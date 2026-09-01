@echo off
setlocal
chcp 65001 >nul
set "BOOT=%~dp0Bootstrap-Worker.ps1"
if not exist "%BOOT%" (
  echo PiSpider Worker bootstrap not found.
  pause
  exit /b 1
)
echo.
echo ============================================================
echo PiSpider Windows Worker - automatic discovery
 echo ============================================================
echo It will find WindowsWorker\LiveWorker.ps1 under:
echo %%APPDATA%%\Pi Network\pi-apps\
echo.
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%BOOT%"
echo.
echo Worker stopped. ExitCode=%ERRORLEVEL%
pause
endlocal
