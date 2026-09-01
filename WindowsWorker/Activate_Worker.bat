@echo off
setlocal
chcp 65001 >nul
set "BOOT=%~dp0Bootstrap-Worker.ps1"
if not exist "%BOOT%" (
  echo Bootstrap-Worker.ps1 not found.
  pause
  exit /b 1
)
echo PiSpider Worker will locate the correct Pi Network app automatically.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BOOT%"
endlocal
