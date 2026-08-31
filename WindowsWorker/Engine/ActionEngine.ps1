# ============================================================
# Engine/ActionEngine.ps1 - Action Catalog + Failsafe dispatcher
# Implementation lives in Actions/*.ps1 (loaded here)
# ============================================================

# Lazy action loading: action scripts are NOT dot-sourced at engine startup.
# This keeps Scan/Status/Patrol workers light; only the selected action module is loaded.
$script:LoadedSpiderActionFiles = @{}

function Import-SpiderAction {
    param([Parameter(Mandatory)][string]$ActionName)
    $map = @{
        CLEAN_RAM='CleanRAM.ps1'; CLEAN_TEMP='CleanTemp.ps1'; DNS_REFRESH='DnsRefresh.ps1';
        NETWORK_REPAIR='NetworkRepair.ps1'; FIREWALL_CHECK='FirewallCheck.ps1';
        RESTART_DOCKER='DockerRecovery.ps1'; RESTART_WSL='DockerRecovery.ps1';
        SOFT_DOCKER_RESTART='DockerRecovery.ps1'; ORDERED_WSL_RECYCLE='DockerRecovery.ps1';
        RESTART_NODE='NodeRecovery.ps1'; HOST_REBOOT='HostReboot.ps1';
        MAINTENANCE_LIGHT='Maintenance.ps1'; MONITOR='MonitorActions.ps1';
        WAIT_MONITOR='MonitorActions.ps1'; REPORT_CONFIG='MonitorActions.ps1'; NONE='MonitorActions.ps1'
    }
    $file = $map[$ActionName]
    if (-not $file) { return $false }
    if ($script:LoadedSpiderActionFiles.ContainsKey($file)) { return $true }
    $actionsDir = Join-Path $script:SpiderRoot 'Actions'
    if (-not (Test-Path $actionsDir)) { $actionsDir = Join-Path (Split-Path -Parent $PSCommandPath) '..\Actions' }
    $path = Join-Path $actionsDir $file
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        . $path
        $script:LoadedSpiderActionFiles[$file] = $true
        Write-SpiderLog "Loaded action module on demand: $file" 'DEBUG'
        return $true
    } catch {
        Write-SpiderLog "Failed loading action module $file`: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Get-ActionCatalog {
    return [pscustomobject]@{
        CLEAN_RAM         = @{ Fn = 'Invoke-CleanRAM';         Risk = 'LOW';    NeedsSnapshot = $true }
        CLEAN_TEMP        = @{ Fn = 'Invoke-CleanTemp';        Risk = 'LOW';    NeedsSnapshot = $false }
        DNS_REFRESH       = @{ Fn = 'Invoke-DnsRefresh';       Risk = 'LOW';    NeedsSnapshot = $false }
        NETWORK_REPAIR    = @{ Fn = 'Invoke-NetworkRepair';    Risk = 'MEDIUM'; NeedsSnapshot = $true }
        FIREWALL_CHECK    = @{ Fn = 'Invoke-FirewallCheck';    Risk = 'LOW';    NeedsSnapshot = $false }
        RESTART_DOCKER    = @{ Fn = 'Invoke-RestartDocker';    Risk = 'HIGH';   NeedsSnapshot = $false }
        RESTART_WSL       = @{ Fn = 'Invoke-RestartWSL';       Risk = 'HIGH';   NeedsSnapshot = $false }
        RESTART_NODE      = @{ Fn = 'Invoke-RestartNode';      Risk = 'HIGH';   NeedsSnapshot = $false }
        SOFT_DOCKER_RESTART = @{ Fn = 'Invoke-SoftDockerRestart'; Risk = 'HIGH'; NeedsSnapshot = $false }
        ORDERED_WSL_RECYCLE = @{ Fn = 'Invoke-OrderedWslRecycle'; Risk = 'HIGH'; NeedsSnapshot = $false }
        HOST_REBOOT       = @{ Fn = 'Invoke-HostReboot';       Risk = 'EXTREME'; NeedsSnapshot = $false }
        MAINTENANCE_LIGHT = @{ Fn = 'Invoke-MaintenanceLight'; Risk = 'LOW';    NeedsSnapshot = $false }
        WAIT_MONITOR      = @{ Fn = 'Invoke-WaitMonitor';      Risk = 'NONE';   NeedsSnapshot = $false }
        MONITOR           = @{ Fn = 'Invoke-MonitorOnly';      Risk = 'NONE';   NeedsSnapshot = $false }
        REPORT_CONFIG     = @{ Fn = 'Invoke-ReportConfig';     Risk = 'NONE';   NeedsSnapshot = $false }
        NONE              = @{ Fn = 'Invoke-NoneAction';       Risk = 'NONE';   NeedsSnapshot = $false }
    }
}

