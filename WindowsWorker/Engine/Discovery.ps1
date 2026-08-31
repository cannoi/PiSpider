# ============================================================
# Engine/Discovery.ps1 - System Map + Telemetry collection
# ============================================================

function Get-MemorySnapshot {
    # Win32_OperatingSystem.*MemorySize is in KILOBYTES (not bytes)
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (-not $os) { return $null }
    $totalKB = [double]$os.TotalVisibleMemorySize
    $freeKB  = [double]$os.FreePhysicalMemory
    $totalGB = [math]::Round($totalKB / 1MB, 2)   # KB / 1048576 = GB
    $freeGB  = [math]::Round($freeKB / 1MB, 2)
    $usedGB  = [math]::Max(0, [math]::Round($totalGB - $freeGB, 2))
    $pct     = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
    [pscustomobject]@{
        TotalGB = $totalGB
        FreeGB  = $freeGB
        UsedGB  = $usedGB
        UsedPct = $pct
        TotalKB = [int64]$totalKB
    }
}

function Get-CPUUsage {
    try { return [int]((Get-CimInstance Win32_Processor -EA SilentlyContinue | Measure-Object LoadPercentage -Average).Average) } catch { return 0 }
}

function Get-DiskSnapshot {
    try {
        $d = Get-PSDrive C -EA SilentlyContinue
        $free = [math]::Round($d.Free/1GB,1); $used = [math]::Round($d.Used/1GB,1); $total = $free+$used
        return [pscustomobject]@{ FreeGB=$free; UsedGB=$used; TotalGB=$total; FreePct=if($total-gt0){[math]::Round(($free/$total)*100,1)}else{0} }
    } catch { return [pscustomobject]@{ FreeGB=0; UsedGB=0; TotalGB=0; FreePct=0 } }
}

function Get-TopMemoryProcesses {
    param([int]$Top=12)
    Get-Process -EA SilentlyContinue | Where-Object { $_.WorkingSet64 -gt 50MB } |
        Sort-Object WorkingSet64 -Descending | Select-Object -First $Top |
        ForEach-Object {
            [pscustomobject]@{ Name=$_.ProcessName; PID=$_.Id; MB=[math]::Round($_.WorkingSet64/1MB,0); Protected=(Test-ProtectedProcess $_.ProcessName) }
        }
}

function Test-DockerHealthy {
    if (Get-Command Invoke-DockerCliTimed -ErrorAction SilentlyContinue) {
        $r = Invoke-DockerCliTimed -DockerArgs @('info','--format','{{.ServerVersion}}') -TimeoutSec 8
        if ($r.Ok -and $r.Output -and $r.Output.Trim()) { return $true }
        $r2 = Invoke-DockerCliTimed -DockerArgs @('ps','--format','{{.Names}}') -TimeoutSec 6
        if ($r2 -and -not $r2.TimedOut -and $r2.ExitCode -eq 0) { return $true }
        return $false
    }
    $cmd = Get-Command docker.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command docker -ErrorAction SilentlyContinue }
    if (-not $cmd) { return $null }
    try {
        $out = & $cmd.Source info --format '{{.ServerVersion}}' 2>$null
        return [bool]$out
    } catch { return $false }
}

