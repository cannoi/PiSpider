# ============================================================
# Actions/MonitorActions.ps1 - Non-mutating observe actions
# ============================================================
function Invoke-WaitMonitor {
    Write-SpiderLog "ACTION: WAIT_MONITOR - observe only" 'ACTION'
    return [pscustomobject]@{
        Action  = 'WAIT_MONITOR'
        Risk    = 'NONE'
        Success = $true
        Message = 'Continue monitoring - no change'
    }
}

function Invoke-MonitorOnly {
    Write-SpiderLog "ACTION: MONITOR - no change" 'ACTION'
    return [pscustomobject]@{
        Action  = 'MONITOR'
        Risk    = 'NONE'
        Success = $true
    }
}

function Invoke-ReportConfig {
    Write-SpiderLog "ACTION: REPORT_CONFIG" 'INFO'
    return [pscustomobject]@{
        Action  = 'REPORT_CONFIG'
        Risk    = 'NONE'
        Success = $true
        Message = 'Configuration change reported'
    }
}

function Invoke-NoneAction {
    return [pscustomobject]@{
        Action  = 'NONE'
        Risk    = 'NONE'
        Success = $true
    }
}
