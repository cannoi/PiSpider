#Requires -Version 5.1
# ============================================================
# Scheduler/Watch_Loop.ps1
# Vòng Watch liên tục trong process hiện tại (không cần Task Scheduler)
# Dùng khi không cài được scheduled task - chạy trong cửa sổ ẩn / service
# Ctrl+C để dừng
# ============================================================
param(
    [int]$IntervalMinutes = 0,
    [switch]$IncludePatrolAtConfigHour
)

$ErrorActionPreference = 'SilentlyContinue'

# One autonomous loop only. RUN from Dashboard must not create duplicates.
$mutex = New-Object System.Threading.Mutex($false, 'Global\PiSpider-AutonomousRun')
if (-not $mutex.WaitOne(0,$false)) { Write-Host '[SPIDER] Autonomous RUN already active.'; exit 0 }

# RUN must be elevated because downstream Docker/Windows recovery actions may require Administrator.
try {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $pr=New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arg='-NoProfile -ExecutionPolicy Bypass -File "'+$MyInvocation.MyCommand.Path+'" -IncludePatrolAtConfigHour'
        if($IntervalMinutes -gt 0){$arg+=' -IntervalMinutes '+$IntervalMinutes}
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arg | Out-Null
        exit 0
    }
} catch {}
$SpiderRoot = Split-Path -Parent $PSScriptRoot
$Main = Join-Path $SpiderRoot 'PiNodeSpider.ps1'
$ConfigPath = Join-Path $SpiderRoot 'Config.json'
$LiveDir = Join-Path $SpiderRoot 'Data\live'; if(-not(Test-Path $LiveDir)){New-Item -ItemType Directory -Path $LiveDir -Force|Out-Null}
function Write-AutoState([string]$phase,[string]$detail,[int]$percent=0){ try { [ordered]@{Active=$true;Mode='AUTO';Phase=$phase;Detail=$detail;Percent=$percent;At=(Get-Date).ToString('o');Pid=$PID}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $LiveDir 'autonomous.json') -Encoding UTF8 } catch {} }
function Write-RunProgress([string]$phase,[string]$detail,[int]$percent=0){ try { [ordered]@{Action='RUN';Phase=$phase;Detail=$detail;Percent=$percent;At=(Get-Date).ToString('o');Pid=$PID}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $LiveDir 'worker_progress.json') -Encoding UTF8 } catch {} }

if ($IntervalMinutes -le 0 -and (Test-Path $ConfigPath)) {
    try {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $IntervalMinutes = [int]$cfg.Loops.WatchIntervalMinutes
    } catch {}
}
if ($IntervalMinutes -le 0) { $IntervalMinutes = 15 }
if ($IntervalMinutes -lt 5) { $IntervalMinutes = 5 }

$patrolHour = 18
$patrolMinute = 0
if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $cfg.Loops.PatrolHour) { $patrolHour = [int]$cfg.Loops.PatrolHour }
        if ($null -ne $cfg.Loops.PatrolMinute) { $patrolMinute = [int]$cfg.Loops.PatrolMinute }
    } catch {}
}

Write-Host "[SPIDER] Watch loop started - every $IntervalMinutes min (Ctrl+C stop)" -ForegroundColor Cyan
Write-AutoState 'WAITING' "Next watch cycle in $IntervalMinutes min" 0
Write-RunProgress 'RUNNING' 'Autonomous Watch Loop active' 5
$lastPatrolKey = ''

while ($true) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] Watch cycle..." -ForegroundColor Gray
    Write-AutoState 'WATCH' 'Running Watch cycle' 20
    Write-RunProgress 'EXECUTING' 'Running Watch cycle' 20
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $Main -Command Watch -Quiet
    } catch {
        Write-Host "Watch error: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($IncludePatrolAtConfigHour) {
        $now = Get-Date
        $key = $now.ToString('yyyy-MM-dd')
        if ($now.Hour -eq $patrolHour -and $now.Minute -ge $patrolMinute -and $now.Minute -lt ($patrolMinute + $IntervalMinutes) -and $key -ne $lastPatrolKey) {
            Write-Host "[$ts] Daily Patrol..." -ForegroundColor Green
            Write-AutoState 'PATROL' 'Running scheduled Patrol' 50
            Write-RunProgress 'EXECUTING' 'Running scheduled Patrol' 50
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $Main -Command Patrol -Quiet
            $lastPatrolKey = $key
        }
    }

    Write-AutoState 'WAITING' "Next watch cycle in $IntervalMinutes min" 0
    Write-RunProgress 'WAITING' "Next watch cycle in $IntervalMinutes min" 0
    Start-Sleep -Seconds ($IntervalMinutes * 60)
}
