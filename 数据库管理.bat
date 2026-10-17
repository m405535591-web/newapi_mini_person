@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "RELAY_SCRIPT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $text=[IO.File]::ReadAllText($env:RELAY_SCRIPT,[Text.Encoding]::UTF8); $body=($text -split '(?m)^# POWERSHELL\r?$',2)[1]; & ([ScriptBlock]::Create($body)) } catch { Write-Host ('操作失败：' + $_.Exception.Message) -ForegroundColor Red; exit 1 }"
set "RELAY_RESULT=%errorlevel%"
echo.
if /i not "%~1"=="--no-pause" pause
exit /b %RELAY_RESULT%
# POWERSHELL
$ErrorActionPreference = 'Stop'
$root = Split-Path $env:RELAY_SCRIPT -Parent
while ($true) {
    Write-Host ''
    Write-Host '========== 中转站数据库管理 =========='
    Write-Host '1. 删除所有用户的全部签到记录（含历史记录）'
    Write-Host '0. 退出'
    $choice = Read-Host '请选择操作'
    if ($choice -eq '0') { break }
    if ($choice -ne '1') { Write-Host '无效选项，请重新选择。'; continue }
    Write-Host '删除后所有用户可重新签到；已发放额度保留，再次签到会再次发放奖励。' -ForegroundColor Yellow
    Write-Host '执行前自动备份数据库，运行中的服务将短暂停止。'
    if ((Read-Host '确认删除请输入 DELETE，其他输入取消') -cne 'DELETE') { Write-Host '已取消。'; continue }
    & python --version
    if ($LASTEXITCODE -ne 0) { throw '需要可用的 Python 3，尚未修改数据库。' }
    $wasRunning = $false
    $pidFile = Join-Path $root 'data\process.json'
    if (Test-Path -LiteralPath $pidFile) {
        $record = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
        $proc = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if ($proc) {
            if ($proc.Path -ne (Join-Path $root 'bin\new-api.exe') -or $proc.StartTime.ToUniversalTime().ToString('o') -ne $record.started) { throw '进程身份不匹配，已取消操作。' }
            $wasRunning = $true
        }
    }
    & (Join-Path $root '停止中转站.bat') --no-pause
    if ($LASTEXITCODE -ne 0) { throw '停止服务失败，尚未修改数据库。' }
    try {
        & python -X utf8 (Join-Path $root 'scripts\database_manage.py') --root $root
        if ($LASTEXITCODE -ne 0) { throw '数据库操作失败，请查看上方提示。' }
    } finally {
        if ($wasRunning) {
            & (Join-Path $root '启动中转站.bat') --no-pause
            if ($LASTEXITCODE -ne 0) { throw '服务恢复失败，请手动运行启动中转站.bat。' }
        }
    }
}
