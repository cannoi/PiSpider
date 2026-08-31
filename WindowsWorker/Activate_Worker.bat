@echo off
setlocal
set "HERE=%~dp0"
set "ROOT="

if exist "%HERE%LiveWorker.ps1" set "ROOT=%HERE%"
if not defined ROOT if exist "%HERE%WindowsWorker\LiveWorker.ps1" set "ROOT=%HERE%WindowsWorker\"
if not defined ROOT if exist "%USERPROFILE%\AppData\Roaming\Pi Network\pi-apps\gothicab-piguard-worker\WindowsWorker\LiveWorker.ps1" (
  set "ROOT=%USERPROFILE%\AppData\Roaming\Pi Network\pi-apps\gothicab-piguard-worker\WindowsWorker\"
)

if not defined ROOT (
  echo LiveWorker.ps1 not found.
  echo Put this BAT in the WindowsWorker folder, not in Downloads.
  pause
  exit /b 1
)

cd /d "%ROOT%"
echo Starting agent + worker
echo Root: %CD%
start "PiSpider Agent" powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\WindowsAgent.ps1"
start "PiSpider Worker" powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\LiveWorker.ps1"
echo Started. You can close this window.
timeout /t 3 >nul
endlocal
