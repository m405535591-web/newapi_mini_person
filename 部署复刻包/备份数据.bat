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
$running = Get-Process -Name 'new-api' -ErrorAction SilentlyContinue | Where-Object Path -EQ $exe
if ($running) { throw '请先双击“停止中转站.bat”，再备份数据。' }
$dest = Join-Path $root ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'config') -Destination $dest -Recurse
New-Item -ItemType Directory -Path (Join-Path $dest 'data') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $root 'data') -File | Where-Object Name -NE 'process.json' | Copy-Item -Destination (Join-Path $dest 'data')
Copy-Item -LiteralPath (Join-Path $root 'bin\version.json') -Destination $dest
Write-Host "备份已保存到： $dest"
Write-Host '备份包含配置和密钥，请妥善保管。'
