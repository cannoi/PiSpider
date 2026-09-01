@echo off
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "ROOT="
if exist "%HERE%LiveWorker.ps1" set "ROOT=%HERE%"
if not defined ROOT if exist "%HERE%WindowsWorker\LiveWorker.ps1" set "ROOT=%HERE%WindowsWorker\"
if not defined ROOT (
  for /d %%D in ("%USERPROFILE%\AppData\Roaming\Pi Network\pi-apps\*") do (
    if exist "%%D\WindowsWorker\LiveWorker.ps1" set "ROOT=%%D\WindowsWorker\"
  )
)
if not defined ROOT (
  echo LiveWorker.ps1 not found. Run Start-Worker.cmd in the SoloHost app folder.
  pause
  exit /b 1
)
cd /d "%ROOT%"
start "PiSpider Agent" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%CD%\WindowsAgent.ps1"
start "PiSpider Worker" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%CD%\LiveWorker.ps1"
echo Started from %CD%
timeout /t 2 >nul
endlocal
