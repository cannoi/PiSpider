# ============================================================
# Engine/Diagnostic.ps1 - Root Cause + Health Score + 6 levels
# ============================================================

function Get-HealthScore {
    param($Snapshot)
    $cfg = Get-SpiderConfig
    $scores = @{}
    $scores.Docker = if ($Snapshot.Docker.EngineHealthy -eq $true) { 100 } elseif ($Snapshot.Docker.EngineHealthy -eq $false) { 0 } else { 50 }
    $scores.WSL = if ($Snapshot.WSL.Available) { 95 } else { 40 }
    if ($Snapshot.WSL.HighMem) { $scores.WSL = [math]::Max(60, $scores.WSL - 15) }
    if ($Snapshot.NodeHealthy) {
        $scores.PiNode = 95
        $scores.Stellar = if ($Snapshot.StellarSynced -eq $true) { 95 } elseif ($Snapshot.StellarSynced -eq $false) { 40 } else { 70 }
    } else {
        $scores.PiNode = 20; $scores.Stellar = 20
    }
    $scores.Network = 100
    if (-not $Snapshot.Network.Internet) { $scores.Network = 10 }
    elseif (-not $Snapshot.Network.DNS) { $scores.Network = 40 }
    elseif ($Snapshot.Network.LatencyMs -gt $cfg.Thresholds.Latency_Warning_Ms) { $scores.Network = 70 }
    $ram = $Snapshot.Memory.UsedPct
    if ($ram -ge $cfg.Thresholds.RAM_Critical) { $scores.RAM = 25 }
    elseif ($ram -ge $cfg.Thresholds.RAM_Warning) { $scores.RAM = 55 }
    else { $scores.RAM = 95 }
    $free = $Snapshot.Disk.FreeGB
    if ($free -lt $cfg.Thresholds.Disk_Free_GB_Critical) { $scores.Disk = 15 }
    elseif ($free -lt $cfg.Thresholds.Disk_Free_GB_Warning) { $scores.Disk = 50 }
    else { $scores.Disk = 95 }
    $scores.Ports = if ($Snapshot.Ports.AnyOpen) { 90 } else { 40 }
    $overall = [math]::Round((
        $scores.Docker * 0.20 + $scores.PiNode * 0.20 + $scores.Stellar * 0.15 +
        $scores.Network * 0.15 + $scores.RAM * 0.12 + $scores.Disk * 0.10 +
        $scores.WSL * 0.05 + $scores.Ports * 0.03
    ), 0)
    $level = if ($overall -ge 90) { 'HEALTHY' }
             elseif ($overall -ge 75) { 'INFO' }
             elseif ($overall -ge 60) { 'WARNING' }
             elseif ($overall -ge 40) { 'DEGRADED' }
             elseif ($overall -ge 20) { 'CRITICAL' }
             else { 'EMERGENCY' }
    return [pscustomobject]@{ Overall=$overall; Scores=$scores; Level=$level }
}

function Find-TopUserMemoryCulprit {
    param($Snapshot)
    $userApps = $Snapshot.TopProcesses | Where-Object { -not $_.Protected -and (Test-CleanupCandidate $_.Name) }
    if ($userApps) { return $userApps | Select-Object -First 1 }
    return $null
}