function Invoke-SpiderAction {
    param(
        [string]$ActionName,
        $Snapshot,
        [string]$Risk = 'MEDIUM',
        [string]$Mode = 'ASSIST',
        [switch]$Force,
        [switch]$UserApproved,
        [switch]$SkipSafety
    )

    if (-not (Test-CircuitBreaker $ActionName)) {
        return [pscustomobject]@{
            Action  = $ActionName
            Success = $false
            Message = 'CircuitBreaker OPEN'
        }
    }

    $catalog = Get-ActionCatalog
    $entry = $null
    if ($catalog.PSObject.Properties.Name -contains $ActionName) {
        $entry = $catalog.$ActionName
        if ($Risk -eq 'MEDIUM' -and $entry.Risk) { $Risk = [string]$entry.Risk }
        # Load only the action implementation actually requested.
        [void](Import-SpiderAction -ActionName $ActionName)
    }

    if (-not $SkipSafety -and (Get-Command Invoke-SafetyGate -ErrorAction SilentlyContinue)) {
        $cfg = Get-SpiderConfig
        $m = if ($Mode) { $Mode } elseif ($cfg) { $cfg.Mode } else { 'ASSIST' }
        $gate = Invoke-SafetyGate -ActionName $ActionName -Risk $Risk -Mode $m -Force:$Force -UserApproved:$UserApproved
        if (-not $gate.Allowed) {
            $hardBlock = $false
            foreach ($r in $gate.Reasons) {
                if ($r -match 'CircuitBreaker|OBSERVE|EXTREME|firmware|BIOS|NeverAuto') { $hardBlock = $true }
            }
            if ($hardBlock -or $Risk -in @('HIGH','EXTREME')) {
                return [pscustomobject]@{
                    Action  = $ActionName
                    Success = $false
                    Message = 'Blocked by Safety'
                    Safety  = $gate
                }
            }
        }
    }

    $start = Get-Date
    $result = $null
    try {
        if ($entry) {
            $fn = $entry.Fn
            if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
                return [pscustomobject]@{ Action=$ActionName; Success=$false; Message="Handler $fn not loaded" }
            }
            if ($entry.NeedsSnapshot) {
                $result = & $fn -Snapshot $Snapshot
            } else {
                $result = & $fn
            }
        } else {
            Write-SpiderLog "Unknown action: $ActionName" 'WARN'
            $result = [pscustomobject]@{ Action=$ActionName; Success=$false; Message='Unknown action' }
        }
    } catch {
        Write-SpiderLog "Action $ActionName exception: $($_.Exception.Message)" 'ERROR'
        $result = [pscustomobject]@{ Action=$ActionName; Success=$false; Message=$_.Exception.Message }
    }

    $duration = [int]((Get-Date) - $start).TotalSeconds
    if ($result -and -not $result.Success) {
        Record-CircuitFailure $ActionName
    } elseif ($result -and $result.Success) {
        Clear-CircuitFailure $ActionName
    }
    if ($result) {
        $result | Add-Member -NotePropertyName DurationSec -NotePropertyValue $duration -Force
    }
    return $result
}

Write-SpiderLog "ActionEngine dispatcher ready" 'DEBUG'
