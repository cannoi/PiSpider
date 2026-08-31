# ============================================================
# Actions/DockerRecovery.ps1
# SAFE ordered recovery - NEVER hang on docker stop / random wsl --shutdown
#
# Ladder (minimal -> maximal):
#   1) RESTART_NODE     - docker restart <pi container only>
#   2) SOFT_DOCKER      - graceful quit Docker Desktop, wait, start (no wsl)
#   3) ORDERED_WSL      - quit Docker Desktop FIRST, then wsl --shutdown, then start Docker
#   4) RESTART_DOCKER   - ordered hard path (no image prune-a by default)
#
# Root cause of hang (user incident):
#   wsl --shutdown WHILE Docker Desktop backend still running
#   + docker stop without timeout on lagging engine
# ============================================================

function Invoke-DockerCliTimeout {
    param(
        [string[]]$Args,
        [int]$TimeoutSec = 45
    )
    if (Get-Command Invoke-DockerCliTimed -ErrorAction SilentlyContinue) {
        return Invoke-DockerCliTimed -DockerArgs $Args -TimeoutSec $TimeoutSec
    }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $exe = (Get-Command docker.exe -ErrorAction SilentlyContinue)
        if (-not $exe) { $exe = Get-Command docker -ErrorAction SilentlyContinue }
        if (-not $exe) { return [pscustomobject]@{ Ok=$false; TimedOut=$false; Output=''; ExitCode=-1 } }
        $psi.FileName = $exe.Source
        $psi.Arguments = ($Args -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return [pscustomobject]@{ Ok=$false; TimedOut=$true; Output=''; ExitCode=-2 }
        }
        $out = $p.StandardOutput.ReadToEnd()
        return [pscustomobject]@{ Ok=($p.ExitCode -eq 0); TimedOut=$false; Output=$out; ExitCode=$p.ExitCode }
    } catch {
        return [pscustomobject]@{ Ok=$false; TimedOut=$false; Output=''; ExitCode=-3 }
    }
}

function Get-DockerDesktopPath {
    foreach ($p in @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Stop-DockerDesktopGraceful {
    param([int]$WaitSec = 40)
    $steps = [System.Collections.Generic.List[string]]::new()
    # Prefer com.docker.backend quit via process stop after trying docker desktop quit
    try {
        $dd = Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue
        if ($dd) {
            # Soft close main window if possible
            foreach ($proc in $dd) {
                try { $proc.CloseMainWindow() | Out-Null } catch {}
            }
            Start-Sleep -Seconds 5
            [void]$steps.Add('close_main_window')
        }
    } catch {}

    # Kill remaining Docker Desktop related processes (order matters)
    $names = @(
        'Docker Desktop',
        'com.docker.backend',
        'com.docker.build',
        'com.docker.proxy',
        'vpnkit'
    )
    foreach ($n in $names) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                [void]$steps.Add("kill:$n")
            } catch {}
        }
    }
    $deadline = (Get-Date).AddSeconds($WaitSec)
    while ((Get-Date) -lt $deadline) {
        $left = Get-Process -Name 'Docker Desktop','com.docker.backend' -ErrorAction SilentlyContinue
        if (-not $left) { break }
        Start-Sleep -Seconds 2
    }
    $still = Get-Process -Name 'Docker Desktop','com.docker.backend' -ErrorAction SilentlyContinue
    if ($still) {
        [void]$steps.Add('docker_desktop_still_running')
        return [pscustomobject]@{ Success = $false; Steps = @($steps) }
    }
    [void]$steps.Add('docker_desktop_stopped')
    return [pscustomobject]@{ Success = $true; Steps = @($steps) }
}

function Start-DockerDesktopAndWait {
    param([int]$MaxWaitSec = 180)
    $steps = [System.Collections.Generic.List[string]]::new()
    $path = Get-DockerDesktopPath
    if (-not $path) {
        return [pscustomobject]@{ Success = $false; Steps = @('docker_desktop_exe_missing') }
    }
    try {
        Start-Process -FilePath $path
        [void]$steps.Add('started_docker_desktop')
    } catch {
        return [pscustomobject]@{ Success = $false; Steps = @('start_failed') }
    }
    $ok = $false
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSec) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        if ((Test-DockerHealthy) -eq $true) { $ok = $true; break }
    }
    [void]$steps.Add("engine_healthy=$ok wait=${elapsed}s")
    return [pscustomobject]@{ Success = $ok; Steps = @($steps) }
}

