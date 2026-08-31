@echo off
cd /d "%~dp0"
echo [PiSpider] Hybrid Worker - waiting for SoloHost Core commands
echo Bus folder: %CD%\Data\live
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LiveWorker.ps1"
pause