function Get-DockerInfo {
    # Multi-source: MonitorLive + docker ps + ports (same idea as PiNodeMonitorLive)
    if (Get-Command Get-PiNodeRuntimeStatus -ErrorAction SilentlyContinue) {
        $rt = Get-PiNodeRuntimeStatus
        return [pscustomobject]@{
            EngineHealthy     = [bool]$rt.EngineHealthy
            Containers        = @($rt.Containers)
            PiContainers      = @($rt.PiContainers)
            PiRunning         = [bool]$rt.PiRunning
            PreferredContainer= $rt.PreferredContainer
            RunningContainer  = $rt.RunningContainer
            Confidence        = $rt.Confidence
            Evidence          = $rt.Evidence
            Method            = $rt.Method
            Runtime           = $rt
        }
    }
    $healthy = Test-DockerHealthy
    $containers = @(); $piContainers = @()
    if ($healthy -eq $true) {
        try {
            $exe = Get-Command docker.exe -ErrorAction SilentlyContinue
            if (-not $exe) { $exe = Get-Command docker -ErrorAction SilentlyContinue }
            if ($exe) {
                $rows = & $exe.Source ps -a --format "{{.Names}}|{{.Status}}|{{.Image}}" 2>$null
                foreach ($r in @($rows)) {
                    if (-not $r) { continue }
                    $parts = "$r".Split('|')
                    $obj = [pscustomobject]@{
                        Name  = $parts[0]
                        Status= $(if ($parts.Count -gt 1) { $parts[1] } else { '?' })
                        Image = $(if ($parts.Count -gt 2) { $parts[2] } else { '' })
                    }
                    $containers += $obj
                    if ($obj.Name -match '(?i)(pi|stellar|testnet|mainnet|node|solohost|hermes|horizon|core)') {
                        $piContainers += $obj
                    }
                }
            }
        } catch {}
    }
    return [pscustomobject]@{
        EngineHealthy = $healthy
        Containers    = $containers
        PiContainers  = $piContainers
        PiRunning     = @($piContainers | Where-Object { $_.Status -match '(?i)\bUp\b' }).Count -gt 0
    }
}

function Get-WSLStatus {
    $available = $false; $vmmemMB = 0
    try { $null = & wsl.exe -l -v 2>$null; $available = ($LASTEXITCODE -eq 0) } catch {}
    $v = Get-Process -Name 'vmmem','vmmemWSL' -EA SilentlyContinue
    if ($v) { $vmmemMB = [math]::Round(($v | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0) }
    return [pscustomobject]@{ Available=$available; VmmemMB=$vmmemMB; HighMem=($vmmemMB -gt 4000) }
}

function Get-NetworkStatus {
    $internet = $false; $dns = $false; $latency = -1
    # Prefer fast TCP to 8.8.8.8:53 / 1.1.1.1:53 - avoids long ICMP blocks
    try {
        if (Test-TcpPortFast -HostName "8.8.8.8" -Port 53 -TimeoutMs 800) { $internet = $true }
        elseif (Test-TcpPortFast -HostName "1.1.1.1" -Port 53 -TimeoutMs 800) { $internet = $true }
    } catch {}
    if (-not $internet) {
        try {
            $internet = [bool](Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue)
        } catch {}
    }
    try {
        $dns = [bool](Resolve-DnsName "google.com" -DnsOnly -NoHostsFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    } catch {}
    $adapter = Get-PrimaryAdapter
    $ip = $null; $gw = $null
    if ($adapter) {
        $ipCfg = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
        if ($ipCfg) { $ip = $ipCfg.IPAddress }
        try {
            $gw = (Get-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric | Select-Object -First 1).NextHop
        } catch {}
    }
    return [pscustomobject]@{
        Internet = $internet; DNS = $dns; LatencyMs = $latency
        Adapter = $(if ($adapter) { $adapter.Name } else { $null })
        IP = $ip; Gateway = $gw
    }
}

function Test-TcpPortFast {
    param([string]$HostName = "127.0.0.1", [int]$Port, [int]$TimeoutMs = 400)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) { return $false }
        $client.EndConnect($iar) | Out-Null
        return $true
    } catch { return $false }
    finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}

function Test-LocalPiPorts {
    # Prefer LISTEN state (same as MonitorLive) then fast TCP fallback
    $cfg = Get-SpiderConfig
    $ports = @(31401, 31402, 31403)
    if ($cfg -and $cfg.PiPorts) {
        $ports = @($cfg.PiPorts | Select-Object -First 5)
    }
    $results = @{}
    foreach ($pt in $ports) {
        $ok = $false
        try {
            $ok = [bool](Get-NetTCPConnection -State Listen -LocalPort ([int]$pt) -ErrorAction SilentlyContinue | Select-Object -First 1)
        } catch {}
        if (-not $ok) {
            try {
                $ok = [bool](netstat -ano 2>$null | Select-String -Pattern (":$pt\s+.*LISTENING") | Select-Object -First 1)
            } catch {}
        }
        if (-not $ok -and (Get-Command Test-TcpPortFast -ErrorAction SilentlyContinue)) {
            $ok = Test-TcpPortFast -Port ([int]$pt) -TimeoutMs 350
        }
        $results["$pt"] = [bool]$ok
    }
    $open = @($results.Values | Where-Object { $_ }).Count
    return [pscustomobject]@{ Ports = $results; AnyOpen = ($open -gt 0); OpenCount = $open }
}

