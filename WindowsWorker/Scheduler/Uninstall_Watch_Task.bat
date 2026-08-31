@echo off
cd /d "%~dp0"
echo Uninstalling Spider tasks...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall_Watch_Task.ps1" %*
echo.
pause
