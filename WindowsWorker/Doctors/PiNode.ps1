# ============================================================
# Doctors/PiNode.ps1 - Pi Node Doctor
# Multi-source: Docker container + MonitorLive + ports + desktop
# ============================================================
function Invoke-PiNodeDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: PiNode" 'DIAG'
    $issues = [System.Collections.Generic.List[string]]::new()
    $procs = $Snapshot.PiProcesses
    $docker = $Snapshot.Docker
    $ports = $Snapshot.Ports
    $ml = $Snapshot.MonitorLive

    $piRunning = [bool]$docker.PiRunning
    $engine = [bool]$docker.EngineHealthy
    $nodeHealthy = [bool]$Snapshot.NodeHealthy
    $portsOpen = [bool]$ports.AnyOpen
    $listenHint = $false
    if ($docker.Runtime -and $docker.Runtime.PortsListening) { $listenHint = $true }

    # MonitorLive weak/strong signals
    $mlCtn = $false
    $mlPort = $false
    $mlStale = $true
    if ($ml) {
        $mlCtn = [bool]$ml.ContainerRunning
        $mlPort = [bool]$ml.PortOpen
        $mlStale = [bool]$ml.Stale
        if ($mlCtn -and -not $mlStale) { $piRunning = $true }
        if ($mlPort -and -not $mlStale) { $portsOpen = $true }
    }

    $evidence = [ordered]@{
        NodeHealthy = $nodeHealthy
        PiRunning = $piRunning
        EngineHealthy = $engine
        PreferredContainer = $(if ($docker.PreferredContainer) { $docker.PreferredContainer } else { $null })
        RunningContainer = $(if ($docker.RunningContainer) { $docker.RunningContainer } else { $null })
        ProcessCount = if ($procs) { @($procs).Count } else { 0 }
        PortsOpen = [int]$ports.OpenCount
        PortsListening = $listenHint
        MonitorLiveCtn = $mlCtn
        MonitorLivePort = $mlPort
        MonitorLiveStale = $mlStale
        Confidence = $(if ($docker.Confidence) { $docker.Confidence } else { $null })
        Method = $(if ($docker.Method) { $docker.Method } else { '' })
    }

    if (-not $engine) { [void]$issues.Add('DOCKER_ENGINE_DOWN') }
    if (-not $piRunning) { [void]$issues.Add('CONTAINER_NOT_RUNNING') }
    if (-not $procs -or @($procs).Count -eq 0) {
        [void]$issues.Add('NO_PI_DESKTOP_PROCESS')  # informational
    }
    if (-not $portsOpen -and -not $listenHint) { [void]$issues.Add('PORTS_NOT_LISTENING') }

    # Soften: ports listening + engine up => not CRITICAL for container name miss
    if ($issues -contains 'CONTAINER_NOT_RUNNING' -and $engine -and ($portsOpen -or $listenHint)) {
        [void]$issues.Remove('CONTAINER_NOT_RUNNING')
        [void]$issues.Add('CONTAINER_NAME_UNCONFIRMED')
        $piRunning = $true
        $evidence.PiRunning = $true
    }

    $status = 'OK'
    if ($issues -contains 'DOCKER_ENGINE_DOWN' -or $issues -contains 'CONTAINER_NOT_RUNNING') {
        $status = 'CRITICAL'
    } elseif ($issues -contains 'PORTS_NOT_LISTENING' -or $issues -contains 'CONTAINER_NAME_UNCONFIRMED') {
        $status = 'WARNING'
    } elseif ($issues -contains 'NO_PI_DESKTOP_PROCESS') {
        $status = 'INFO'  # Desktop closed while container runs is OK
    } elseif ($issues.Count -gt 0) {
        $status = 'WARNING'
    }

    $action = 'NONE'
    if ($issues -contains 'CONTAINER_NOT_RUNNING' -and $engine) {
        $action = 'RESTART_NODE'
    } elseif ($issues -contains 'DOCKER_ENGINE_DOWN') {
        $action = 'RESTART_DOCKER'
    } elseif ($issues -contains 'PORTS_NOT_LISTENING') {
        $action = 'FIREWALL_CHECK'
    }

    return [pscustomobject]@{
        Doctor = 'PiNode'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "Healthy=$nodeHealthy Pi=$piRunning Ports=$($ports.OpenCount) Ctn=$(if($docker.RunningContainer){$docker.RunningContainer}else{'-'})"
    }
}
