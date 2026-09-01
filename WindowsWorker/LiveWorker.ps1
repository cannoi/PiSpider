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

# Single-instance guard: every launcher and direct PowerShell invocation share the same mutex.
$script:WorkerMutex = New-Object System.Threading.Mutex($false, 'Global\PiSpider-WindowsWorker')
if (-not $script:WorkerMutex.WaitOne(0, $false)) {
    Write-Host '[WORKER] Already running. This window will not start a second Worker.' -ForegroundColor Yellow
    exit 0
}

function Write-AtomicText {
    param([string]$Path, [string]$Text)
    $tmp = "$Path.pispider.tmp"
    [IO.File]::WriteAllText($tmp, $Text, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Sync-SoloHostCompose {
    param([string]$Root)
    $compose = Join-Path (Split-Path -Parent $Root) 'docker-compose.yml'
    if (-not (Test-Path -LiteralPath $compose)) { return $false }
    $canonical = Get-Content -LiteralPath $compose -Raw -Encoding UTF8
    # This package's compose is the canonical SoloHost channel definition.
    # A separate immutable copy is embedded beside the Worker by the launcher.
    $canonicalFile = Join-Path $Root 'Engine\SoloHost.docker-compose.yml'
    if (-not (Test-Path -LiteralPath $canonicalFile)) { return $false }
    $desired = Get-Content -LiteralPath $canonicalFile -Raw -Encoding UTF8
    if (($canonical -replace "`r`n", "`n") -eq ($desired -replace "`r`n", "`n")) { return $false }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $compose -Destination "$compose.pispider-backup-$stamp" -Force
    Write-AtomicText -Path $compose -Text $desired
    return $true
}

function Restart-SoloHostApp {
    param([string]$Root)
    $appRoot = Split-Path -Parent $Root
    $docker = Get-Command docker.exe -ErrorAction SilentlyContinue
    if (-not $docker) { throw 'Docker CLI not found.' }
    $request = Join-Path $Root 'Data\live\solohost_restart_request.json'
    $req = [ordered]@{ Action='STOP_START'; Service='pispider-core'; RequestedAt=(Get-Date).ToString('o'); Source='windows-worker' }
    $json = $req | ConvertTo-Json -Depth 4
    try { Write-AtomicText -Path $request -Text $json } catch {}
    Push-Location $appRoot
    try {
        Write-Host '[WORKER] SoloHost: STOP pispider-core' -ForegroundColor Cyan
        & $docker.Source compose stop pispider-core
        if ($LASTEXITCODE -ne 0) { throw "docker compose stop failed ($LASTEXITCODE)" }
        Write-Host '[WORKER] SoloHost: START pispider-core with updated compose' -ForegroundColor Cyan
        & $docker.Source compose up -d --force-recreate pispider-core
        if ($LASTEXITCODE -ne 0) { throw "docker compose up failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
}

# Synchronize only when the existing compose differs. Never overwrite on every start.
try {
    $composeChanged = Sync-SoloHostCompose -Root $script:SpiderRoot
    if ($composeChanged) {
        Write-Host '[WORKER] SoloHost docker-compose.yml updated; applying STOP -> START.' -ForegroundColor Yellow
        try { Restart-SoloHostApp -Root $script:SpiderRoot }
        catch { Write-Warning "SoloHost restart failed: $($_.Exception.Message). The compose backup and new compose remain in place." }
    }
} catch { Write-Warning "SoloHost compose sync skipped: $($_.Exception.Message)" }

$bus = Join-Path $script:SpiderRoot 'Engine\LiveBus.ps1'
if (-not (Test-Path -LiteralPath $bus)) { throw "Missing Engine\LiveBus.ps1" }
. $bus

$main = Join-Path $script:SpiderRoot 'PiNodeSpider.ps1'
if (-not (Test-Path -LiteralPath $main)) { throw "Missing PiNodeSpider.ps1" }

Write-Host "[WORKER] PiSpider Hybrid Worker  root=$($script:SpiderRoot)"
Write-Host "[WORKER] Bus=$(Get-SpiderLiveBusDir)"
Write-Host "[WORKER] Poll=${PollSeconds}s   Activate by Core command.json"

function Get-CoreHeartbeatUrls {
    $ports = New-Object System.Collections.Generic.List[int]
    # Prefer the SoloHost port declared by the app config, then known legacy/current ports.
    # Do NOT read the Pi app's config.json here. Pi Desktop may protect that file
    # with ACLs even when the Worker itself is runnable. The known SoloHost
    # localhost ports are enough and avoid noisy AccessDenied errors.
    $envPort = 0
    try { $envPort = [int]$env:PISPIDER_SOLOHOST_PORT } catch {}
    if ($envPort -gt 0 -and -not $ports.Contains($envPort)) { [void]$ports.Add($envPort) }
    foreach ($port in @(18770,18780)) {
        if (-not $ports.Contains($port)) { [void]$ports.Add($port) }
    }
    foreach ($port in $ports) {
        "http://127.0.0.1:$port/api/worker-heartbeat"
    }
}

function Send-CoreHeartbeat {
    param([bool]$Busy = $false, [string]$Note = '')
    # File LiveBus remains the primary channel. Localhost HTTP is a second path so
    # SoloHost can verify a Worker even when Docker/Windows mount paths differ.
    $payload = [ordered]@{
        Alive = $true
        Busy = $Busy
        At = (Get-Date).ToString('o')
        Pack = 'windows-worker'
        Note = $Note
        Pid = $PID
        Root = $script:SpiderRoot
    }
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    foreach ($uri in (Get-CoreHeartbeatUrls)) {
        try {
            Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 3 -ErrorAction Stop | Out-Null
            break
        } catch { }
    }
}

function Write-WorkerHeartbeat {
    param([bool]$Busy = $false, [string]$Note = '')
    Write-SpiderLiveHeartbeat -Busy $Busy -Note $Note
    Send-CoreHeartbeat -Busy $Busy -Note $Note
}

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
    Write-WorkerHeartbeat -Busy $true -Note $cmd
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
    Write-WorkerHeartbeat -Busy $false -Note 'idle'
}

Write-WorkerHeartbeat -Busy $false -Note 'waiting'
$lastId = ''
while ($true) {
    try {
        Write-WorkerHeartbeat -Busy $false -Note 'waiting'
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
