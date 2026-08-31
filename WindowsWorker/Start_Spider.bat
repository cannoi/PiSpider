@echo off
cd /d "%~dp0"
echo.
echo  [SPIDER] Single runner: PiSpider.exe
echo.
if exist "%~dp0PiSpider.exe" (
  start "" "%~dp0PiSpider.exe"
  exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Dashboard\PiSpiderHost.ps1"
