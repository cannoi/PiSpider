@echo off
setlocal
chcp 65001 >nul
set "BOOT=%~dp0WindowsWorker\Bootstrap-Worker.ps1"
if not exist "%BOOT%" (
  echo PiSpider Worker bootstrap not found.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BOOT%"
endlocal