function Get-StellarStatus {
    # Prefer enriched independent telemetry (docker + optional MonitorLive)
    if (Get-Command Get-EnrichedStellarStatus -ErrorAction SilentlyContinue) {
        $e = Get-EnrichedStellarStatus
        return [pscustomobject]@{
            Synced = $e.Synced
            LedgerAgeSec = $e.LedgerAgeSec
            Peers = $e.Peers
            Incoming = $e.Incoming
            Outgoing = $e.Outgoing
            Available = $e.Available
            Method = $e.Method
            Container = $e.Container
            State = $(if ($e.PSObject.Properties['State']) { $e.State } else { $null })
            LedgerNum = $(if ($e.PSObject.Properties['LedgerNum']) { $e.LedgerNum } else { $null })
            Evidence = $(if ($e.PSObject.Properties['Evidence']) { $e.Evidence } else { @() })
            Overall = $(if ($e.PSObject.Properties['Overall']) { $e.Overall } else { $null })
            FiveLayer = $(if ($e.PSObject.Properties['FiveLayer']) { $e.FiveLayer } else { $null })
        }
    }
    $synced = $null; $ledgerAge = -1; $peers = -1; $method = 'none'
    $docker = Get-DockerInfo
    if ($docker.EngineHealthy -and $docker.PiRunning) {
        $synced = $null
        $ledgerAge = -1
        $peers = -1
        $method = 'docker-container-up-unknown-sync'
    }
    return [pscustomobject]@{
        Synced = $synced; LedgerAgeSec = $ledgerAge; Peers = $peers
        Incoming = -1; Outgoing = -1
        Available = ($null -ne $synced)
        Method = $method
    }
}

function Get-PiNodeProcesses {
    $names = @('Pi Desktop','PiDesktop','Pi Network','PiNetwork','PiNode','DataLive','PiNodeMonitorLive','stellar-core')
    $found = @()
    foreach ($n in $names) {
        $p = Get-Process -Name $n -EA SilentlyContinue
        if ($p) { $found += $p | Select-Object ProcessName, Id, @{N='MB';E={[math]::Round($_.WorkingSet64/1MB,0)}} }
    }
    return $found
}

function Get-UptimeHours {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
    } catch { return 0 }
}

function Get-VirtualizationStatus {
    # Do NOT trust only Win32_Processor.VirtualizationFirmwareEnabled (often false/null
    # while Hyper-V / WSL2 / Docker are already running).
    $firmware = $null
    $hypervisorPresent = $null
    $dockerImpliesOK = $false
    $wslImpliesOK = $false
    $method = @()

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cpu.VirtualizationFirmwareEnabled) {
            $firmware = [bool]$cpu.VirtualizationFirmwareEnabled
            [void]$method.Add('Win32_Processor.VirtualizationFirmwareEnabled')
        }
    } catch {}

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($null -ne $cs.HypervisorPresent) {
            $hypervisorPresent = [bool]$cs.HypervisorPresent
            [void]$method.Add('Win32_ComputerSystem.HypervisorPresent')
        }
    } catch {}

    # Practical evidence: Docker engine up = virtualization works on this host
    try {
        if (Get-Command Test-DockerHealthy -ErrorAction SilentlyContinue) {
            $dh = Test-DockerHealthy
            if ($dh -eq $true) { $dockerImpliesOK = $true; [void]$method.Add('DockerEngineHealthy') }
        }
    } catch {}

    try {
        $vmmem = Get-Process -Name 'vmmem','vmmemWSL' -ErrorAction SilentlyContinue
        if ($vmmem) { $wslImpliesOK = $true; [void]$method.Add('vmmemRunning') }
    } catch {}

    # Effective enabled: any strong positive signal
    $enabled = $false
    if ($dockerImpliesOK -or $wslImpliesOK -or $hypervisorPresent -eq $true) {
        $enabled = $true
    } elseif ($firmware -eq $true) {
        $enabled = $true
    } elseif ($firmware -eq $false -and -not $dockerImpliesOK -and -not $wslImpliesOK -and $hypervisorPresent -ne $true) {
        $enabled = $false
    } else {
        $enabled = $null  # unknown
    }

    return [pscustomobject]@{
        Enabled = $enabled
        Available = $true
        FirmwareFlag = $firmware
        HypervisorPresent = $hypervisorPresent
        DockerImpliesOK = $dockerImpliesOK
        WslImpliesOK = $wslImpliesOK
        Method = ($method -join ',')
    }
}

