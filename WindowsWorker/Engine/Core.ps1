# ============================================================
# PiNode Spider Engine - Core.ps1
# Safety | Protected Zone | Logging | Events | History | Helpers
# ============================================================

$script:SpiderRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $script:SpiderRoot) { $script:SpiderRoot = $PSScriptRoot }
$script:ConfigPath   = Join-Path $script:SpiderRoot "Config.json"
$script:RulesPath    = Join-Path $script:SpiderRoot "Rules\Rules.json"
$script:ProtectedPath= Join-Path $script:SpiderRoot "Rules\Protected.json"
$script:RecoveryPath = Join-Path $script:SpiderRoot "Rules\Recovery.json"
$script:DataDir      = Join-Path $script:SpiderRoot "Data"
$script:LogDir       = Join-Path $script:SpiderRoot "Logs"
$script:HistoryPath  = Join-Path $script:DataDir "History.json"
$script:LatestPath   = Join-Path $script:DataDir "Latest.json"
$script:MapPath      = Join-Path $script:DataDir "SystemMap.json"
$script:BaselinePath = Join-Path $script:DataDir "Baseline.json"
$script:EventsPath   = Join-Path $script:DataDir "Events.json"
$script:CircuitPath  = Join-Path $script:DataDir "CircuitBreaker.json"

New-Item -ItemType Directory -Path $script:DataDir, $script:LogDir -Force | Out-Null

