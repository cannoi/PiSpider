@echo off
setlocal
set "HERE=%~dp0"
set "W=%HERE%WindowsWorker"
if not exist "%W%\LiveWorker.ps1" set "W=%HERE%"
if not exist "%W%\LiveWorker.ps1" (
  echo LiveWorker.ps1 not found. Run this from the PiSpider SoloHost app folder.
  pause
  exit /b 1
)
cd /d "%W%"
echo.
echo ============================================================
echo PiSpider Windows Worker
echo ============================================================
echo Root: %W%
echo.
echo Starting LiveWorker only (single command consumer)...
echo Keep this window open while testing.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%W%\LiveWorker.ps1"
echo.
echo Worker stopped. ExitCode=%ERRORLEVEL%
pause
endlocal