function Build-SystemMap {
    Write-SpiderLog "Building System Map..." 'INFO'
    $map = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Hardware = [pscustomobject]@{
            CPU = (Get-CimInstance Win32_Processor -EA SilentlyContinue | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors)
            RAM_GB = (Get-MemorySnapshot).TotalGB
            Virtualization = Get-VirtualizationStatus
        }
        Windows = [pscustomobject]@{
            Version = [System.Environment]::OSVersion.VersionString
            UptimeHours = Get-UptimeHours
            Admin = Test-IsAdmin
        }
        Network = Get-NetworkStatus
        WSL = Get-WSLStatus
        Docker = Get-DockerInfo
        PiNode = [pscustomobject]@{
            Processes = Get-PiNodeProcesses
            Ports = Test-LocalPiPorts
            Stellar = Get-StellarStatus
        }
        Storage = Get-DiskSnapshot
        DependencyGraph = @(
            'Internet -> WindowsNetwork -> Firewall -> WSL -> Docker -> PiContainer -> Stellar -> Sync'
        )
    }
    Save-Json $map (Join-Path $script:DataDir 'SystemMap.json')
    Write-SpiderLog "System Map saved" 'INFO'
    return $map
}

function Invoke-FullCollect {
    Write-SpiderLog "=== DISCOVERY / COLLECT START ===" 'INFO'
    $cfg = Get-SpiderConfig
    Write-SpiderLog "Collect: memory/cpu/disk..." 'DEBUG'
    $mem = Get-MemorySnapshot
    $cpu = Get-CPUUsage
    $disk = Get-DiskSnapshot
    $topProc = Get-TopMemoryProcesses
    Write-SpiderLog "Collect: docker (timeout 8s)..." 'DEBUG'
    $docker = Get-DockerInfo
    Write-SpiderLog "Collect: wsl..." 'DEBUG'
    $wsl = Get-WSLStatus
    Write-SpiderLog "Collect: network..." 'DEBUG'
    $net = Get-NetworkStatus
    Write-SpiderLog "Collect: pi ports (fast TCP)..." 'DEBUG'
    $ports = Test-LocalPiPorts
    Write-SpiderLog "Collect: stellar..." 'DEBUG'
    $stellar = Get-StellarStatus
    $piProcs = Get-PiNodeProcesses
    $uptime = Get-UptimeHours
    $virt = Get-VirtualizationStatus
    # Consensus: Docker info already includes MonitorLive+ports when Runtime present
    $nodeHealthy = ($docker.PiRunning -eq $true) -and ($docker.EngineHealthy -eq $true)
    # Port listen strong signal (MonitorLive style OPEN on 31401-03)
    if (-not $nodeHealthy -and $docker.EngineHealthy -eq $true -and $ports.AnyOpen) {
        $nodeHealthy = $true
        if (-not $docker.PiRunning) {
            try { $docker | Add-Member -NotePropertyName PiRunning -NotePropertyValue $true -Force } catch {}
        }
        Write-SpiderLog "NodeHealthy inferred: Docker engine + Pi ports listening" 'INFO'
    }
    # Keep $null when sync unknown — do NOT coerce to $false
    if ($null -eq $stellar.Synced) { $stellarSynced = $null }
    else { $stellarSynced = [bool]$stellar.Synced }
    $ml = $null
    try { if ($docker.Runtime -and $docker.Runtime.MonitorLive) { $ml = $docker.Runtime.MonitorLive } } catch {}
    try { if (-not $ml -and (Get-Command Read-MonitorLiveSnapshot -EA SilentlyContinue)) { $ml = Read-MonitorLiveSnapshot } } catch {}

    $snapshot = [pscustomobject]@{
        Timestamp     = (Get-Date).ToString('o')
        Admin         = (Test-IsAdmin)
        UptimeHours   = $uptime
        Virtualization= $virt
        Memory        = $mem
        CPU           = $cpu
        Disk          = $disk
        TopProcesses  = $topProc
        Docker        = $docker
        WSL           = $wsl
        Network       = $net
        Ports         = $ports
        Stellar       = $stellar
        PiProcesses   = $piProcs
        NodeHealthy   = $nodeHealthy
        StellarSynced = $stellarSynced
        MonitorLive   = $ml
        FiveLayer     = $(if ($stellar -and $stellar.PSObject.Properties['FiveLayer']) { $stellar.FiveLayer } elseif ($stellar -and $stellar.PSObject.Properties['Evidence']) { $null } else { $null })
        NodeOverall   = $(if ($stellar -and $stellar.PSObject.Properties['Overall']) { $stellar.Overall } else { $null })
        PiRuntimeEvidence = $(if ($docker.Evidence) { $docker.Evidence } else { @() })
        Mode          = if ($cfg) { $cfg.Mode } else { 'ASSIST' }
    }
    Save-SpiderState $snapshot
    $ctnName = if ($docker.RunningContainer) { $docker.RunningContainer } elseif ($docker.PreferredContainer) { $docker.PreferredContainer } else { '-' }
    Write-SpiderLog ("RAM={0}% CPU={1}% DiskFree={2}GB Docker={3} Pi={4} Ctn={5} Net={6} Conf={7}" -f `
        $mem.UsedPct, $cpu, $disk.FreeGB, $docker.EngineHealthy, $docker.PiRunning, $ctnName, $net.Internet, $(if($docker.Confidence){$docker.Confidence}else{'-'})) 'INFO'
    Write-SpiderLog "=== DISCOVERY END ===" 'INFO'
    return $snapshot
}

function Save-Baseline {
    param($Snapshot)
    $baseline = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        MemoryPct = $Snapshot.Memory.UsedPct
        DiskFreeGB = $Snapshot.Disk.FreeGB
        DockerHealthy = $Snapshot.Docker.EngineHealthy
        PiRunning = $Snapshot.Docker.PiRunning
        NetworkInternet = $Snapshot.Network.Internet
        PortsOpen = $Snapshot.Ports.OpenCount
        Adapter = $Snapshot.Network.Adapter
        IP = $Snapshot.Network.IP
    }
    Save-Json $baseline $script:BaselinePath
    Write-SpiderLog "Baseline saved" 'INFO'
    return $baseline
}

function Compare-Baseline {
    param($Snapshot)
    $base = Load-Json $script:BaselinePath
    if (-not $base) { return $null }
    $diffs = @()
    if ($base.Adapter -and $Snapshot.Network.Adapter -and ($base.Adapter -ne $Snapshot.Network.Adapter)) {
        $diffs += "Adapter: $($base.Adapter) -> $($Snapshot.Network.Adapter)"
    }
    if ($base.IP -and $Snapshot.Network.IP -and ($base.IP -ne $Snapshot.Network.IP)) {
        $diffs += "IP: $($base.IP) -> $($Snapshot.Network.IP)"
    }
    if ($null -ne $base.DockerHealthy -and $base.DockerHealthy -ne $Snapshot.Docker.EngineHealthy) {
        $diffs += "DockerHealthy: $($base.DockerHealthy) -> $($Snapshot.Docker.EngineHealthy)"
    }
    return [pscustomobject]@{ HasDiff = ($diffs.Count -gt 0); Diffs = $diffs }
}
