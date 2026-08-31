# ============================================================
# Doctors/Stellar.ps1 - Stellar Core Doctor
# Sync, ledger age, peers, incoming/outgoing
# ============================================================
function Invoke-StellarDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Stellar" 'DIAG'
    $cfg = Get-SpiderConfig
    $s = $Snapshot.Stellar
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{
        Available = [bool]$s.Available
        Synced = $s.Synced
        LedgerAgeSec = $s.LedgerAgeSec
        Peers = $s.Peers
        Incoming = $s.Incoming
        Outgoing = $s.Outgoing
        Method = $s.Method
        Container = $s.Container
    }

    if (-not $s.Available) { [void]$issues.Add('UNAVAILABLE') }
    if ($s.Synced -eq $false) { [void]$issues.Add('UNSYNCED') }

    $ageWarn = $cfg.Thresholds.LedgerAge_Warning_Sec
    $ageCrit = $cfg.Thresholds.LedgerAge_Critical_Sec
    $peerWarn = $cfg.Thresholds.Peers_Min_Warning
    $peerCrit = $cfg.Thresholds.Peers_Min_Critical

    if ($s.LedgerAgeSec -ge 0) {
        if ($s.LedgerAgeSec -gt $ageCrit) { [void]$issues.Add('LEDGER_STALL_CRITICAL') }
        elseif ($s.LedgerAgeSec -gt $ageWarn) { [void]$issues.Add('LEDGER_AGE_HIGH') }
    }
    if ($s.Peers -ge 0) {
        if ($s.Peers -lt $peerCrit) { [void]$issues.Add('PEERS_CRITICAL') }
        elseif ($s.Peers -lt $peerWarn) { [void]$issues.Add('PEERS_LOW') }
    }
    if ($s.Incoming -ge 0 -and $s.Incoming -eq 0 -and $s.Peers -ge 0 -and $s.Peers -lt $peerWarn) {
        [void]$issues.Add('NO_INCOMING_PEERS')
    }

    $status = 'OK'
    if ($issues -contains 'UNAVAILABLE' -or $issues -contains 'LEDGER_STALL_CRITICAL' -or $issues -contains 'PEERS_CRITICAL') {
        $status = 'CRITICAL'
    } elseif ($issues.Count -gt 0) {
        $status = 'WARNING'
    }

    # Minimal intervention: low peers + network OK → WAIT first
    $action = 'NONE'
    if ($issues -contains 'UNAVAILABLE' -and $Snapshot.Docker.EngineHealthy) {
        $action = 'RESTART_NODE'
    } elseif ($issues -contains 'LEDGER_STALL_CRITICAL') {
        if ($Snapshot.Network.Internet) { $action = 'RESTART_NODE' } else { $action = 'NETWORK_REPAIR' }
    } elseif ($issues -contains 'PEERS_LOW' -or $issues -contains 'LEDGER_AGE_HIGH') {
        $action = 'WAIT_MONITOR'
    }

    return [pscustomobject]@{
        Doctor = 'Stellar'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "Age=$($s.LedgerAgeSec)s Peers=$($s.Peers) Method=$($s.Method)"
    }
}
