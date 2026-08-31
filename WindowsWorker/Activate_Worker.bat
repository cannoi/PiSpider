@echo off
cd /d "%~dp0"
start "PiSpider Worker" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LiveWorker.ps1"
echo Worker started. You can close this window.
