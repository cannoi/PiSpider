#Requires -Version 5.1
# PiSpider Hybrid Worker — runs on Windows Node PC
# Reads Data\live\command.json written by SoloHost Core
[CmdletBinding()]
param(
    [int]$PollSeconds = 15,
    [switch]$Once
)

$ErrorActionPreference = 'Continue'
$script:SpiderRoot = $PSScriptRoot
if (-not $script:SpiderRoot) { $script:SpiderRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$env:PINODE_SPIDER_ROOT = $script:SpiderRoot

$bus = Join-Path $script:SpiderRoot 'Engine\LiveBus.ps1'
if (-not (Test-Path -LiteralPath $bus)) { throw "Missing Engine\LiveBus.ps1" }
. $bus

$main = Join-Path $script:SpiderRoot 'PiNodeSpider.ps1'
if (-not (Test-Path -LiteralPath $main)) { throw "Missing PiNodeSpider.ps1" }

Write-Host "[WORKER] PiSpider Hybrid Worker  root=$($script:SpiderRoot)"
Write-Host "[WORKER] Bus=$(Get-SpiderLiveBusDir)"
Write-Host "[WORKER] Poll=${PollSeconds}s   Activate by Core command.json"

function Invoke-LiveAction {
    param([string]$Action)
    $map = @{
        SCAN    = 'Scan'
        PATROL  = 'Patrol'
        STATUS  = 'Status'
        REPAIR  = 'Repair'
        DIGEST  = 'DailyReport'
        WATCH   = 'Watch'
    }
    $cmd = $map[$Action]
    if (-not $cmd) {
        Write-SpiderLiveResult -Action $Action -Status 'SKIP' -Summary "Unknown action $Action"
        return
    }
    Write-SpiderLiveHeartbeat -Busy $true -Note $cmd
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $ps -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File', $main, '-Command', $cmd, '-Quiet'
    ) -WorkingDirectory $script:SpiderRoot -Wait -PassThru -WindowStyle Hidden
    $code = 0
    try { $code = [int]$p.ExitCode } catch {}
    Sync-SpiderLiveApproval
    $health = $null
    $summary = "exit=$code"
    $rep = Join-Path $script:SpiderRoot 'Data\last_report.json'
    if (Test-Path $rep) {
        try {
            $j = Get-Content $rep -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.Health.Overall) { $health = [string]$j.Health.Overall }
            if ($j.Decision.Action) { $summary = "decision=$($j.Decision.Action) health=$health" }
        } catch {}
    }
    Write-SpiderLiveResult -Action $Action -Status $(if ($code -eq 0) { 'OK' } else { 'FAIL' }) -Summary $summary -Health $health
    Write-SpiderLiveHeartbeat -Busy $false -Note 'idle'
}

Write-SpiderLiveHeartbeat -Busy $false -Note 'waiting'
$lastId = ''
while ($true) {
    try {
        Write-SpiderLiveHeartbeat -Busy $false -Note 'waiting'
        $cmd = Read-SpiderLiveCommand
        if ($cmd -and $cmd.Id -and $cmd.Id -ne $lastId) {
            $act = ([string]$cmd.Action).ToUpper()
            if ($act -in @('APPROVE','DENY')) {
                $pending = Join-Path $script:SpiderRoot 'Data\pending_approval.json'
                if (Test-Path $pending) {
                    try {
                        $j = Get-Content $pending -Raw | ConvertFrom-Json
                        $j | Add-Member Status $act -Force
                        $j | Add-Member ResolvedAt ((Get-Date).ToString('o')) -Force
                        ($j | ConvertTo-Json) | Set-Content $pending -Encoding UTF8
                    } catch {}
                }
                Write-SpiderLiveResult -Action $act -Status 'OK' -Summary "User $act on Core"
                if ($act -eq 'APPROVE') { Invoke-LiveAction -Action 'REPAIR' }
                Clear-SpiderLiveCommand
                $lastId = [string]$cmd.Id
            } else {
                Invoke-LiveAction -Action $act
                Clear-SpiderLiveCommand
                $lastId = [string]$cmd.Id
            }
        }
    } catch {
        Write-Host "[WORKER] $($_.Exception.Message)"
    }
    if ($Once) { break }
    Start-Sleep -Seconds ([Math]::Max(5, $PollSeconds))
}
