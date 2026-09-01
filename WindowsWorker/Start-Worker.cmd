@echo off
setlocal
set "ROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
start "PiSpider-Live" /MIN "%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ROOT%LiveWorker.ps1"
if exist "%ROOT%WindowsAgent.ps1" start "PiSpider-Agent" /MIN "%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ROOT%WindowsAgent.ps1"
if exist "%ROOT%UiServer.ps1" start "PiSpider-UI" /MIN "%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ROOT%UiServer.ps1"
endlocal
exit /b 0
