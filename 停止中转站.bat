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
$pidFile = Join-Path $root 'data\process.json'
if (!(Test-Path -LiteralPath $pidFile)) { Write-Host '没有找到运行记录，中转站可能已经停止。'; exit 0 }
$record = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
$proc = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
if ($proc) {
    $expected = Join-Path $root 'bin\new-api.exe'
    if ($proc.Path -ne $expected -or $proc.StartTime.ToUniversalTime().ToString('o') -ne $record.started) { throw '进程身份不匹配，已取消停止操作。' }
    Stop-Process -Id $proc.Id
    $proc.WaitForExit(10000) | Out-Null
    Write-Host '中转站已停止，数据库将在下次启动时自动恢复未完成日志。'
}
Remove-Item -LiteralPath $pidFile -Force
