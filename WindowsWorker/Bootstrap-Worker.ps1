#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NoComposeSync,
    [switch]$NoRestartSoloHost,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'

function Find-PiAppsRoot {
    $candidates = @()
    if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'Pi Network\pi-apps') }
    $candidates += (Join-Path $HOME 'AppData\Roaming\Pi Network\pi-apps')
    foreach ($p in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $p -PathType Container) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

function Find-WorkerRoot {
    $here = $PSScriptRoot
    if (Test-Path (Join-Path $here 'LiveWorker.ps1')) { return $here }
    $apps = Find-PiAppsRoot
    if (-not $apps) { throw "Pi Network app folder not found: %APPDATA%\Pi Network\pi-apps" }
    $hits = @(Get-ChildItem -LiteralPath $apps -Filter 'LiveWorker.ps1' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\WindowsWorker\\LiveWorker\.ps1$' })
    if (-not $hits) { throw "WindowsWorker\LiveWorker.ps1 was not found under $apps" }
    $best = $hits | Sort-Object @{Expression={ if ($_.FullName -match 'pispider|hybrid|solohost') { 0 } else { 1 } }}, FullName | Select-Object -First 1
    return $best.Directory.FullName
}

function Get-AppRoot([string]$WorkerRoot) { return (Split-Path -Parent $WorkerRoot) }

$workerRoot = Find-WorkerRoot
$workerRoot = (Resolve-Path -LiteralPath $workerRoot).Path
$appRoot = Get-AppRoot $workerRoot
$env:PINODE_SPIDER_ROOT = $workerRoot

Write-Host "[BOOT] PiSpider Worker found: $workerRoot" -ForegroundColor Green
Write-Host "[BOOT] SoloHost app root: $appRoot"

$ui = Join-Path $workerRoot 'WorkerDashboard.ps1'
$live = Join-Path $workerRoot 'LiveWorker.ps1'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $ui) {
    Write-Host '[BOOT] Opening Worker dashboard (consoles stay hidden)...' -ForegroundColor Cyan
    Start-Process -FilePath $ps -ArgumentList @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File', $ui) | Out-Null
    exit 0
}
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$live)
if ($Once) { $args += '-Once' }
Write-Host '[BOOT] Dashboard missing — starting hidden LiveWorker.' -ForegroundColor Yellow
Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden | Out-Null
exit 0
