# ============================================================
# Engine/Dependency.ps1
# Spider Web - dependency graph & impact analysis
# Internet → Network → Firewall → WSL → Docker → PiContainer → Stellar → Sync
# ============================================================

$script:SpiderDependencyOrder = @(
    'Internet',
    'WindowsNetwork',
    'Firewall',
    'WSL',
    'Docker',
    'PiContainer',
    'Stellar',
    'Sync'
)

function Get-DependencyGraph {
    return [pscustomobject]@{
        Order = $script:SpiderDependencyOrder
        Edges = @(
            [pscustomobject]@{ From='Internet';       To='WindowsNetwork' },
            [pscustomobject]@{ From='WindowsNetwork'; To='Firewall' },
            [pscustomobject]@{ From='WindowsNetwork'; To='WSL' },
            [pscustomobject]@{ From='WSL';            To='Docker' },
            [pscustomobject]@{ From='Docker';         To='PiContainer' },
            [pscustomobject]@{ From='PiContainer';    To='Stellar' },
            [pscustomobject]@{ From='Stellar';        To='Sync' },
            [pscustomobject]@{ From='Firewall';       To='PiContainer' }
        )
        Principle = 'Never reset a lower node while an upper dependency is broken'
    }
}

function Get-LayerHealthFromSnapshot {
    param($Snapshot)
    if (-not $Snapshot) { return @{} }
    $map = [ordered]@{}
    $map['Internet'] = [bool]$Snapshot.Network.Internet
    $map['WindowsNetwork'] = [bool]($Snapshot.Network.Adapter -and $Snapshot.Network.IP)
    $map['Firewall'] = [bool]$Snapshot.Ports.AnyOpen -or ($Snapshot.Ports.OpenCount -gt 0)
    $map['WSL'] = [bool]$Snapshot.WSL.Available
    $map['Docker'] = ($Snapshot.Docker.EngineHealthy -eq $true)
    $map['PiContainer'] = [bool]$Snapshot.Docker.PiRunning
    $map['Stellar'] = ($Snapshot.Stellar.Available -eq $true)
    $map['Sync'] = ($Snapshot.StellarSynced -eq $true) -or ($Snapshot.Stellar.Synced -eq $true)
    return $map
}

function Find-RootBrokenLayer {
    param($Snapshot)
    $health = Get-LayerHealthFromSnapshot $Snapshot
    foreach ($layer in $script:SpiderDependencyOrder) {
        if ($health.Contains($layer) -and -not $health[$layer]) {
            return $layer
        }
    }
    return $null
}

function Get-AffectedLayers {
    param([string]$BrokenLayer)
    if (-not $BrokenLayer) { return @() }
    $idx = [array]::IndexOf($script:SpiderDependencyOrder, $BrokenLayer)
    if ($idx -lt 0) { return @($BrokenLayer) }
    return @($script:SpiderDependencyOrder[$idx..($script:SpiderDependencyOrder.Count - 1)])
}

function Resolve-ActionByDependency {
    param(
        [string]$ProposedAction,
        $Snapshot
    )
    $root = Find-RootBrokenLayer $Snapshot
    if (-not $root) {
        return [pscustomobject]@{
            RootLayer = $null
            ProposedAction = $ProposedAction
            RecommendedAction = $ProposedAction
            Redirected = $false
            Reason = 'All dependency layers healthy (or unknown)'
            Affected = @()
        }
    }

    $affected = Get-AffectedLayers $root
    $recommended = $ProposedAction
    $redirected = $false
    $reason = "Root broken layer: $root"

    # Map layer → preferred repair action (minimal intervention)
    $layerAction = @{
        'Internet'        = 'NETWORK_REPAIR'
        'WindowsNetwork'  = 'NETWORK_REPAIR'
        'Firewall'        = 'FIREWALL_CHECK'
        'WSL'             = 'RESTART_DOCKER'   # WSL shutdown included in docker recovery path
        'Docker'          = 'RESTART_DOCKER'
        'PiContainer'     = 'RESTART_NODE'
        'Stellar'         = 'RESTART_NODE'
        'Sync'            = 'WAIT_MONITOR'
    }

    $preferred = $layerAction[$root]
    if ($preferred -and $ProposedAction -ne $preferred) {
        # Only redirect if proposed action targets a LOWER layer than the root break
        $proposedLayer = switch -Regex ($ProposedAction) {
            'NETWORK'  { 'Internet' }
            'FIREWALL' { 'Firewall' }
            'DOCKER'   { 'Docker' }
            'NODE'     { 'PiContainer' }
            'CLEAN_RAM|CLEAN_TEMP|MAINTENANCE' { $null }
            default { $null }
        }
        if ($proposedLayer) {
            $pIdx = [array]::IndexOf($script:SpiderDependencyOrder, $proposedLayer)
            $rIdx = [array]::IndexOf($script:SpiderDependencyOrder, $root)
            if ($pIdx -gt $rIdx) {
                $recommended = $preferred
                $redirected = $true
                $reason = "Redirect: fix $root first (was $ProposedAction)"
            }
        } elseif ($ProposedAction -in @('RESTART_NODE','RESTART_DOCKER') -and $root -in @('Internet','WindowsNetwork')) {
            $recommended = 'NETWORK_REPAIR'
            $redirected = $true
            $reason = "Redirect: Internet/Network down - do not restart Node/Docker first"
        }
    }

    return [pscustomobject]@{
        RootLayer = $root
        ProposedAction = $ProposedAction
        RecommendedAction = $recommended
        Redirected = $redirected
        Reason = $reason
        Affected = $affected
        LayerHealth = (Get-LayerHealthFromSnapshot $Snapshot)
    }
}

function Format-DependencyWeb {
    param($Snapshot)
    $health = Get-LayerHealthFromSnapshot $Snapshot
    $lines = @('[SPIDER] SPIDER WEB (dependency)')
    foreach ($layer in $script:SpiderDependencyOrder) {
        $ok = $health[$layer]
        $icon = if ($ok) { '[OK]' } else { '[CRIT]' }
        $lines += ("  {0} {1}" -f $icon, $layer)
    }
    return ($lines -join "`n")
}

Write-SpiderLog "Engine Dependency loaded" 'DEBUG'
