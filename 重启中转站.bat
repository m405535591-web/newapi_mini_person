@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
call "%~dp0停止中转站.bat" --no-pause
set "RELAY_RESULT=%errorlevel%"
if not "%RELAY_RESULT%"=="0" goto finish
call "%~dp0启动中转站.bat" --no-pause
set "RELAY_RESULT=%errorlevel%"
:finish
echo.
if "%RELAY_RESULT%"=="0" (echo 中转站重启完成。) else (echo 重启未完成，请查看上方提示。)
if /i not "%~1"=="--no-pause" pause
exit /b %RELAY_RESULT%
