# ============================================================
# Doctors/WSL.ps1 - WSL Doctor
# Availability, vmmem memory pressure, Docker dependency
# ============================================================
function Invoke-WSLDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: WSL" 'DIAG'
    $w = $Snapshot.WSL
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{
        Available = [bool]$w.Available
        VmmemMB = [int]$w.VmmemMB
        HighMem = [bool]$w.HighMem
    }

    if (-not $w.Available) {
        [void]$issues.Add('WSL_NOT_AVAILABLE')
    }
    if ($w.HighMem) {
        [void]$issues.Add('VMMEM_HIGH')
    }
    if ($w.VmmemMB -gt 12000) {
        [void]$issues.Add('VMMEM_VERY_HIGH')
    }

    # Docker depends on WSL2 backend typically
    if (-not $w.Available -and $Snapshot.Docker.EngineHealthy -eq $false) {
        [void]$issues.Add('WSL_DOCKER_COUPLED_FAILURE')
    }

    $status = 'OK'
    if ($issues -contains 'WSL_NOT_AVAILABLE' -or $issues -contains 'WSL_DOCKER_COUPLED_FAILURE') {
        $status = 'CRITICAL'
    } elseif ($issues.Count -gt 0) {
        $status = 'WARNING'
    }

    # High vmmem with healthy node → MONITOR not restart
    $action = 'NONE'
    if ($issues -contains 'WSL_NOT_AVAILABLE') { $action = 'RESTART_DOCKER' }
    elseif ($issues -contains 'VMMEM_HIGH' -and $Snapshot.NodeHealthy) { $action = 'MONITOR' }
    elseif ($issues -contains 'VMMEM_VERY_HIGH') { $action = 'MONITOR' }

    return [pscustomobject]@{
        Doctor = 'WSL'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "vmmem=$($w.VmmemMB)MB Available=$($w.Available)"
    }
}
