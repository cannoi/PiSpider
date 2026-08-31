# ============================================================
# Doctors/Firewall.ps1 - Firewall & Pi ports Doctor
# ============================================================
function Invoke-FirewallDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Firewall" 'DIAG'
    $cfg = Get-SpiderConfig
    $ports = $Snapshot.Ports
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{
        AnyOpen = [bool]$ports.AnyOpen
        OpenCount = [int]$ports.OpenCount
        Ports = $ports.Ports
    }

    if (-not $ports.AnyOpen) {
        [void]$issues.Add('PI_PORTS_CLOSED')
    } elseif ($ports.OpenCount -lt 2) {
        [void]$issues.Add('FEW_PORTS_OPEN')
    }

    # Check if Windows Firewall rules exist (best-effort, needs admin often)
    $ruleOk = $null
    try {
        $rules = Get-NetFirewallRule -DisplayName 'Pi_Node_*' -ErrorAction SilentlyContinue
        $ruleOk = ($null -ne $rules -and @($rules).Count -gt 0)
        $evidence.PiFirewallRules = $ruleOk
        if ($ruleOk -eq $false) { [void]$issues.Add('NO_PI_FIREWALL_RULE') }
    } catch {
        $evidence.PiFirewallRules = $null
    }

    $status = 'OK'
    if ($issues -contains 'PI_PORTS_CLOSED') { $status = 'WARNING' }
    if ($Snapshot.NodeHealthy -and $issues -contains 'PI_PORTS_CLOSED') { $status = 'WARNING' }

    $action = if ($issues.Count -gt 0) { 'FIREWALL_CHECK' } else { 'NONE' }

    return [pscustomobject]@{
        Doctor = 'Firewall'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "Open ports: $($ports.OpenCount)"
    }
}
