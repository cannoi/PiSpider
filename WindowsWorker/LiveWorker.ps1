#Requires -Version 5.1
# PiSpider Hybrid Worker — runs on Windows Node PC
# Reads Data\live\command.json written by SoloHost Core
[CmdletBinding()]
param(
    [int]$PollSeconds = 2,
    [switch]$Once
)

$ErrorActionPreference = 'Continue'
$script:SpiderRoot = $PSScriptRoot
if (-not $script:SpiderRoot) { $script:SpiderRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$env:PINODE_SPIDER_ROOT = $script:SpiderRoot

# Pi Node recovery may require Administrator rights. Elevate once at the launcher boundary.
try {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $pr=New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $args='-NoProfile -ExecutionPolicy Bypass -File "'+$MyInvocation.MyCommand.Path+'"'
        if($PollSeconds){$args+=' -PollSeconds '+$PollSeconds}
        if($Once){$args+=' -Once'}
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -ArgumentList $args -WindowStyle Hidden | Out-Null
        Write-Host '[WORKER] Administrator permission requested. The elevated Worker will continue.' -ForegroundColor Yellow
        exit 0
    }
} catch { Write-Warning "Administrator elevation check failed: $($_.Exception.Message)" }

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

function Send-CoreEvent {
    param([string]$Type, [hashtable]$Payload)
    $body = [ordered]@{ Type=$Type; Pack='windows-worker' }
    foreach($k in $Payload.Keys){ $body[$k]=$Payload[$k] }
    $json = $body | ConvertTo-Json -Depth 8 -Compress
    foreach ($uri in (Get-CoreEventUrls)) {
        try { Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 1 -ErrorAction Stop | Out-Null; break } catch {}
    }
}
function Get-CoreEventUrls {
    $ports = New-Object System.Collections.Generic.List[int]
    $envPort=0; try{$envPort=[int]$env:PISPIDER_SOLOHOST_PORT}catch{}
    if($envPort -gt 0){[void]$ports.Add($envPort)}
    foreach($port in @(18770,18780)){if(-not $ports.Contains($port)){[void]$ports.Add($port)}}
    foreach($port in $ports){ "http://127.0.0.1:$port/api/worker-event" }
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
            Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 1 -ErrorAction Stop | Out-Null
            break
        } catch { }
    }
    try { Send-CoreEvent -Type 'HEARTBEAT' -Payload @{Alive=$true;Busy=$Busy;At=$payload.At;Note=$Note;Pid=$PID;Root=$script:SpiderRoot} } catch {}
}

function Write-WorkerHeartbeat {
    param([bool]$Busy = $false, [string]$Note = '')
    Write-SpiderLiveHeartbeat -Busy $Busy -Note $Note
    Send-CoreHeartbeat -Busy $Busy -Note $Note
}

function Write-WorkerProgress {
    param([string]$Action,[string]$Phase,[string]$Detail='',[int]$Percent=0)
    $at=(Get-Date).ToString('o'); $obj=[ordered]@{Action=$Action;Phase=$Phase;Detail=$Detail;Percent=$Percent;At=$at;Pid=$PID}
    try { Write-SpiderLiveJson -Name 'worker_progress.json' -Object $obj } catch {}
    try { Send-CoreEvent -Type 'PROGRESS' -Payload @{Action=$Action;Phase=$Phase;Detail=$Detail;Percent=$Percent;At=$at;Pid=$PID} } catch {}
    try { Send-CoreEvent -Type 'LOG' -Payload @{Action=$Action;Level='INFO';Message=("$Phase | $Detail | $Percent%");At=$at;Pid=$PID} } catch {}
}
function Write-WorkerState {
    param([bool]$Active=$true,[string]$Mode='AUTO',[string]$Note='')
    $at=(Get-Date).ToString('o'); $obj=[ordered]@{Active=$Active;Mode=$Mode;Note=$Note;At=$at;Pid=$PID}
    try { Write-SpiderLiveJson -Name 'worker_state.json' -Object $obj } catch {}
    try { Send-CoreEvent -Type 'STATE' -Payload @{Active=$Active;Mode=$Mode;Note=$Note;At=$at;Pid=$PID} } catch {}
}