function Invoke-RootCauseAnalysis {
    param($Snapshot)
    $cfg = Get-SpiderConfig
    $findings = @()
    $ram = $Snapshot.Memory.UsedPct
    $nodeOK = $Snapshot.NodeHealthy
    $dockerOK = ($Snapshot.Docker.EngineHealthy -eq $true)
    $wslHigh = $Snapshot.WSL.HighMem
    $internet = $Snapshot.Network.Internet
    $diskFree = $Snapshot.Disk.FreeGB
    $portsOpen = $Snapshot.Ports.AnyOpen
    $stellarSynced = $Snapshot.StellarSynced
    $peers = $Snapshot.Stellar.Peers
    $ledgerAge = $Snapshot.Stellar.LedgerAgeSec
    $topUser = Find-TopUserMemoryCulprit $Snapshot
    $baseCmp = Compare-Baseline $Snapshot


    # Five-layer driven findings (executable actions only)
    $fl = $null
    try {
        if ($Snapshot.Stellar -and $Snapshot.Stellar.FiveLayer) { $fl = $Snapshot.Stellar.FiveLayer }
        elseif ($Snapshot.FiveLayer) { $fl = $Snapshot.FiveLayer }
    } catch {}
    if ($fl -and $fl.Layer1) {
        if ($fl.Layer1.Running -eq $false) {
            $findings += [pscustomobject]@{
                Id='CONTAINER_NOT_RUNNING'; Severity='CRITICAL'
                RootCause='Pi Node container is not running'
                Confidence=98; Action='RESTART_NODE'; Risk='HIGH'; ImpactOnNode='HIGH'
                Details="Container=$($fl.Container) Status=$($fl.Layer1.Status) Exit=$($fl.Layer1.ExitCode)"
            }
        } elseif ($fl.Layer1.OOMKilled) {
            $findings += [pscustomobject]@{
                Id='CONTAINER_OOM'; Severity='CRITICAL'
                RootCause='Container was OOM-killed'
                Confidence=95; Action='RESTART_NODE'; Risk='HIGH'; ImpactOnNode='HIGH'
                Details='Increase memory limit or free RAM then restart container'
            }
        } elseif ($fl.Layer1.Paused) {
            $findings += [pscustomobject]@{
                Id='CONTAINER_PAUSED'; Severity='WARNING'
                RootCause='Container is paused'
                Confidence=95; Action='RESTART_NODE'; Risk='MEDIUM'; ImpactOnNode='HIGH'
                Details='Unpause/restart Pi container'
            }
        }
    }
    if ($fl -and $fl.Layer4 -and $fl.Layer4.Ok -and $null -ne $fl.Layer4.CpuPercent) {
        if ([double]$fl.Layer4.CpuPercent -ge 90) {
            $findings += [pscustomobject]@{
                Id='NODE_CPU_HIGH'; Severity='WARNING'
                RootCause='Container CPU very high'
                Confidence=75; Action='WAIT_MONITOR'; Risk='LOW'; ImpactOnNode='LOW'
                Details="CPU=$($fl.Layer4.CpuPercent)% (normal during catch-up; escalate if sustained)"
            }
        }
    }

    if ($nodeOK -and $dockerOK -and $stellarSynced -and $ram -lt $cfg.Thresholds.RAM_Warning -and $internet -and $diskFree -ge $cfg.Thresholds.Disk_Free_GB_Warning) {
        $findings += [pscustomobject]@{
            Id='NODE_HEALTHY'; Severity='HEALTHY'; RootCause='System healthy'; Confidence=99
            Action='NONE'; Risk='NONE'; ImpactOnNode='NONE'; Details='All critical components normal'
        }
    }
    if ($ram -ge $cfg.Thresholds.RAM_Warning -and $topUser -and $nodeOK) {
        $sev = if ($ram -ge $cfg.Thresholds.RAM_Critical) { 'CRITICAL' } else { 'WARNING' }
        $conf = if ($ram -ge $cfg.Thresholds.RAM_Critical) { 95 } else { 90 }
        $hist = Get-SpiderHistoryStats 'RAM_USER_PRESSURE'
        if ($hist -and $hist.SuccessRate -gt 80) { $conf = [math]::Min(99, $conf + 5) }
        $findings += [pscustomobject]@{
            Id='RAM_USER_PRESSURE'; Severity=$sev; RootCause="User application memory pressure ($($topUser.Name) $($topUser.MB)MB)"
            Confidence=$conf; Action='CLEAN_RAM'; Risk='LOW'; ImpactOnNode='LOW'
            Details="Top culprit: $($topUser.Name) PID=$($topUser.PID) RAM=$($topUser.MB)MB"; Culprit=$topUser
        }
    }
    if ($ram -ge $cfg.Thresholds.RAM_Warning -and $wslHigh -and $nodeOK -and -not $topUser) {
        $findings += [pscustomobject]@{
            Id='RAM_WSL_DOCKER'; Severity='WARNING'; RootCause='WSL/Docker memory usage (expected for Pi Node)'
            Confidence=85; Action='MONITOR'; Risk='NONE'; ImpactOnNode='NONE'
            Details="vmmemWSL ~$($Snapshot.WSL.VmmemMB)MB. Node still healthy. Do NOT reset."
        }
    }
    if ($Snapshot.Docker.EngineHealthy -eq $false) {
        $findings += [pscustomobject]@{
            Id='DOCKER_ENGINE_DOWN'; Severity='CRITICAL'; RootCause='Docker Engine unavailable'
            Confidence=98; Action='RESTART_DOCKER'; Risk='HIGH'; ImpactOnNode='HIGH'
            Details='Pi containers unreachable. WSL may still be running.'
        }
    }
    # Only CRITICAL if engine OK, Pi not running, AND no port/listen/MonitorLive positive signals
    $portsSuggestUp = $false
    try {
        if ($Snapshot.Ports -and $Snapshot.Ports.AnyOpen) { $portsSuggestUp = $true }
        if ($Snapshot.Docker -and $Snapshot.Docker.Runtime -and $Snapshot.Docker.Runtime.PortsListening) { $portsSuggestUp = $true }
        if ($Snapshot.MonitorLive -and $Snapshot.MonitorLive.ContainerRunning -and -not $Snapshot.MonitorLive.Stale) { $portsSuggestUp = $true }
    } catch {}
    if ($dockerOK -and -not $Snapshot.Docker.PiRunning -and -not $portsSuggestUp -and -not $Snapshot.NodeHealthy) {
        $findings += [pscustomobject]@{
            Id='PI_CONTAINER_DOWN'; Severity='CRITICAL'; RootCause='Pi Node container not running'
            Confidence=90; Action='RESTART_NODE'; Risk='HIGH'; ImpactOnNode='HIGH'
            Details='Docker engine OK but no Pi/Stellar container Up (no port/MonitorLive evidence)'
        }
    }
    if (-not $internet) {
        $findings += [pscustomobject]@{
            Id='NETWORK_DOWN'; Severity='CRITICAL'; RootCause='No internet connectivity'
            Confidence=95; Action='NETWORK_REPAIR'; Risk='MEDIUM'; ImpactOnNode='HIGH'
            Details="Adapter=$($Snapshot.Network.Adapter) IP=$($Snapshot.Network.IP)"
        }
    }
    if ($diskFree -lt $cfg.Thresholds.Disk_Free_GB_Critical) {
        $findings += [pscustomobject]@{
            Id='DISK_CRITICAL'; Severity='CRITICAL'; RootCause='Critical low disk space'
            Confidence=98; Action='CLEAN_TEMP'; Risk='MEDIUM'; ImpactOnNode='HIGH'; Details="Free: ${diskFree}GB"
        }
    } elseif ($diskFree -lt $cfg.Thresholds.Disk_Free_GB_Warning) {
        $findings += [pscustomobject]@{
            Id='DISK_LOW'; Severity='WARNING'; RootCause='Low disk space'
            Confidence=90; Action='CLEAN_TEMP'; Risk='LOW'; ImpactOnNode='LOW'; Details="Free: ${diskFree}GB"
        }
    }
    if (-not $portsOpen -and $nodeOK) {
        $findings += [pscustomobject]@{
            Id='PORTS_CLOSED'; Severity='WARNING'; RootCause='Pi Node ports not listening locally'
            Confidence=75; Action='FIREWALL_CHECK'; Risk='LOW'; ImpactOnNode='MEDIUM'
            Details="Open ports count: $($Snapshot.Ports.OpenCount)"
        }
    }
    # Explicit not-synced / catching up (MonitorLive or stellar-core info)
    if ($stellarSynced -eq $false) {
        $sev = 'WARNING'
        $action = 'WAIT_MONITOR'
        if ($ledgerAge -gt $cfg.Thresholds.LedgerAge_Critical_Sec) {
            $sev = 'CRITICAL'; $action = 'RESTART_NODE'
        } elseif ($ledgerAge -gt 300) {
            $sev = 'WARNING'; $action = 'RESTART_NODE'
        }
        $findings += [pscustomobject]@{
            Id='STELLAR_CATCHING_UP'; Severity=$sev
            RootCause='Pi Node ledger not synced (Catching up / Chua dong bo)'
            Confidence=92; Action=$action
            Risk=$(if($sev -eq 'CRITICAL'){'HIGH'}else{'MEDIUM'}); ImpactOnNode='HIGH'
            Details="Synced=false LedgerAge=${ledgerAge}s Peers=$peers Method=$($Snapshot.Stellar.Method)"
        }
    } elseif ($null -eq $stellarSynced -and $dockerOK -and $nodeOK) {
        $findings += [pscustomobject]@{
            Id='STELLAR_SYNC_UNKNOWN'; Severity='INFO'
            RootCause='Container up but sync state unknown (no MonitorLive / stellar info)'
            Confidence=60; Action='MONITOR'; Risk='NONE'; ImpactOnNode='UNKNOWN'
            Details="Install/start PiNodeMonitorLive or set env PINODE_MONITOR_LIVE to latest.json"
        }
    }

    if ($dockerOK -and $nodeOK -and $Snapshot.Stellar -and ($null -eq $stellarSynced) -and [string]$Snapshot.Stellar.Method -match 'docker-ps-only|none|five-layer') {
        $findings += [pscustomobject]@{
            Id='STELLAR_INFO_UNAVAILABLE'; Severity='WARNING'
            RootCause='Cannot read stellar-core info (exec/http failed) — sync unknown'
            Confidence=80; Action='WAIT_MONITOR'; Risk='LOW'; ImpactOnNode='MEDIUM'
            Details="Method=$($Snapshot.Stellar.Method) Container=$($Snapshot.Docker.RunningContainer). Retry next scan."
        }
    }

    if ($Snapshot.Stellar.Available -and $ledgerAge -gt $cfg.Thresholds.LedgerAge_Warning_Sec) {
        $sev = if ($ledgerAge -gt $cfg.Thresholds.LedgerAge_Critical_Sec) { 'CRITICAL' } else { 'WARNING' }
        $action = if ($sev -eq 'CRITICAL') { 'RESTART_NODE' } else { 'WAIT_MONITOR' }
        # Avoid duplicate if CATCHING_UP already added
        $hasCatch = $false
        foreach ($f in $findings) { if ($f.Id -eq 'STELLAR_CATCHING_UP') { $hasCatch = $true } }
        if (-not $hasCatch) {
            $findings += [pscustomobject]@{
                Id='STELLAR_STALL'; Severity=$sev; RootCause='Ledger age high (possible stall)'
                Confidence=75; Action=$action; Risk=$(if($sev -eq 'CRITICAL'){'HIGH'}else{'MEDIUM'}); ImpactOnNode='MEDIUM'
                Details="LedgerAge=${ledgerAge}s Peers=$peers"
            }
        }
    }
    if ($baseCmp -and $baseCmp.HasDiff) {
        $findings += [pscustomobject]@{
            Id='CONFIG_CHANGED'; Severity='INFO'; RootCause='Configuration changed since baseline'
            Confidence=90; Action='REPORT_CONFIG'; Risk='NONE'; ImpactOnNode='UNKNOWN'
            Details=($baseCmp.Diffs -join '; ')
        }
    }

    $order = @{ 'EMERGENCY'=0; 'CRITICAL'=1; 'DEGRADED'=2; 'WARNING'=3; 'INFO'=4; 'HEALTHY'=5 }
    $findings = $findings | Sort-Object { $order[$_.Severity] }, Confidence -Descending
    return $findings
}
