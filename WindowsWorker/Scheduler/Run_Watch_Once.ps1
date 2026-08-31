#Requires -Version 5.1
# Chạy một vòng Watch/Patrol ngay (không cần Task Scheduler)
param(
    [ValidateSet('Watch','Patrol','Scan')]
    [string]$Command = 'Watch',
    [switch]$Quiet
)
$SpiderRoot = Split-Path -Parent $PSScriptRoot
$Main = Join-Path $SpiderRoot 'PiNodeSpider.ps1'
if (-not (Test-Path $Main)) {
    Write-Host "PiNodeSpider.ps1 not found" -ForegroundColor Red
    exit 1
}
$argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Main, '-Command', $Command)
if ($Quiet) { $argsList += '-Quiet' }
Write-Host "[SPIDER] Running $Command once..." -ForegroundColor Cyan
& powershell.exe @argsList
exit $LASTEXITCODE