function Invoke-LiveAction {
    param([string]$Action)
    $map = @{
        RUN     = 'Run'
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
    Write-WorkerProgress -Action $Action -Phase 'RUNNING' -Detail 'Executing PiNodeSpider' -Percent 10
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $stdout = Join-Path $script:SpiderRoot 'Data\live\worker.stdout.log'
    $stderr = Join-Path $script:SpiderRoot 'Data\live\worker.stderr.log'
    Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $main + '" -Command ' + $cmd + ' -Quiet'
    $psi.WorkingDirectory = $script:SpiderRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    Write-WorkerProgress -Action $Action -Phase 'STARTED' -Detail 'PiNodeSpider process started' -Percent 20
    [void]$proc.Start()
    Write-WorkerProgress -Action $Action -Phase 'EXECUTING' -Detail 'Waiting for result' -Percent 50
    $outText = $proc.StandardOutput.ReadToEnd()
    $errText = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $code = [int]$proc.ExitCode
    Write-WorkerProgress -Action $Action -Phase 'VERIFYING' -Detail ('Exit code '+$code) -Percent 85
    try { [IO.File]::WriteAllText($stdout,$outText,(New-Object Text.UTF8Encoding($false))) } catch {}
    try { [IO.File]::WriteAllText($stderr,$errText,(New-Object Text.UTF8Encoding($false))) } catch {}
    $errTail = ''
    try { if(Test-Path $stderr){ $errTail = ((Get-Content $stderr -Tail 8 -ErrorAction SilentlyContinue) -join ' ') } } catch {}
    if($code -ne 0 -and $errTail){ Write-SpiderLog "$cmd failed exit=$code stderr=$errTail" 'ERROR' }
    Sync-SpiderLiveApproval
    $health = $null
    $summary = "exit=$code"; if($errTail){$summary += " | $errTail"}
    $rep = Join-Path $script:SpiderRoot 'Data\last_report.json'
    if (Test-Path $rep) {
        try {
            $j = Get-Content $rep -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.Health.Overall) { $health = [string]$j.Health.Overall }
            if ($j.Decision.Action) { $summary = "decision=$($j.Decision.Action) health=$health" }
        } catch {}
    }
    $finalStatus = if ($code -eq 0) { 'OK' } else { 'FAIL' }
    Write-SpiderLiveResult -Action $Action -Status $finalStatus -Summary $summary -Health $health
    try { Send-CoreEvent -Type 'RESULT' -Payload @{Action=$Action;Status=$finalStatus;Summary=$summary;Health=$health;At=(Get-Date).ToString('o');Pid=$PID} } catch {}
    Write-WorkerProgress -Action $Action -Phase 'DONE' -Detail $summary -Percent 100
    Write-WorkerHeartbeat -Busy $false -Note 'idle'
    Write-WorkerState -Active $true -Mode 'AUTO' -Note 'idle'
}

try { Send-CoreEvent -Type 'LOG' -Payload @{Action='WORKER';Level='INFO';Message='Windows Worker online; AUTO polling started';At=(Get-Date).ToString('o');Pid=$PID} } catch {}
Write-WorkerHeartbeat -Busy $false -Note 'waiting'
Write-WorkerState -Active $true -Mode 'AUTO' -Note 'waiting'
$lastId = ''
while ($true) {
    try {
        Write-WorkerHeartbeat -Busy $false -Note 'waiting'
        $cmd = Read-SpiderLiveCommand
        if ($cmd -and $cmd.Id -and $cmd.Id -ne $lastId) {
            $act = ([string]$cmd.Action).ToUpper()
            Write-WorkerProgress -Action $act -Phase 'RECEIVED' -Detail 'Command received from SoloHost' -Percent 5
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
    Start-Sleep -Seconds ([Math]::Max(2, $PollSeconds))
}