function Invoke-WslShutdownSafe {
    # ONLY call after Docker Desktop processes are gone
    $steps = [System.Collections.Generic.List[string]]::new()
    $dd = Get-Process -Name 'Docker Desktop','com.docker.backend' -ErrorAction SilentlyContinue
    if ($dd) {
        [void]$steps.Add('ABORT_wsl_shutdown_docker_still_up')
        Write-SpiderLog "REFUSED wsl --shutdown: Docker Desktop still running (hang risk)" 'WARN'
        return [pscustomobject]@{ Success = $false; Steps = @($steps); Refused = $true }
    }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wsl.exe'
        $psi.Arguments = '--shutdown'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit(60000)) {
            try { $p.Kill() } catch {}
            [void]$steps.Add('wsl_shutdown_timeout')
            return [pscustomobject]@{ Success = $false; Steps = @($steps) }
        }
        [void]$steps.Add('wsl_shutdown_ok')
        Start-Sleep -Seconds 3
        return [pscustomobject]@{ Success = $true; Steps = @($steps) }
    } catch {
        [void]$steps.Add('wsl_shutdown_error')
        return [pscustomobject]@{ Success = $false; Steps = @($steps) }
    }
}

function Invoke-SoftDockerRestart {
    Write-SpiderLog "ACTION: SOFT_DOCKER_RESTART (no wsl --shutdown)" 'ACTION'
    $steps = [System.Collections.Generic.List[string]]::new()
    $stop = Stop-DockerDesktopGraceful -WaitSec 45
    foreach ($s in $stop.Steps) { [void]$steps.Add($s) }
    if (-not $stop.Success) {
        return [pscustomobject]@{
            Action = 'SOFT_DOCKER_RESTART'; Risk = 'HIGH'; Success = $false
            Steps = @($steps); Message = 'Could not stop Docker Desktop cleanly'
        }
    }
    Start-Sleep -Seconds 3
    $start = Start-DockerDesktopAndWait -MaxWaitSec 150
    foreach ($s in $start.Steps) { [void]$steps.Add($s) }
    return [pscustomobject]@{
        Action = 'SOFT_DOCKER_RESTART'; Risk = 'HIGH'
        Success = $start.Success; Steps = @($steps)
        Message = if ($start.Success) { 'Docker Desktop recycled without WSL shutdown' } else { 'Docker engine did not come back' }
    }
}

function Invoke-OrderedWslRecycle {
    Write-SpiderLog "ACTION: ORDERED_WSL_RECYCLE (Desktop stop -> wsl --shutdown -> start)" 'ACTION'
    $steps = [System.Collections.Generic.List[string]]::new()

    $stop = Stop-DockerDesktopGraceful -WaitSec 50
    foreach ($s in $stop.Steps) { [void]$steps.Add($s) }
    if (-not $stop.Success) {
        return [pscustomobject]@{
            Action = 'ORDERED_WSL_RECYCLE'; Risk = 'HIGH'; Success = $false
            Steps = @($steps)
            Message = 'Docker Desktop still running - refused wsl --shutdown to avoid hang'
        }
    }

    $wsl = Invoke-WslShutdownSafe
    foreach ($s in $wsl.Steps) { [void]$steps.Add($s) }
    if ($wsl.Refused) {
        return [pscustomobject]@{
            Action = 'ORDERED_WSL_RECYCLE'; Risk = 'HIGH'; Success = $false
            Steps = @($steps); Message = 'WSL shutdown refused - safety'
        }
    }

    Start-Sleep -Seconds 5
    $start = Start-DockerDesktopAndWait -MaxWaitSec 180
    foreach ($s in $start.Steps) { [void]$steps.Add($s) }

    return [pscustomobject]@{
        Action = 'ORDERED_WSL_RECYCLE'; Risk = 'HIGH'
        Success = $start.Success; Steps = @($steps)
        Message = if ($start.Success) { 'Ordered WSL+Docker recycle OK' } else { 'Engine still down after ordered recycle' }
    }
}

function Invoke-RestartDocker {
    # HARD path: ordered recycle; NO bulk docker stop hang; NO image prune -a
    Write-SpiderLog "ACTION: RESTART_DOCKER (ORDERED HARD - no hang-prone stop-all)" 'ACTION'
    $steps = [System.Collections.Generic.List[string]]::new()

    # Try soft first
    $soft = Invoke-SoftDockerRestart
    foreach ($s in $soft.Steps) { [void]$steps.Add("soft:$s") }
    if ($soft.Success) {
        return [pscustomobject]@{
            Action = 'RESTART_DOCKER'; Risk = 'HIGH'; Success = $true
            Steps = @($steps); Message = 'Recovered via soft Docker Desktop restart'
        }
    }

    # Escalate ordered WSL
    $ord = Invoke-OrderedWslRecycle
    foreach ($s in $ord.Steps) { [void]$steps.Add("ordered:$s") }
    return [pscustomobject]@{
        Action = 'RESTART_DOCKER'; Risk = 'HIGH'
        Success = $ord.Success; Steps = @($steps)
        Message = $ord.Message
    }
}

function Invoke-RestartWSL {
    Write-SpiderLog "ACTION: RESTART_WSL -> ORDERED_WSL_RECYCLE only" 'ACTION'
    $r = Invoke-OrderedWslRecycle
    return [pscustomobject]@{
        Action = 'RESTART_WSL'; Risk = 'HIGH'
        Success = $r.Success; Steps = $r.Steps; Message = $r.Message
    }
}
