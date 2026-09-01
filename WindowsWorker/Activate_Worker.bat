@echo off
setlocal
set "HERE=%~dp0"
set "ROOT="
if exist "%HERE%LiveWorker.ps1" set "ROOT=%HERE%"
if not defined ROOT if exist "%HERE%WindowsWorker\LiveWorker.ps1" set "ROOT=%HERE%WindowsWorker\"
if not defined ROOT (
  echo LiveWorker.ps1 not found.
  echo Run this file from the PiSpider SoloHost app folder,
  echo or copy the WindowsWorker folder into that app folder first.
  pause
  exit /b 1
)
cd /d "%ROOT%"
echo.
echo PiSpider Windows Worker
echo Root: %ROOT%
echo.
echo Starting LiveWorker only...
echo Leave this window open while testing.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\LiveWorker.ps1"
echo.
echo Worker stopped. ExitCode=%ERRORLEVEL%
pause
endlocal
