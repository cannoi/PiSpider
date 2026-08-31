# ============================================================
# Actions/FirewallCheck.ps1 - Pi Node ports 31401-31410 (Risk: LOW)
# ============================================================
function Invoke-FirewallCheck {
    Write-SpiderLog "ACTION: FIREWALL_CHECK" 'ACTION'
    if (-not (Test-IsAdmin)) {
        return [pscustomobject]@{
            Action  = 'FIREWALL_CHECK'
            Risk    = 'LOW'
            Success = $false
            Message = 'Need Administrator'
        }
    }
    $portRange = '31401-31410'
    cmd /c "netsh advfirewall firewall delete rule name=`"Pi_Node_Inbound_Ports`"" >$null 2>&1
    cmd /c "netsh advfirewall firewall delete rule name=`"Pi_Node_Outbound_Ports`"" >$null 2>&1
    cmd /c "netsh advfirewall firewall add rule name=`"Pi_Node_Inbound_Ports`" dir=in action=allow protocol=TCP localport=$portRange profile=any" >$null 2>&1
    cmd /c "netsh advfirewall firewall add rule name=`"Pi_Node_Outbound_Ports`" dir=out action=allow protocol=TCP localport=$portRange profile=any" >$null 2>&1

    # Verify local listen (informational)
    $open = 0
    foreach ($pt in 31401, 31402, 31403) {
        try {
            if ((Test-NetConnection 127.0.0.1 -Port $pt -WarningAction SilentlyContinue -ErrorAction SilentlyContinue).TcpTestSucceeded) {
                $open++
            }
        } catch {}
    }

    return [pscustomobject]@{
        Action       = 'FIREWALL_CHECK'
        Risk         = 'LOW'
        Success      = $true
        PortRange    = $portRange
        LocalOpenSample = $open
    }
}
