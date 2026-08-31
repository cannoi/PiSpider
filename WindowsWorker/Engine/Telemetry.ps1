# ============================================================
# Engine/Telemetry.ps1
# Telemetry độc lập - không phụ thuộc Controller/MonitorLive
# Nếu tìm thấy latest.json của MonitorLive thì chỉ ENRICH, không bắt buộc
# ============================================================

function Find-MonitorLiveLatest {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:PINODE_MONITOR_LIVE -and (Test-Path -LiteralPath $env:PINODE_MONITOR_LIVE)) {
        return $env:PINODE_MONITOR_LIVE
    }
    if ($env:PINODE_CONTROLLER_DATA) {
        $cd = $env:PINODE_CONTROLLER_DATA
        [void]$candidates.Add((Join-Path $cd 'PiNodeMonitorLive\latest.json'))
        [void]$candidates.Add((Join-Path $cd 'latest.json'))
    }
    $root = $script:SpiderRoot
    if ($root) {
        @(
            (Join-Path $root 'Data\PiNodeMonitorLive\latest.json'),
            (Join-Path $root 'Data\PiNodeMonitorLive_CMD_v2\data\latest.json'),
            (Join-Path $root '..\Data\PiNodeMonitorLive\latest.json'),
            (Join-Path $root '..\Data\PiNodeMonitorLive_CMD_v2\data\latest.json')
        ) | ForEach-Object { [void]$candidates.Add($_) }
    }
    $appData = $env:LOCALAPPDATA
    if ($appData) {
        @(
            (Join-Path $appData 'PiNode\Data\PiNodeMonitorLive\latest.json'),
            (Join-Path $appData 'Pi_Node_Telegram_Controller_PRO\Data\PiNodeMonitorLive\latest.json'),
            (Join-Path $appData 'Pi_Node_Telegram_Controller_PRO\Data\latest.json')
        ) | ForEach-Object { [void]$candidates.Add($_) }
    }
    $desk = [Environment]::GetFolderPath('Desktop')
    if ($desk) {
        # Broad search under Desktop/Auto-Update-GitHub (common user layout)
        $roots = @(
            $desk,
            (Join-Path $desk 'Auto-Update-GitHub'),
            (Join-Path $env:USERPROFILE 'Desktop\Auto-Update-GitHub')
        )
        foreach ($r in $roots) {
            if (-not $r -or -not (Test-Path $r)) { continue }
            try {
                Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    [void]$candidates.Add((Join-Path $_.FullName 'Data\PiNodeMonitorLive\latest.json'))
                    [void]$candidates.Add((Join-Path $_.FullName 'Data\latest.json'))
                }
            } catch {}
            [void]$candidates.Add((Join-Path $r 'Data\PiNodeMonitorLive\latest.json'))
            [void]$candidates.Add((Join-Path $r 'Data\latest.json'))
        }
    }
    if ($root) {
        $parent = Split-Path $root -Parent
        for ($i = 0; $i -lt 5 -and $parent; $i++) {
            [void]$candidates.Add((Join-Path $parent 'Data\PiNodeMonitorLive\latest.json'))
            [void]$candidates.Add((Join-Path $parent 'Data\latest.json'))
            $parent = Split-Path $parent -Parent
        }
    }
    $best = $null
    $bestTime = [datetime]::MinValue
    foreach ($cand in $candidates) {
        if (-not $cand -or -not (Test-Path -LiteralPath $cand)) { continue }
        try {
            $item = Get-Item -LiteralPath $cand
            if ($item.LastWriteTime -gt $bestTime) {
                $bestTime = $item.LastWriteTime
                $best = $cand
            }
        } catch {
            if (-not $best) { $best = $cand }
        }
    }
    return $best
}

function Read-MonitorLiveSnapshot {
    # No external MonitorLive — Spider owns status via NodeStatusReader.ps1
    return $null
}


function Get-Prop {
    param($Object, [string[]]$Names)
    if (-not $Object) { return $null }
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}

