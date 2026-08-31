# ============================================================
# Actions/HostReboot.ps1 - Controlled OS reboot (Risk: EXTREME)
# NEVER auto unless EMERGENCY-GUARDIAN + UserApproved + Force
# ============================================================
function Invoke-HostReboot {
    param(
        [int]$DelaySec = 60,
        [string]$Reason = 'Spider prolonged recovery failure'
    )
    Write-SpiderLog "ACTION: HOST_REBOOT requested delay=${DelaySec}s reason=$Reason" 'WARN'

    $cfg = Get-SpiderConfig
    $mode = if ($cfg) { $cfg.Mode } else { 'ASSIST' }

    # Hard safety - never silent reboot
    if ($mode -notin @('EMERGENCY-GUARDIAN') -and -not $script:SpiderForceReboot) {
        return [pscustomobject]@{
            Action = 'HOST_REBOOT'; Risk = 'EXTREME'; Success = $false
            Message = 'Blocked: need EMERGENCY-GUARDIAN mode + explicit approval (or -Force with policy)'
        }
    }

    if (-not (Test-IsAdmin)) {
        return [pscustomobject]@{
            Action = 'HOST_REBOOT'; Risk = 'EXTREME'; Success = $false
            Message = 'Need Administrator to schedule reboot'
        }
    }

    try {
        # shutdown.exe /r /t delay /c reason
        $msg = "PiNodeSpider: $Reason"
        $arg = "/r /t $DelaySec /c `"$msg`""
        Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList $arg -WindowStyle Hidden
        Write-SpiderLog "HOST_REBOOT scheduled in ${DelaySec}s" 'ACTION'
        return [pscustomobject]@{
            Action = 'HOST_REBOOT'; Risk = 'EXTREME'; Success = $true
            DelaySec = $DelaySec
            Message = "Reboot scheduled in $DelaySec seconds. Cancel: shutdown /a"
        }
    } catch {
        return [pscustomobject]@{
            Action = 'HOST_REBOOT'; Risk = 'EXTREME'; Success = $false
            Message = $_.Exception.Message
        }
    }
}
