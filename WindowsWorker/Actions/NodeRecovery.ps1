# ============================================================
# Actions/NodeRecovery.ps1 - Restart Pi container ONLY (Risk: HIGH)
# Prefer docker restart <name> with timeout - never wsl --shutdown
# ============================================================
function Invoke-RestartNode {
    Write-SpiderLog "ACTION: RESTART_NODE (container only, no WSL)" 'ACTION'
    $docker = Get-DockerInfo
    if (-not $docker.EngineHealthy) {
        return [pscustomobject]@{
            Action = 'RESTART_NODE'; Risk = 'HIGH'; Success = $false
            Message = 'Docker down - fix Docker first (dependency). Do NOT wsl --shutdown from here.'
        }
    }

    $targets = @()
    if ($docker.RunningContainer) { $targets += $docker.RunningContainer }
    if ($docker.PreferredContainer -and $targets -notcontains $docker.PreferredContainer) {
        $targets += $docker.PreferredContainer
    }
    foreach ($c in @($docker.PiContainers)) {
        if ($c.Name -and $targets -notcontains $c.Name) { $targets += $c.Name }
    }
    if ($targets.Count -eq 0) {
        $targets = @('testnet2','mainnet','testnet')
    }

    $restarted = @()
    $failed = @()
    foreach ($name in $targets) {
        $r = $null
        if (Get-Command Invoke-DockerCliTimeout -ErrorAction SilentlyContinue) {
            $r = Invoke-DockerCliTimeout -Args @('restart', $name) -TimeoutSec 60
        } elseif (Get-Command Invoke-DockerCliTimed -ErrorAction SilentlyContinue) {
            $r = Invoke-DockerCliTimed -DockerArgs @('restart', $name) -TimeoutSec 60
        } else {
            try {
                docker restart $name 2>$null | Out-Null
                $r = [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); TimedOut = $false }
            } catch { $r = [pscustomobject]@{ Ok = $false; TimedOut = $false } }
        }
        if ($r -and $r.Ok) {
            $restarted += $name
            Write-SpiderLog "docker restart $name OK" 'ACTION'
            break  # one success enough
        } elseif ($r -and $r.TimedOut) {
            $failed += "$name(timeout)"
            Write-SpiderLog "docker restart $name TIMEOUT - abort further restarts" 'WARN'
            break
        } else {
            # try start if not running
            if (Get-Command Invoke-DockerCliTimed -ErrorAction SilentlyContinue) {
                $s = Invoke-DockerCliTimed -DockerArgs @('start', $name) -TimeoutSec 45
                if ($s.Ok) { $restarted += $name; break }
            }
            $failed += $name
        }
    }

    Start-Sleep -Seconds 12
    $after = Get-DockerInfo
    $ok = [bool]$after.PiRunning
    # Port evidence
    if (-not $ok -and $after.Runtime -and $after.Runtime.PortsListening) { $ok = $true }

    return [pscustomobject]@{
        Action = 'RESTART_NODE'
        Risk = 'HIGH'
        Success = $ok
        Restarted = $restarted
        Failed = $failed
        PiRunning = $ok
        Message = if ($ok) { 'Pi container running after restart' } else { 'Container still down - escalate SOFT_DOCKER or ORDERED_WSL, not blind reset' }
    }
}
