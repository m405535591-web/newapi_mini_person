@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "RELAY_SCRIPT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $text=[IO.File]::ReadAllText($env:RELAY_SCRIPT,[Text.Encoding]::UTF8); $body=($text -split '(?m)^# POWERSHELL\r?$',2)[1]; if (!$body) { throw '脚本内容缺失' }; & ([ScriptBlock]::Create($body)) } catch { Write-Host ('操作失败：' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"
set "RELAY_RESULT=%errorlevel%"
echo.
if not "%RELAY_RESULT%"=="0" echo 操作未完成，请查看上方提示。
if /i not "%~1"=="--no-pause" pause
exit /b %RELAY_RESULT%
# POWERSHELL
$ErrorActionPreference = 'Stop'
$root = Split-Path $env:RELAY_SCRIPT -Parent
$exe = Join-Path $root 'bin\new-api.exe'
$pidFile = Join-Path $root 'data\process.json'
if (!(Test-Path -LiteralPath $exe)) { throw '找不到 bin/new-api.exe 程序' }
if (Test-Path -LiteralPath $pidFile) {
    $record = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
    $existing = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
    if ($existing -and $existing.Path -eq $exe) { Write-Host "中转站已在运行，进程编号： $($existing.Id)"; exit 0 }
}
$cfg = Get-Content -LiteralPath (Join-Path $root 'config\settings.json') -Raw | ConvertFrom-Json
if (Get-NetTCPConnection -LocalPort $cfg.port -State Listen -ErrorAction SilentlyContinue) { throw "端口 $($cfg.port) 已被占用" }
$values = @{
    CRITICAL_RATE_LIMIT_ENABLE = 'false'
    USER_SESSION_ISSUANCE_LIMIT = '2000'
    USER_SESSION_ACTIVE_LIMIT = '500'
    TEMP = (Join-Path $root 'temp'); TMP = (Join-Path $root 'temp')
    SQLITE_PATH = (Join-Path $root 'data\new-api.db')
    SESSION_SECRET = $cfg.session_secret; CRYPTO_SECRET = $cfg.crypto_secret
    PORT = [string]$cfg.port; TZ = 'Asia/Hong_Kong'; GIN_MODE = 'release'
    DEFAULT_LANGUAGE = 'zh-CN'; DEBUG = 'false'; ENABLE_PPROF = 'false'
    HTTP_PROXY = $cfg.upstream_proxy; HTTPS_PROXY = $cfg.upstream_proxy; ALL_PROXY = $cfg.upstream_proxy
    NO_PROXY = $cfg.no_proxy
    SQL_DSN = ''; LOG_SQL_DSN = ''; REDIS_CONN_STRING = ''
    SESSION_COOKIE_SECURE = 'false'; SESSION_COOKIE_TRUSTED_URL = ''
}
# Keep this handle open until PowerShell exits, including console closure.
# All child processes inherit membership; Windows kills them on handle close.
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class RelayConsoleJob {
    private static IntPtr job;
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimits {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters {
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimits {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr handle, int infoClass,
        ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr handle, IntPtr process);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    public static void Attach() {
        if (job != IntPtr.Zero) return;
        IntPtr handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero) throw new Win32Exception();
        var limits = new ExtendedLimits();
        limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if (!SetInformationJobObject(handle, 9, ref limits,
                (uint)Marshal.SizeOf(typeof(ExtendedLimits))) ||
                !AssignProcessToJobObject(handle, GetCurrentProcess())) {
            int error = Marshal.GetLastWin32Error();
            CloseHandle(handle);
            throw new Win32Exception(error);
        }
        job = handle;
    }
}
"@
[RelayConsoleJob]::Attach()
$proc = $null
$old = @{}
try {
    foreach ($key in $values.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process')
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logDir = Join-Path $root 'logs'
    $arguments = '--port ' + $cfg.port + ' --log-dir "' + $logDir + '"'
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $root -NoNewWindow -RedirectStandardOutput (Join-Path $logDir "stdout-$stamp.log") -RedirectStandardError (Join-Path $logDir "stderr-$stamp.log") -PassThru
    @{pid=$proc.Id; started=$proc.StartTime.ToUniversalTime().ToString('o'); executable=$exe} | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding UTF8
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($proc.HasExited) { throw "中转站启动失败，请查看 logs/stderr-$stamp.log" }
        try {
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:$($cfg.port)/api/status" -TimeoutSec 2
            if ($response.success) { $ready=$true; break }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (!$ready) { throw '启动检查超时，请查看 logs 目录。' }
    Write-Host "中转站已启动： http://localhost:$($cfg.port) (PID $($proc.Id))"
    Write-Host "支持局域网访问，浏览器打开本机 IP 地址的 $($cfg.port) 端口。"
    Write-Host '请保持此 CMD 窗口打开；关闭窗口或按 Ctrl+C 将自动停止中转站。'
    Write-Host "运行日志：$logDir"
    while (!$proc.WaitForExit(500)) {}
    Write-Host '中转站已停止。'
    if ($proc.ExitCode -ne 0) { throw "服务进程已退出（代码 $($proc.ExitCode)），请查看 logs 目录。" }
} finally {
    if ($proc) {
        if (!$proc.HasExited) { Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $pidFile) {
            $current = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
            if ($current.pid -eq $proc.Id -and $current.started -eq $proc.StartTime.ToUniversalTime().ToString('o')) {
                Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    foreach ($key in $old.Keys) { [Environment]::SetEnvironmentVariable($key, $old[$key], 'Process') }
}
