# ============================================================
# Doctors/Docker.ps1 - Docker Doctor
# Engine, containers, Pi-related containers, restart signals
# ============================================================
function Invoke-DockerDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Docker" 'DIAG'
    $d = $Snapshot.Docker
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{
        EngineHealthy = $d.EngineHealthy
        PiRunning = [bool]$d.PiRunning
        ContainerCount = if ($d.Containers) { @($d.Containers).Count } else { 0 }
        PiContainerCount = if ($d.PiContainers) { @($d.PiContainers).Count } else { 0 }
    }

    if ($d.EngineHealthy -eq $null) { [void]$issues.Add('CLI_MISSING') }
    if ($d.EngineHealthy -eq $false) { [void]$issues.Add('ENGINE_DOWN') }
    if ($d.EngineHealthy -eq $true -and -not $d.PiRunning) { [void]$issues.Add('PI_CONTAINER_DOWN') }

    $restarting = @()
    if ($d.PiContainers) {
        foreach ($c in $d.PiContainers) {
            if ($c.Status -match '(?i)Restarting|Exited|Dead|Paused') {
                $restarting += "$($c.Name):$($c.Status)"
                [void]$issues.Add('PI_CONTAINER_UNHEALTHY')
            }
        }
    }
    $evidence.UnhealthyPi = $restarting

    $status = 'OK'
    if ($issues -contains 'ENGINE_DOWN' -or $issues -contains 'CLI_MISSING') {
        $status = 'CRITICAL'
    } elseif ($issues -contains 'PI_CONTAINER_DOWN' -or $issues -contains 'PI_CONTAINER_UNHEALTHY') {
        $status = 'CRITICAL'
    } elseif ($issues.Count -gt 0) {
        $status = 'WARNING'
    }

    $action = 'NONE'
    if ($issues -contains 'ENGINE_DOWN') { $action = 'RESTART_DOCKER' }
    elseif ($issues -contains 'PI_CONTAINER_DOWN' -or $issues -contains 'PI_CONTAINER_UNHEALTHY') { $action = 'RESTART_NODE' }

    return [pscustomobject]@{
        Doctor = 'Docker'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "Engine=$($d.EngineHealthy) PiRunning=$($d.PiRunning)"
    }
}
