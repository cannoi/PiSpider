@echo off
setlocal
set "HERE=%~dp0"
set "W=%HERE%WindowsWorker"
if not exist "%W%\LiveWorker.ps1" set "W=%HERE%"
if not exist "%W%\LiveWorker.ps1" (
  echo LiveWorker.ps1 not found next to this file.
  pause
  exit /b 1
)
cd /d "%W%"
start "PiSpider Agent" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%W%\WindowsAgent.ps1"
start "PiSpider Worker" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%W%\LiveWorker.ps1"
echo Started Worker. Leave the PowerShell windows open.
timeout /t 2 >nul
endlocal