function Get-StellarFromDocker {
    # Independent best-effort: inspect running containers for stellar/pi node
    $result = [pscustomobject]@{
        Available = $false
        Synced = $null
        LedgerAgeSec = -1
        Peers = -1
        Incoming = -1
        Outgoing = -1
        Container = $null
        Method = 'none'
    }
    $dockerCmd = Get-Command docker.exe -ErrorAction SilentlyContinue
    if (-not $dockerCmd) { return $result }

    try {
        $rows = & docker.exe ps --format '{{.Names}}|{{.Status}}' 2>$null
        if ($LASTEXITCODE -ne 0) { return $result }
        $piName = $null
        foreach ($r in $rows) {
            $parts = $r -split '\|'
            if ($parts[0] -match '(?i)(pi|stellar|testnet|mainnet|solohost|node)' -and $parts[1] -match 'Up') {
                $piName = $parts[0]
                break
            }
        }
        if (-not $piName) { return $result }
        $result.Container = $piName
        $result.Available = $true
        $result.Method = 'docker-ps'

        # Try stellar-core http info inside container (common ports 11626)
        try {
            $info = & docker.exe exec $piName curl -s --max-time 3 http://127.0.0.1:11626/info 2>$null
            if ($info -and $info.Trim().StartsWith('{')) {
                $ij = $info | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($ij) {
                    $result.Method = 'stellar-http'
                    # Parse loosely
                    $state = $null
                    if ($ij.info) { $state = $ij.info }
                    elseif ($ij) { $state = $ij }
                    if ($state) {
                        $ledger = Get-Prop $state @('ledger','Ledger')
                        if ($ledger) {
                            $age = Get-Prop $ledger @('age','Age')
                            if ($null -ne $age) { $result.LedgerAgeSec = [int]$age }
                        }
                        $peers = Get-Prop $state @('peers','Peers')
                        if ($null -ne $peers) {
                            if ($peers -is [int] -or $peers -match '^\d+$') { $result.Peers = [int]$peers }
                        }
                        $status = [string](Get-Prop $state @('state','State','status'))
                        if ($status -match '(?i)Synced|Catching') { $result.Synced = ($status -match '(?i)Synced') }
                        else { $result.Synced = ($result.LedgerAgeSec -ge 0 -and $result.LedgerAgeSec -lt 30) }
                    }
                }
            }
        } catch {}

        if ($null -eq $result.Synced) {
            # Container Up != ledger Synced. Unknown until MonitorLive or stellar info.
            $result.Synced = $null
            $result.LedgerAgeSec = -1
            $result.Peers = -1
            $result.Method = 'docker-container-up-unknown-sync'
        }
    } catch {}
    return $result
}

function Get-EnrichedStellarStatus {
    # Independent Spider reader only — no MonitorLive / Controller dependency
    if (Get-Command Get-SpiderIndependentNodeStatus -ErrorAction SilentlyContinue) {
        $st = Get-SpiderIndependentNodeStatus
        return [pscustomobject]@{
            Synced          = $st.Synced
            LedgerAgeSec    = $st.LedgerAgeSec
            Peers           = $st.Peers
            Incoming        = $st.Incoming
            Outgoing        = $st.Outgoing
            Available       = $st.Available
            Method          = $st.Method
            Container       = $st.Container
            State           = $st.State
            LedgerNum       = $st.LedgerNum
            Evidence        = $st.Evidence
            Overall         = $st.Overall
            FiveLayer       = $st.FiveLayer
        }
    }
    # Fallback legacy docker-only (unknown sync)
    $own = Get-StellarFromDocker
    return $own
}



function Get-ConfiguredPiContainerName {
    $cands = New-Object System.Collections.Generic.List[string]
    $add = {
        param($n)
        $n = ([string]$n).Trim()
        if (-not $n) { return }
        if ($n -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { return }
        if (-not $cands.Contains($n)) { [void]$cands.Add($n) }
    }
    $roots = @()
    if ($script:SpiderRoot) {
        $roots += $script:SpiderRoot
        $p = Split-Path $script:SpiderRoot -Parent
        for ($i = 0; $i -lt 5 -and $p; $i++) { $roots += $p; $p = Split-Path $p -Parent }
    }
    $desk = [Environment]::GetFolderPath('Desktop')
    if ($desk) { $roots += $desk }
    if ($env:LOCALAPPDATA) { $roots += $env:LOCALAPPDATA }
    foreach ($r in $roots) {
        foreach ($rel in @(
            'Data\PiNodeMonitorLive\container_name.txt',
            'PiNodeMonitorLive\container_name.txt',
            'Data\container_name.txt',
            'Pi_Node_Telegram_Controller_PRO\Data\PiNodeMonitorLive\container_name.txt'
        )) {
            $f = Join-Path $r $rel
            if (Test-Path -LiteralPath $f) {
                try {
                    $n = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue).Trim()
                    & $add $n
                } catch {}
            }
        }
    }
    # MonitorLive snapshot preferred name
    try {
        $ml = Read-MonitorLiveSnapshot
        if ($ml -and $ml.PiContainer) { & $add ([string]$ml.PiContainer) }
    } catch {}
    foreach ($d in @('testnet2','mainnet','testnet','pi-node','stellar','solohost')) { & $add $d }
    return @($cands)
}

