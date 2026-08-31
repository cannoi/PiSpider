@echo off
cd /d "%~dp0"
echo.
echo  [SPIDER] Install PiSpider startup task only
echo  (Run as Administrator recommended)
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install_Watch_Task.ps1" %*
echo.
pause
