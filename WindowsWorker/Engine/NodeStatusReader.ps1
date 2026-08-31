#Requires -Version 5.1
# ============================================================
# Engine/NodeStatusReader.ps1
# 5-layer independent Pi Node status (fast path, no temperature)
# L1 Container | L2 Consensus | L3 Network | L4 Resources | L5 Blockchain
# ============================================================

function Invoke-SpiderDockerReadOnly {
    param([string[]]$DockerArgs, [int]$TimeoutSec = 12)
    try {
        $dockerExe = $null
        foreach ($cand in @(
            "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
            "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe",
            'docker'
        )) {
            if ($cand -eq 'docker') { $dockerExe = 'docker'; break }
            if ($cand -and (Test-Path -LiteralPath $cand)) { $dockerExe = $cand; break }
        }
        if (-not $dockerExe) { return $null }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $dockerExe
        $psi.Arguments = ($DockerArgs | ForEach-Object {
            $a = [string]$_
            if ($a -match '\s') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
        }) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        try { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit([Math]::Max(1000, $TimeoutSec * 1000))) {
            try { $p.Kill() } catch {}
            return $null
        }
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($out) -and $err) { return $err }
        if ([string]::IsNullOrWhiteSpace($out)) { return $null }
        return $out
    } catch { return $null }
}

function Get-SpiderPiContainerName {
    $prefer = @('testnet2', 'mainnet', 'testnet')
    try {
        $raw = Invoke-SpiderDockerReadOnly -DockerArgs @('ps', '--format', '{{.Names}}\t{{.Image}}') -TimeoutSec 8
        if ($raw) {
            $lines = $raw -split "`r?`n" | Where-Object { $_ -match '\S' }
            foreach ($pref in $prefer) {
                foreach ($line in $lines) {
                    if ($line -match "(?i)^$pref\t") { return $pref }
                }
            }
            foreach ($line in $lines) {
                if ($line -match '(?i)(pi-node|stellar|community|testnet|mainnet)') {
                    return ($line -split '\t')[0].Trim()
                }
            }
        }
    } catch {}
    return 'testnet2'
}

function Get-SpiderPiVolumeRoots {
    # Host mounts for Pi Network docker volumes (no hard fail if missing)
    $roots = New-Object System.Collections.Generic.List[string]
    $roaming = $env:APPDATA
    if ($roaming) {
        $base = Join-Path $roaming 'Pi Network\docker_volumes'
        if (Test-Path $base) {
            Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$roots.Add($_.FullName)
            }
            foreach ($n in @('testnet_2', 'testnet2', 'mainnet', 'mainnet_1')) {
                $p = Join-Path $base $n
                if (Test-Path $p) { [void]$roots.Add($p) }
            }
        }
    }
    return @($roots | Select-Object -Unique)
}

# ---------- Layer 1: Container State ----------
function Get-SpiderNodeLayer1 {
    param([string]$Container)
    $r = [ordered]@{
        Ok = $false; Running = $false; Paused = $false; OOMKilled = $false
        ExitCode = -1; Status = 'unknown'; StartedAt = $null; Error = $null
    }
    try {
        $raw = Invoke-SpiderDockerReadOnly -DockerArgs @(
            'inspect', $Container, '--format', '{{json .State}}'
        ) -TimeoutSec 8
        if (-not $raw) { $r.Error = 'inspect_failed'; return [pscustomobject]$r }
        $j = $raw | ConvertFrom-Json
        $r.Running = [bool]$j.Running
        $r.Paused = [bool]$j.Paused
        $r.OOMKilled = [bool]$j.OOMKilled
        try { $r.ExitCode = [int]$j.ExitCode } catch {}
        $r.Status = [string]$j.Status
        $r.StartedAt = [string]$j.StartedAt
        $r.Ok = $true
    } catch {
        $r.Error = $_.Exception.Message
    }
    return [pscustomobject]$r
}

# ---------- Layer 2: Consensus (logs + stellar-core info) ----------
function Convert-SpiderCoreInfoJson {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    $start = $Raw.IndexOf('{'); $end = $Raw.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        # regex only
        $state = $null; $age = $null; $auth = $null
        if ($Raw -match '"state"\s*:\s*"([^"]+)"') { $state = $Matches[1] }
        if ($Raw -match '"age"\s*:\s*(\d+)') { $age = [int]$Matches[1] }
        if ($Raw -match '"authenticated_count"\s*:\s*(\d+)') { $auth = [int]$Matches[1] }
        if ($state -or $null -ne $age) {
            return [pscustomobject]@{
                state = $state
                ledger = [pscustomobject]@{ age = $age }
                peers = [pscustomobject]@{ authenticated_count = $auth }
            }
        }
        return $null
    }
    try {
        $j = $Raw.Substring($start, $end - $start + 1) | ConvertFrom-Json
        if ($j.state -or $j.ledger -or $j.peers) { return $j }
    } catch {}
    return $null
}

