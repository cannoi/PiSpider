# ============================================================
# Actions/DnsRefresh.ps1 - Flush DNS cache (Risk: LOW)
# ============================================================
function Invoke-DnsRefresh {
    Write-SpiderLog "ACTION: DNS_REFRESH" 'ACTION'
    try {
        cmd /c "ipconfig /flushdns" >$null 2>&1
        $ok = $true
    } catch { $ok = $false }
    return [pscustomobject]@{
        Action  = 'DNS_REFRESH'
        Risk    = 'LOW'
        Success = $ok
    }
}
