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
if (Get-Process -Name 'new-api' -ErrorAction SilentlyContinue | Where-Object Path -EQ $exe) { throw '请先双击“停止中转站.bat”，再清理日志缓存。' }
$cutoff = (Get-Date).AddDays(-7)
Get-ChildItem -LiteralPath (Join-Path $root 'logs') -File | Where-Object LastWriteTime -LT $cutoff | Remove-Item -Force
foreach ($name in @('temp','cache')) {
    $target = [IO.Path]::GetFullPath((Join-Path $root $name))
    if (!$target.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '目标路径不在项目内，已取消操作。' }
    $items = @(Get-ChildItem -LiteralPath $target -Force -Recurse)
    if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw '目录内包含链接或重解析点，已取消清理。' }
    Get-ChildItem -LiteralPath $target -Force | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
Write-Host '已清理七天前的文件日志以及临时文件、缓存；数据库调用记录和备份保留。'
