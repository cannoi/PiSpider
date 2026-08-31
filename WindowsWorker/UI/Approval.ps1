# ============================================================
# UI/Approval.ps1 - Approval Console (local interactive)
# Dùng khi Mode=ASSIST hoặc action Risk cần user confirm
# Không block khi -FromController / -Quiet / non-interactive
# ============================================================

function Test-SpiderInteractive {
    try {
        if ($env:PINODE_CONTROLLER -eq '1') { return $false }
        if (-not [Environment]::UserInteractive) { return $false }
        $raw = [Console]::IsInputRedirected
        if ($raw) { return $false }
        return $true
    } catch { return $false }
}

function Show-SpiderApproval {
    param(
        [string]$ActionName,
        [string]$Risk = 'MEDIUM',
        [string]$Reason = '',
        [string]$Mode = 'ASSIST',
        [int]$TimeoutSec = 60,
        [switch]$ForcePrompt
    )

    $result = [pscustomobject]@{
        Approved = $false
        TimedOut = $false
        Skipped  = $false
        Choice   = 'NONE'
        Action   = $ActionName
        Risk     = $Risk
    }

    if (-not $ForcePrompt -and -not (Test-SpiderInteractive)) {
        $result.Skipped = $true
        $result.Choice = 'NON_INTERACTIVE'
        Write-SpiderLog "Approval skipped (non-interactive): $ActionName" 'INFO'
        try {
            if (Get-Command Send-SpiderApprovalNotify -ErrorAction SilentlyContinue) {
                Send-SpiderApprovalNotify -Summary ("Action=$ActionName Risk=$Risk`n$Reason")
            }
        } catch {}
        return $result
    }
    try {
        if (Get-Command Send-SpiderApprovalNotify -ErrorAction SilentlyContinue) {
            Send-SpiderApprovalNotify -Summary ("Action=$ActionName Risk=$Risk`n$Reason`nMo Dashboard de xac nhan.")
        }
    } catch {}

    $icon = switch ($Risk) {
        'LOW' {'[OK]'} 'MEDIUM' {'[WARN]'} 'HIGH' {'[CRIT]'} 'EXTREME' {'[EMER]'} default {'[.]'}
    }

    Write-Host ""
    Write-Host "+==================================================+" -ForegroundColor Cyan
    Write-Host "|         [SPIDER]  SPIDER APPROVAL CONSOLE              |" -ForegroundColor Cyan
    Write-Host "+==================================================+" -ForegroundColor Cyan
    Write-Host "  Action : $ActionName"
    Write-Host "  Risk   : $icon $Risk"
    Write-Host "  Mode   : $Mode"
    if ($Reason) { Write-Host "  Reason : $Reason" }
    Write-Host ""
    Write-Host "  [Y] Approve   [N] Deny   [S] Skip (monitor only)"
    Write-Host "  Timeout ${TimeoutSec}s → Deny"
    Write-Host ""

    $choice = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    try {
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $c = $key.KeyChar.ToString().ToUpperInvariant()
                if ($c -in @('Y','N','S')) { $choice = $c; break }
            } else {
                Start-Sleep -Milliseconds 200
            }
        }
    } catch {
        # Fallback Read-Host when Console API limited
        try {
            $raw = Read-Host "Approve $ActionName? (Y/N/S)"
            if ($raw) { $choice = $raw.Substring(0,1).ToUpperInvariant() }
        } catch {}
    }

    if (-not $choice) {
        $result.TimedOut = $true
        $result.Choice = 'TIMEOUT'
        $result.Approved = $false
        Write-Host "  → TIMEOUT - denied" -ForegroundColor Yellow
        Write-SpiderLog "Approval TIMEOUT for $ActionName" 'WARN'
        return $result
    }

    switch ($choice) {
        'Y' {
            $result.Approved = $true
            $result.Choice = 'APPROVE'
            Write-Host "  → APPROVED" -ForegroundColor Green
            Write-SpiderLog "User APPROVED $ActionName" 'ACTION'
        }
        'S' {
            $result.Approved = $false
            $result.Choice = 'SKIP'
            Write-Host "  → SKIP (monitor)" -ForegroundColor Cyan
            Write-SpiderLog "User SKIP $ActionName" 'INFO'
        }
        default {
            $result.Approved = $false
            $result.Choice = 'DENY'
            Write-Host "  → DENIED" -ForegroundColor Red
            Write-SpiderLog "User DENIED $ActionName" 'INFO'
        }
    }
    Write-Host ""
    return $result
}

function Request-SpiderApprovalIfNeeded {
    param(
        $Decision,
        [switch]$ForcePrompt
    )
    if (-not $Decision) {
        return [pscustomobject]@{ Approved = $false; Skipped = $true; Choice = 'NO_DECISION' }
    }
    if (-not $Decision.RequiresApproval -and -not $ForcePrompt) {
        return [pscustomobject]@{
            Approved = [bool]$Decision.AutoExecute
            Skipped  = $true
            Choice   = 'AUTO_POLICY'
            Action   = $Decision.Action
            Risk     = $Decision.Risk
        }
    }
    return Show-SpiderApproval `
        -ActionName $Decision.Action `
        -Risk $Decision.Risk `
        -Reason $(if ($Decision.Finding) { $Decision.Finding.RootCause } else { '' }) `
        -Mode $Decision.Mode `
        -ForcePrompt:$ForcePrompt
}
