@echo off
setlocal
set "UI=%~dp0WindowsWorker\WorkerDashboard.ps1"
if not exist "%UI%" set "UI=%~dp0WorkerDashboard.ps1"
if not exist "%UI%" (
  echo WorkerDashboard.ps1 not found.
  pause
  exit /b 1
)
start "PiSpider Worker" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -File "%UI%"
endlocal
exit /b 0