function Get-SpiderNodeLayer2 {
    param([string]$Container, [switch]$SkipSlow)
    $r = [ordered]@{
        Ok = $false; State = 'Unknown'; Synced = $null; LedgerAgeSec = -1
        Peers = -1; Incoming = -1; Outgoing = -1; Method = 'none'
        ProcessHint = $null; Error = $null
    }
    # 2a stellar-core info (primary, accurate)
    $confs = @(
        '/opt/stellar/core/etc/stellar-core.cfg',
        '/opt/stellar/horizon/captive-data/captive-core/stellar-core.conf'
    )
    $info = $null
    foreach ($conf in $confs) {
        $raw = Invoke-SpiderDockerReadOnly -DockerArgs @(
            'exec', $Container, '/usr/bin/stellar-core', '--conf', $conf, 'http-command', 'info'
        ) -TimeoutSec 12
        $info = Convert-SpiderCoreInfoJson -Raw $raw
        if ($info) { $r.Method = 'exec-conf'; break }
    }
    if (-not $info) {
        $raw = Invoke-SpiderDockerReadOnly -DockerArgs @(
            'exec', $Container, 'stellar-core', 'http-command', 'info'
        ) -TimeoutSec 10
        $info = Convert-SpiderCoreInfoJson -Raw $raw
        if ($info) { $r.Method = 'exec-bin' }
    }
    if (-not $info) {
        foreach ($port in @(11626, 11625, 8000, 11627)) {
            $cmd = "curl -s --max-time 4 http://127.0.0.1:$port/info 2>/dev/null || wget -qO- http://127.0.0.1:$port/info 2>/dev/null || true"
            $raw = Invoke-SpiderDockerReadOnly -DockerArgs @('exec', $Container, 'sh', '-c', $cmd) -TimeoutSec 10
            $info = Convert-SpiderCoreInfoJson -Raw $raw
            if ($info) { $r.Method = "ctn-http-$port"; break }
        }
    }
    # supervisorctl status (process up != synced, but proves core alive)
    if (-not $info) {
        $sup = Invoke-SpiderDockerReadOnly -DockerArgs @(
            'exec', $Container, 'supervisorctl', 'status'
        ) -TimeoutSec 8
        if ($sup -and $sup -match '(?i)stellar') {
            $r.ProcessHint = ($sup -split "`n" | Where-Object { $_ -match 'stellar' } | Select-Object -First 3) -join '; '
            if ($sup -match '(?i)stellar-core.*RUNNING') {
                $r.Ok = $true
                $r.Method = 'supervisorctl'
                $r.State = 'CoreRunning'
                $r.Synced = $null
            }
        }
    }
    # find stellar-core binary then info
    if (-not $info) {
        $find = Invoke-SpiderDockerReadOnly -DockerArgs @(
            'exec', $Container, 'sh', '-c',
            'command -v stellar-core; ls /usr/bin/stellar-core /usr/local/bin/stellar-core 2>/dev/null; true'
        ) -TimeoutSec 8
        if ($find) {
            foreach ($bin in @($find -split "`r?`n")) {
                $b = $bin.Trim()
                if (-not $b -or $b -notmatch 'stellar-core') { continue }
                $raw = Invoke-SpiderDockerReadOnly -DockerArgs @(
                    'exec', $Container, $b, 'http-command', 'info'
                ) -TimeoutSec 12
                $info = Convert-SpiderCoreInfoJson -Raw $raw
                if ($info) { $r.Method = "exec-find:$b"; break }
            }
        }
    }

    if ($info) {
        $r.Ok = $true
        try { $r.State = [string]$info.state } catch {}
        try {
            if ($null -ne $info.ledger.age) { $r.LedgerAgeSec = [int]$info.ledger.age }
        } catch {}
        try {
            if ($null -ne $info.peers.authenticated_count) {
                $r.Peers = [int]$info.peers.authenticated_count
                $r.Incoming = $r.Peers; $r.Outgoing = $r.Peers
            }
        } catch {}
        if ($r.State -match '(?i)^Synced') { $r.Synced = $true }
        elseif ($r.State -match '(?i)Catching|Joining|Stopping|Booting|Syncing') { $r.Synced = $false }
        elseif ($r.LedgerAgeSec -ge 0 -and $r.LedgerAgeSec -lt 30) { $r.Synced = $true }
        elseif ($r.LedgerAgeSec -gt 60) { $r.Synced = $false }
        else { $r.Synced = $false }
        return [pscustomobject]$r
    }

    # 2b host supervisor / stellar-core.log (fast file tail, no docker exec)
    if (-not $SkipSlow) {
        try {
            foreach ($root in (Get-SpiderPiVolumeRoots)) {
                $logCandidates = @(
                    (Join-Path $root 'supervisor_logs\stellar-core.log'),
                    (Join-Path $root 'stellar-core.log'),
                    (Join-Path $root 'logs\stellar-core.log')
                )
                foreach ($lp in $logCandidates) {
                    if (-not (Test-Path -LiteralPath $lp)) { continue }
                    $tail = Get-Content -LiteralPath $lp -Tail 80 -ErrorAction SilentlyContinue
                    if (-not $tail) { continue }
                    $text = $tail -join "`n"
                    $r.Ok = $true
                    $r.Method = 'host-log'
                    if ($text -match '(?i)\bSynced\b') { $r.State = 'Synced'; $r.Synced = $true }
                    elseif ($text -match '(?i)Catching up|Syncing') { $r.State = 'Catching up'; $r.Synced = $false }
                    elseif ($text -match '(?i)CONSENSUS|QUORUM') { $r.State = 'Consensus active'; $r.Synced = $null }
                    $r.ProcessHint = 'log-scan'
                    return [pscustomobject]$r
                }
            }
        } catch {
            $r.Error = $_.Exception.Message
        }
    }
    $r.Error = 'consensus_unavailable'
    return [pscustomobject]$r
}

