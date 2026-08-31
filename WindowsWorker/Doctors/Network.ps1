# ============================================================
# Doctors/Network.ps1 - Network Doctor
# NIC → IP → Gateway → DNS → Internet → Latency
# ============================================================
function Invoke-NetworkDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Network" 'DIAG'
    $cfg = Get-SpiderConfig
    $n = $Snapshot.Network
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{
        Adapter = $n.Adapter
        IP = $n.IP
        Gateway = $n.Gateway
        Internet = [bool]$n.Internet
        DNS = [bool]$n.DNS
        LatencyMs = $n.LatencyMs
    }

    if (-not $n.Adapter) { [void]$issues.Add('NO_ADAPTER') }
    if (-not $n.IP) { [void]$issues.Add('NO_IP') }
    if (-not $n.Gateway) { [void]$issues.Add('NO_GATEWAY') }
    if (-not $n.Internet) { [void]$issues.Add('NO_INTERNET') }
    if (-not $n.DNS) { [void]$issues.Add('DNS_FAIL') }
    $latWarn = if ($cfg.Thresholds.Latency_Warning_Ms) { $cfg.Thresholds.Latency_Warning_Ms } else { 200 }
    if ($n.LatencyMs -ge 0 -and $n.LatencyMs -gt $latWarn) { [void]$issues.Add('HIGH_LATENCY') }

    # Deeper optional checks (best-effort, non-blocking)
    $gwReachable = $null
    if ($n.Gateway) {
        try {
            $gwReachable = Test-Connection -ComputerName $n.Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
            $evidence.GatewayReachable = [bool]$gwReachable
            if ($n.Internet -eq $false -and $gwReachable -eq $false) {
                [void]$issues.Add('GATEWAY_UNREACHABLE')
            } elseif ($n.Internet -eq $false -and $gwReachable -eq $true) {
                [void]$issues.Add('ISP_OR_UPSTREAM')
            }
        } catch {
            $evidence.GatewayReachable = $null
        }
    }

    $status = 'OK'
    if ($issues -contains 'NO_INTERNET' -or $issues -contains 'NO_ADAPTER' -or $issues -contains 'GATEWAY_UNREACHABLE') {
        $status = 'CRITICAL'
    } elseif ($issues.Count -gt 0) {
        $status = 'WARNING'
    }

    $action = 'NONE'
    if ($status -eq 'CRITICAL' -or $issues -contains 'DNS_FAIL' -or $issues -contains 'NO_IP') {
        $action = 'NETWORK_REPAIR'
    }

    return [pscustomobject]@{
        Doctor = 'Network'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "IP=$($n.IP) GW=$($n.Gateway) Latency=$($n.LatencyMs)ms"
    }
}