function Get-SpiderConfig {
    if (Test-Path $script:ConfigPath) {
        return Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-SpiderRules {
    if (Test-Path $script:RulesPath) {
        return Get-Content $script:RulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-ProtectedZone {
    if (Test-Path $script:ProtectedPath) {
        return Get-Content $script:ProtectedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-RecoveryPolicy {
    if (Test-Path $script:RecoveryPath) {
        return Get-Content $script:RecoveryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Write-SpiderLog {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG','ACTION','DIAG','EVENT','PATROL')]
        [string]$Level = 'INFO'
    )
    $logFile = Join-Path $script:LogDir ("Spider_{0:yyyy-MM-dd}.log" -f (Get-Date))
    $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Message
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    $color = switch ($Level) {
        'ERROR'  { 'Red' }
        'WARN'   { 'Yellow' }
        'ACTION' { 'Cyan' }
        'DIAG'   { 'Magenta' }
        'EVENT'  { 'DarkCyan' }
        'PATROL' { 'Green' }
        default  { 'White' }
    }
    Write-Host $line -ForegroundColor $color
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-ProtectedProcess {
    param([string]$Name)
    $zone = Get-ProtectedZone
    $list = if ($zone) { $zone.Processes } else { (Get-SpiderConfig).ProtectedProcesses }
    foreach ($p in $list) {
        if ($Name -like "*$p*") { return $true }
    }
    return $false
}

function Test-CleanupCandidate {
    param([string]$Name)
    $cfg = Get-SpiderConfig
    foreach ($p in $cfg.CleanupCandidates) {
        if ($Name -like "*$p*") { return $true }
    }
    return $false
}

function Test-ProtectedPath {
    param([string]$Path)
    $zone = Get-ProtectedZone
    if (-not $zone) { return $false }
    foreach ($pat in $zone.Paths) {
        $expanded = [Environment]::ExpandEnvironmentVariables($pat)
        if ($Path -like $expanded) { return $true }
    }
    return $false
}

function Save-Json {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 14 | Set-Content -Path $Path -Encoding UTF8
}

function Load-Json {
    param([string]$Path)
    if (Test-Path $Path) {
        try { return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-SpiderState { param($State) Save-Json $State $script:LatestPath }
function Load-SpiderState { return Load-Json $script:LatestPath }

function Add-SpiderEvent {
    param(
        [string]$Category,
        [string]$Severity,
        [string]$Symptoms,
        [string]$RootCause,
        [double]$Confidence,
        [string]$Action,
        [string]$Result,
        [int]$DurationSec = 0,
        [hashtable]$Extra = @{}
    )
    $events = @()
    $existing = Load-Json $script:EventsPath
    if ($existing) { $events = @($existing) }
    $id = "SP-{0:yyyyMMdd}-{1:D5}" -f (Get-Date), ($events.Count + 1)
    $entry = [pscustomobject]@{
        EventId     = $id
        Timestamp   = (Get-Date).ToString('o')
        Category    = $Category
        Severity    = $Severity
        Symptoms    = $Symptoms
        RootCause   = $RootCause
        Confidence  = $Confidence
        Action      = $Action
        Result      = $Result
        DurationSec = $DurationSec
        Extra       = $Extra
    }
    $events += $entry
    $cfg = Get-SpiderConfig
    $keep = if ($cfg) { $cfg.HistoryDays } else { 30 }
    $cutoff = (Get-Date).AddDays(-$keep)
    $events = $events | Where-Object {
        try { [datetime]$_.Timestamp -ge $cutoff } catch { $true }
    }
    Save-Json $events $script:EventsPath
    Write-SpiderLog "EVENT $id | $Category | $Severity | $RootCause | $Result" 'EVENT'
    return $entry
}

function Add-SpiderHistory {
    param($Entry)
    $history = @()
    $existing = Load-Json $script:HistoryPath
    if ($existing) { $history = @($existing) }
    $history += $Entry
    $cfg = Get-SpiderConfig
    $keep = if ($cfg) { $cfg.HistoryDays } else { 30 }
    $cutoff = (Get-Date).AddDays(-$keep)
    $history = $history | Where-Object {
        try { [datetime]$_.Timestamp -ge $cutoff } catch { $true }
    }
    Save-Json $history $script:HistoryPath
}

function Get-SpiderHistoryStats {
    param([string]$ProblemId)
    $history = Load-Json $script:HistoryPath
    if (-not $history) { return $null }
    $matches = @($history | Where-Object { $_.ProblemId -eq $ProblemId })
    if ($matches.Count -eq 0) { return $null }
    $success = @($matches | Where-Object { $_.Result -eq 'SUCCESS' }).Count
    $total = $matches.Count
    return [pscustomobject]@{
        Occurrences   = $total
        SuccessRate   = if ($total -gt 0) { [math]::Round(($success / $total) * 100, 1) } else { 0 }
        TypicalAction = ($matches | Group-Object Action | Sort-Object Count -Descending | Select-Object -First 1).Name
    }
}

function Test-CircuitBreaker {
    param([string]$ActionName)
    $cb = Load-Json $script:CircuitPath
    if (-not $cb) { return $true }
    $key = $ActionName
    if (-not $cb.$key) { return $true }
    $item = $cb.$key
    $cfg = Get-SpiderConfig
    $cooldown = $cfg.Failsafe.CircuitBreakerCooldownMin
    if ($item.Failures -ge $cfg.Failsafe.CircuitBreakerFailures) {
        $last = [datetime]$item.LastFail
        if ((Get-Date) -lt $last.AddMinutes($cooldown)) {
            Write-SpiderLog "CircuitBreaker OPEN for $ActionName (failures=$($item.Failures))" 'WARN'
            return $false
        }
    }
    return $true
}

function Record-CircuitFailure {
    param([string]$ActionName)
    $cb = Load-Json $script:CircuitPath
    if (-not $cb) { $cb = [pscustomobject]@{} }
    $ht = @{}
    if ($cb.PSObject.Properties) {
        foreach ($p in $cb.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    }
    $prev = if ($ht.ContainsKey($ActionName)) { $ht[$ActionName] } else { $null }
    $fails = if ($prev) { [int]$prev.Failures + 1 } else { 1 }
    $ht[$ActionName] = [pscustomobject]@{ Failures = $fails; LastFail = (Get-Date).ToString('o') }
    Save-Json ([pscustomobject]$ht) $script:CircuitPath
}

function Clear-CircuitFailure {
    param([string]$ActionName)
    $cb = Load-Json $script:CircuitPath
    if (-not $cb) { return }
    $ht = @{}
    foreach ($p in $cb.PSObject.Properties) {
        if ($p.Name -ne $ActionName) { $ht[$p.Name] = $p.Value }
    }
    Save-Json ([pscustomobject]$ht) $script:CircuitPath
}

function Play-AlertSound {
    param([string]$Type = 'Critical')
    try {
        if ($Type -eq 'Critical') {
            1..3 | ForEach-Object { [Console]::Beep(800, 300); Start-Sleep -Milliseconds 150 }
        } else {
            [Console]::Beep(600, 200)
        }
    } catch {}
}

function Get-PrimaryAdapter {
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true })
    if (-not $adapters) {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    }
    $pref = $adapters | Sort-Object {
        if ($_.Name -match '(?i)ethernet|local area') { 0 }
        elseif ($_.Name -match '(?i)wi-?fi|wireless') { 1 }
        else { 2 }
    }
    return $pref | Select-Object -First 1
}

function Invoke-ApprovalConsole {
    param(
        [string]$Title,
        [string]$RootCause,
        [double]$Confidence,
        [string]$Risk,
        [string]$Action,
        [string]$Details,
        [int]$TimeoutSec = 300
    )
    Write-SpiderLog "APPROVAL REQUIRED: $Title | Risk=$Risk" 'WARN'
    Write-Host ""
    Write-Host "+======================================================+" -ForegroundColor Yellow
    Write-Host "|           [SPIDER]  PI NODE SPIDER - ACTION APPROVAL        |" -ForegroundColor Yellow
    Write-Host "+======================================================+" -ForegroundColor Yellow
    Write-Host ("|  {0}" -f $Title.PadRight(50).Substring(0,50)) -ForegroundColor White
    Write-Host "|                                                      |" -ForegroundColor Yellow
    Write-Host ("|  Root Cause : {0}" -f $RootCause.PadRight(40).Substring(0,[Math]::Min(40,$RootCause.Length))) -ForegroundColor White
    Write-Host ("|  Confidence : {0}%" -f $Confidence) -ForegroundColor White
    Write-Host ("|  Risk       : {0}" -f $Risk) -ForegroundColor $(if($Risk -eq 'HIGH' -or $Risk -eq 'EXTREME'){'Red'}else{'Yellow'})
    Write-Host ("|  Action     : {0}" -f $Action) -ForegroundColor Cyan
    if ($Details) {
        Write-Host ("|  Details    : {0}" -f $Details.PadRight(40).Substring(0,[Math]::Min(40,$Details.Length))) -ForegroundColor Gray
    }
    Write-Host "|                                                      |" -ForegroundColor Yellow
    Write-Host "|  [Y] APPROVE    [N] DENY    (timeout = DENY)         |" -ForegroundColor Cyan
    Write-Host "+======================================================+" -ForegroundColor Yellow
    Write-Host ""
    $end = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $end) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
                Write-SpiderLog "User APPROVED: $Action" 'ACTION'
                return $true
            }
            if ($key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
                Write-SpiderLog "User DENIED: $Action" 'WARN'
                return $false
            }
        }
        Start-Sleep -Milliseconds 200
    }
    Write-SpiderLog "Approval timeout → DENY (safe default)" 'WARN'
    return $false
}


function Get-SpiderSeverity {
    $p = Join-Path $script:SpiderRoot "Rules\Severity.json"
    if (Test-Path $p) { return Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

function Get-SpiderModes {
    $p = Join-Path $script:SpiderRoot "Rules\Modes.json"
    if (Test-Path $p) { return Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

function Get-SpiderAnomaly {
    $p = Join-Path $script:SpiderRoot "Rules\Anomaly.json"
    if (Test-Path $p) { return Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

Write-SpiderLog "Engine Core loaded" 'DEBUG'