# ---------- Layer 3: Network / ports ----------
function Get-SpiderNodeLayer3 {
    param([string]$Container)
    $r = [ordered]@{
        Ok = $false
        Ports = @{}
        HostListen = @{}
        DockerPortRaw = $null
        Error = $null
    }
    try {
        $raw = Invoke-SpiderDockerReadOnly -DockerArgs @('port', $Container) -TimeoutSec 6
        $r.DockerPortRaw = $raw
        if ($raw) {
            foreach ($line in ($raw -split "`r?`n")) {
                if ($line -match '(\d+)/tcp\s*->\s*.*:(\d+)') {
                    $r.Ports[$Matches[1]] = $Matches[2]
                }
            }
        }
        # Host listening on Pi ports
        foreach ($hp in @(31401, 31402, 31403, 31400)) {
            $listen = $false
            try {
                $c = Get-NetTCPConnection -LocalPort $hp -State Listen -ErrorAction SilentlyContinue
                if ($c) { $listen = $true }
            } catch {
                try {
                    $tn = New-Object System.Net.Sockets.TcpClient
                    $iar = $tn.BeginConnect('127.0.0.1', $hp, $null, $null)
                    $ok = $iar.AsyncWaitHandle.WaitOne(200)
                    if ($ok -and $tn.Connected) { $listen = $true }
                    $tn.Close()
                } catch {}
            }
            $r.HostListen["$hp"] = $listen
        }
        $r.Ok = $true
    } catch {
        $r.Error = $_.Exception.Message
    }
    return [pscustomobject]$r
}

# ---------- Layer 4: Resources (docker stats) — may be slower ----------
function Get-SpiderNodeLayer4 {
    param([string]$Container, [switch]$Skip)
    $r = [ordered]@{
        Ok = $false; CpuPercent = $null; MemUsage = $null; MemLimit = $null
        NetIO = $null; Error = $null; Skipped = [bool]$Skip
    }
    if ($Skip) { return [pscustomobject]$r }
    try {
        $raw = Invoke-SpiderDockerReadOnly -DockerArgs @(
            'stats', $Container, '--no-stream', '--format',
            '{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}'
        ) -TimeoutSec 10
        if (-not $raw) { $r.Error = 'stats_failed'; return [pscustomobject]$r }
        $parts = ($raw.Trim() -split '\|')
        if ($parts.Count -ge 1) {
            $cpu = ($parts[0] -replace '%', '').Trim()
            try { $r.CpuPercent = [double]$cpu } catch {}
        }
        if ($parts.Count -ge 2) { $r.MemUsage = $parts[1].Trim() }
        if ($parts.Count -ge 3) { $r.NetIO = $parts[2].Trim() }
        $r.Ok = $true
    } catch {
        $r.Error = $_.Exception.Message
    }
    return [pscustomobject]$r
}

