@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
call "%~dp0停止中转站.bat" --no-pause
set "RELAY_RESULT=%errorlevel%"
if not "%RELAY_RESULT%"=="0" goto finish
echo 正在重新启动，服务运行期间请保持此 CMD 窗口打开。
call "%~dp0启动中转站.bat" --no-pause
set "RELAY_RESULT=%errorlevel%"
:finish
echo.
if "%RELAY_RESULT%"=="0" (echo 中转站运行已结束。) else (echo 服务运行异常，请查看上方提示。)
if /i not "%~1"=="--no-pause" pause
exit /b %RELAY_RESULT%