function Invoke-DockerCliTimed {
    param([string[]]$DockerArgs, [int]$TimeoutSec = 10)
    $dockerExe = $null
    foreach ($c in @('docker.exe','docker')) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $dockerExe = $cmd.Source; break }
    }
    if (-not $dockerExe) { return [pscustomobject]@{ Ok=$false; Output=$null; ExitCode=-1 } }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $dockerExe
        $psi.Arguments = ($DockerArgs -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            return [pscustomobject]@{ Ok=$false; Output=$null; ExitCode=-2; TimedOut=$true }
        }
        $out = $p.StandardOutput.ReadToEnd()
        return [pscustomobject]@{
            Ok = ($p.ExitCode -eq 0)
            Output = $out
            ExitCode = $p.ExitCode
            TimedOut = $false
        }
    } catch {
        return [pscustomobject]@{ Ok=$false; Output=$null; ExitCode=-3; Error=$_.Exception.Message }
    }
}

function Get-PiNodeRuntimeStatus {
    <#
    Multi-source consensus (aligned with PiNodeMonitorLive):
      1) docker CLI (ps / inspect preferred container)
      2) MonitorLive latest.json (docker, container_status, port, sync)
      3) Local ports 31401-31403 LISTEN
      4) Pi Desktop process (optional, never sole CRITICAL)
    #>
    $evidence = [System.Collections.Generic.List[string]]::new()
    $ml = $null
    try { $ml = Read-MonitorLiveSnapshot } catch {}

    # --- Docker daemon ---
    $engine = $false
    $info = Invoke-DockerCliTimed -DockerArgs @('info','--format','{{.ServerVersion}}') -TimeoutSec 8
    if ($info.Ok -and $info.Output -and $info.Output.Trim()) {
        $engine = $true
        [void]$evidence.Add('docker_info_ok')
    } else {
        # Fallback: docker version / docker ps may still work
        $ver = Invoke-DockerCliTimed -DockerArgs @('version','--format','{{.Server.Version}}') -TimeoutSec 6
        if ($ver.Ok -and $ver.Output -and $ver.Output.Trim()) {
            $engine = $true
            [void]$evidence.Add('docker_version_ok')
        }
    }

    # --- Containers ---
    $allRows = @()
    $piRows = @()
    $preferredName = $null
    $piRunning = $false
    $runningName = $null
    $wantedList = @(Get-ConfiguredPiContainerName)

    if ($engine -or $true) {
        $psOut = Invoke-DockerCliTimed -DockerArgs @('ps','-a','--format','{{.Names}}|{{.Status}}|{{.Image}}') -TimeoutSec 10
        if ($psOut.Ok -or ($psOut.Output -and $psOut.Output.Trim())) {
            if (-not $engine -and $psOut.Output) {
                $engine = $true
                [void]$evidence.Add('docker_ps_implies_engine')
            }
            foreach ($line in ($psOut.Output -split "`r?`n")) {
                if (-not $line.Trim()) { continue }
                $parts = $line -split '\|'
                if ($parts.Count -lt 2) { continue }
                $obj = [pscustomobject]@{ Name=$parts[0].Trim(); Status=$parts[1].Trim(); Image=$(if($parts.Count -gt 2){$parts[2].Trim()}else{''}) }
                $allRows += $obj
            }
            [void]$evidence.Add(('docker_ps_count={0}' -f $allRows.Count))
        }
    }

    # Rank: configured names first, then pattern
    foreach ($want in $wantedList) {
        $hit = @($allRows | Where-Object { $_.Name -eq $want })
        if ($hit.Count -gt 0) {
            $preferredName = $want
            $piRows += $hit
            if ($hit[0].Status -match '(?i)\bUp\b') {
                $piRunning = $true
                $runningName = $want
                [void]$evidence.Add("container_up:$want")
            } else {
                [void]$evidence.Add("container_exists_not_up:$want")
            }
            break
        }
    }
    if (-not $piRunning) {
        foreach ($obj in $allRows) {
            if ($obj.Name -match '(?i)(testnet|mainnet|stellar|horizon|pi.?node|solohost|core)' -and $obj.Status -match '(?i)\bUp\b') {
                $piRunning = $true
                $runningName = $obj.Name
                $piRows += $obj
                [void]$evidence.Add("pattern_up:$($obj.Name)")
                break
            }
        }
    }
    if ($piRows.Count -eq 0) {
        $piRows = @($allRows | Where-Object { $_.Name -match '(?i)(testnet|mainnet|stellar|horizon|pi.?node|solohost|core|node)' })
    }

    # --- MonitorLive enrich (never sole source for CRITICAL if stale) ---
    $mlDocker = $false
    $mlCtn = $false
    $mlPort = $false
    if ($ml) {
        [void]$evidence.Add("monitorlive:$($ml.SourcePath)")
        if ($ml.AgeMinutes -ne $null) { [void]$evidence.Add("ml_age_min=$($ml.AgeMinutes)") }
        if ($ml.DockerRunning) { $mlDocker = $true; [void]$evidence.Add('ml_docker_RUNNING') }
        if ($ml.ContainerRunning) { $mlCtn = $true; [void]$evidence.Add('ml_container_running') }
        if ($ml.PortOpen) { $mlPort = $true; [void]$evidence.Add('ml_port_OPEN') }
        if ($ml.PiContainer -and -not $runningName) { $preferredName = [string]$ml.PiContainer }
        # If CLI failed but ML says running and not stale -> trust ML for PiRunning
        if (-not $piRunning -and $mlCtn -and -not $ml.Stale) {
            $piRunning = $true
            $runningName = [string]$ml.PiContainer
            [void]$evidence.Add('pi_running_from_monitorlive')
        }
        if (-not $engine -and $mlDocker -and -not $ml.Stale) {
            $engine = $true
            [void]$evidence.Add('engine_from_monitorlive')
        }
    }

    # --- Ports LISTEN (MonitorLive style) ---
    $listenCount = 0
    $listenMap = @{}
    foreach ($pt in @(31401, 31402, 31403)) {
        $ok = $false
        try {
            $ok = [bool](Get-NetTCPConnection -State Listen -LocalPort $pt -ErrorAction SilentlyContinue | Select-Object -First 1)
        } catch {}
        if (-not $ok) {
            try {
                $ok = [bool](netstat -ano 2>$null | Select-String -Pattern (":$pt\s+.*LISTENING") | Select-Object -First 1)
            } catch {}
        }
        $listenMap["$pt"] = $ok
        if ($ok) { $listenCount++ }
    }
    $portsListening = ($listenCount -ge 2)
    if ($portsListening) { [void]$evidence.Add("ports_listen=$listenCount") }

    # Ports open + docker engine => strong signal node stack up even if name mismatch
    if (-not $piRunning -and $engine -and $portsListening) {
        $piRunning = $true
        [void]$evidence.Add('pi_running_inferred_ports+docker')
    }
    if (-not $piRunning -and $mlPort -and $mlDocker -and -not $ml.Stale) {
        $piRunning = $true
        [void]$evidence.Add('pi_running_inferred_ml_port+docker')
    }

    # --- Pi Desktop process (informational) ---
    $desktop = @()
    try {
        $desktop = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match '(?i)^(Pi Desktop|PiDesktop|Pi Network|PiNetwork)$' -or
            $_.MainWindowTitle -match '(?i)Pi (Desktop|Network|Node)'
        } | Select-Object -First 5 ProcessName, Id)
        if ($desktop.Count -gt 0) { [void]$evidence.Add('pi_desktop_process') }
    } catch {}

    $confidence = 50
    if ($piRunning -and $engine) { $confidence = 90 }
    if ($piRunning -and $portsListening) { $confidence = [math]::Max($confidence, 92) }
    if ($piRunning -and $mlCtn -and -not $ml.Stale) { $confidence = [math]::Max($confidence, 95) }
    if (-not $piRunning -and -not $engine) { $confidence = 80 }
    if (-not $piRunning -and $engine) { $confidence = 70 }

    $nodeHealthy = ($engine -eq $true -and $piRunning -eq $true)

    return [pscustomobject]@{
        EngineHealthy = $engine
        PiRunning = $piRunning
        NodeHealthy = $nodeHealthy
        PreferredContainer = $(if ($runningName) { $runningName } else { $preferredName })
        RunningContainer = $runningName
        Containers = $allRows
        PiContainers = $piRows
        PortsListenCount = $listenCount
        PortsListenMap = $listenMap
        PortsListening = $portsListening
        DesktopProcesses = $desktop
        MonitorLive = $ml
        Confidence = $confidence
        Evidence = @($evidence)
        Method = ($evidence -join ';')
    }
}
