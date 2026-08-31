# ============================================================
# Actions/NetworkRepair.ps1 - Stack refresh + optional static IP keep (Risk: MEDIUM)
# ============================================================
function Invoke-NetworkRepair {
    param($Snapshot)
    Write-SpiderLog "ACTION: NETWORK_REPAIR" 'ACTION'
    $isAdmin = Test-IsAdmin
    $adapter = Get-PrimaryAdapter
    if (-not $adapter) {
        return [pscustomobject]@{ Action='NETWORK_REPAIR'; Risk='MEDIUM'; Success=$false; Message='No adapter' }
    }
    $iface = $adapter.Name

    try {
        Restart-NetAdapter -Name $iface -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    } catch {}

    cmd /c "ipconfig /release" >$null 2>&1
    cmd /c "ipconfig /renew" >$null 2>&1
    cmd /c "ipconfig /flushdns" >$null 2>&1

    if ($isAdmin) {
        cmd /c "netsh winsock reset" >$null 2>&1
        cmd /c "netsh int ip reset" >$null 2>&1
    }

    Start-Sleep -Seconds 3
    $netAfter = Get-NetworkStatus
    $success = [bool]$netAfter.Internet

    # Keep current IP as static (from original Reset_Node_Network logic)
    if ($isAdmin -and $netAfter.IP) {
        $ipCfg = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        $prefix = if ($ipCfg) { [int]$ipCfg.PrefixLength } else { 24 }
        $gw = $netAfter.Gateway
        if (-not $gw -and $netAfter.IP) {
            $parts = $netAfter.IP.Split('.')
            if ($parts.Count -eq 4) { $gw = "$($parts[0]).$($parts[1]).$($parts[2]).1" }
        }
        try {
            $existing = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue
            foreach ($e in $existing) {
                try {
                    Remove-NetIPAddress -InterfaceAlias $iface -IPAddress $e.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
                } catch {}
            }
            try {
                Remove-NetRoute -InterfaceAlias $iface -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
            } catch {}
            New-NetIPAddress -InterfaceAlias $iface -IPAddress $netAfter.IP -PrefixLength $prefix -DefaultGateway $gw -ErrorAction SilentlyContinue | Out-Null
            Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses @('8.8.8.8','8.8.4.4') -ErrorAction SilentlyContinue
            Write-SpiderLog "Static IP kept: $($netAfter.IP) gw=$gw" 'ACTION'
        } catch {
            Write-SpiderLog "Static IP set partial fail - netsh fallback" 'WARN'
            $mask = switch ($prefix) {
                8  { '255.0.0.0' }
                16 { '255.255.0.0' }
                24 { '255.255.255.0' }
                default { '255.255.255.0' }
            }
            cmd /c "netsh interface ip set address name=`"$iface`" static $($netAfter.IP) $mask $gw 1" >$null 2>&1
            cmd /c "netsh interface ip set dns name=`"$iface`" static 8.8.8.8 validate=no" >$null 2>&1
            cmd /c "netsh interface ip add dns name=`"$iface`" 8.8.4.4 index=2 validate=no" >$null 2>&1
        }
    }

    # Ensure Pi ports firewall while repairing network
    if ($isAdmin) {
        Invoke-FirewallCheck | Out-Null
    }

    return [pscustomobject]@{
        Action   = 'NETWORK_REPAIR'
        Risk     = 'MEDIUM'
        Success  = $success
        IP       = $netAfter.IP
        Gateway  = $netAfter.Gateway
        Internet = $netAfter.Internet
        Adapter  = $iface
    }
}