# ---------- Layer 5: Blockchain data on host volume (light) ----------
function Get-SpiderNodeLayer5 {
    param([switch]$Skip)
    $r = [ordered]@{
        Ok = $false; DataSizeMB = $null; LastHistoryWrite = $null
        HistoryFresh = $null; Path = $null; Error = $null; Skipped = [bool]$Skip
    }
    if ($Skip) { return [pscustomobject]$r }
    try {
        foreach ($root in (Get-SpiderPiVolumeRoots)) {
            $stellar = Join-Path $root 'stellar'
            if (-not (Test-Path $stellar)) { $stellar = $root }
            if (-not (Test-Path $stellar)) { continue }
            $r.Path = $stellar
            # Light: only top-level size sample, not full -Recurse (slow)
            $sum = 0L
            Get-ChildItem -LiteralPath $stellar -File -ErrorAction SilentlyContinue | ForEach-Object { $sum += $_.Length }
            Get-ChildItem -LiteralPath $stellar -Directory -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object {
                Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 50 | ForEach-Object { $sum += $_.Length }
            }
            $r.DataSizeMB = [math]::Round($sum / 1MB, 2)
            $hist = Join-Path $stellar 'history'
            if (Test-Path $hist) {
                $last = Get-ChildItem $hist -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($last) {
                    $r.LastHistoryWrite = $last.LastWriteTime.ToString('o')
                    $ageMin = ((Get-Date) - $last.LastWriteTime).TotalMinutes
                    $r.HistoryFresh = ($ageMin -lt 15)
                }
            }
            $r.Ok = $true
            break
        }
        if (-not $r.Ok) { $r.Error = 'volume_not_found' }
    } catch {
        $r.Error = $_.Exception.Message
    }
    return [pscustomobject]$r
}

function Get-SpiderNodeFiveLayerStatus {
    param(
        [string]$Container = '',
        [switch]$Fast,
        [switch]$IncludeSlow
    )
    if (-not $Container) { $Container = Get-SpiderPiContainerName }
    $fast = $Fast -or (-not $IncludeSlow)
    # Fast = L1+L2+L3 always; L4/L5 optional deferred
    $l1 = Get-SpiderNodeLayer1 -Container $Container
    $l2 = Get-SpiderNodeLayer2 -Container $Container
    $l3 = Get-SpiderNodeLayer3 -Container $Container
    $l4 = Get-SpiderNodeLayer4 -Container $Container -Skip:$fast
    $l5 = Get-SpiderNodeLayer5 -Skip:$fast

    # Overall
    $health = 'UNKNOWN'
    $synced = $l2.Synced
    if (-not $l1.Running) { $health = 'DOWN' }
    elseif ($l1.OOMKilled) { $health = 'CRITICAL' }
    elseif ($l1.Paused) { $health = 'DEGRADED' }
    elseif ($synced -eq $true) { $health = 'HEALTHY' }
    elseif ($synced -eq $false) { $health = 'CATCHING_UP' }
    elseif ($l1.Running) { $health = 'RUNNING_SYNC_UNKNOWN' }

    $summary = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Container = $Container
        Overall = $health
        Synced = $synced
        State = $l2.State
        LedgerAgeSec = $l2.LedgerAgeSec
        Peers = $l2.Peers
        Layer1 = $l1
        Layer2 = $l2
        Layer3 = $l3
        Layer4 = $l4
        Layer5 = $l5
        FastMode = [bool]$fast
    }
    return [pscustomobject]$summary
}

function Save-SpiderNodeStatusLatest {
    param($Status)
    if (-not $script:SpiderRoot) { return }
    $dir = Join-Path $script:SpiderRoot 'Data'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'node_status_latest.json'
    try { ($Status | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8 } catch {}
    return $path
}

function Get-SpiderIndependentNodeStatus {
    # Fast path every tick (L1-L3); maps to legacy Stellar fields
    $five = Get-SpiderNodeFiveLayerStatus -Fast
    try { Save-SpiderNodeStatusLatest -Status $five | Out-Null } catch {}

    $available = [bool]($five.Layer1.Running -or $five.Layer2.Ok)
    return [pscustomobject]@{
        Available    = $available
        Synced       = $five.Synced
        State        = $five.State
        LedgerAgeSec = $five.LedgerAgeSec
        LedgerNum    = $null
        Peers        = $five.Peers
        Incoming     = $(if ($five.Layer2) { $five.Layer2.Incoming } else { -1 })
        Outgoing     = $(if ($five.Layer2) { $five.Layer2.Outgoing } else { -1 })
        Container    = $five.Container
        Method       = $(if ($five.Layer2 -and $five.Layer2.Method) { $five.Layer2.Method } else { 'five-layer-fast' })
        Evidence     = @(
            "L1_running=$($five.Layer1.Running)",
            "L2_state=$($five.State)",
            "L2_method=$($five.Layer2.Method)",
            "overall=$($five.Overall)"
        )
        Timestamp    = $five.Timestamp
        FiveLayer    = $five
        Overall      = $five.Overall
    }
}

function Get-SpiderDataLiveStatus {
    # Alias: full layers including L4/L5 (slower, for patrol)
    $five = Get-SpiderNodeFiveLayerStatus -IncludeSlow
    try { Save-SpiderNodeStatusLatest -Status $five | Out-Null } catch {}
    return $five
}

function Get-SpiderNodeSyncState {
    return Get-SpiderIndependentNodeStatus
}
