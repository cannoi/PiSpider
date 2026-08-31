#Requires -Version 5.1
# ============================================================
# Engine/Orchestrator.ps1
# Central conductor: host data -> decide -> act (minimal)
# Tick interval default 60s. Protect Pi Node. No external brain.
# ============================================================

function Get-SpiderOrchestratorConfig {
    $cfg = $null
    try {
        if (Get-Command Get-SpiderConfig -EA SilentlyContinue) { $cfg = Get-SpiderConfig }
    } catch {}
    $interval = 60
    $enabled = $true
    $require = $true
    if ($cfg -and $cfg.Orchestrator) {
        if ($null -ne $cfg.Orchestrator.IntervalSeconds) {
            $interval = [int]$cfg.Orchestrator.IntervalSeconds
        }
        if ($null -ne $cfg.Orchestrator.Enabled) {
            $enabled = [bool]$cfg.Orchestrator.Enabled
        }
        if ($null -ne $cfg.Orchestrator.RequireRunningForScan) {
            $require = [bool]$cfg.Orchestrator.RequireRunningForScan
        }
    }
    if ($interval -lt 30) { $interval = 30 }
    if ($interval -gt 300) { $interval = 300 }
    return [pscustomobject]@{
        Enabled = $enabled
        IntervalSeconds = $interval
        RequireRunningForScan = $require
    }
}

function Get-SpiderOrchestratorStatePath {
    if (-not $script:SpiderRoot) { return $null }
    return (Join-Path $script:SpiderRoot 'Data\orchestrator_state.json')
}

function Get-SpiderOrchestratorState {
    $path = Get-SpiderOrchestratorStatePath
    $st = [ordered]@{
        Running = $false
        LastTick = $null
        LastOk = $null
        LastError = $null
        TickCount = 0
        IntervalSeconds = 60
        Source = 'none'
    }
    if ($path -and (Test-Path -LiteralPath $path)) {
        try {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j.Running) { $st.Running = [bool]$j.Running }
            if ($j.LastTick) { $st.LastTick = [string]$j.LastTick }
            if ($j.LastOk) { $st.LastOk = [string]$j.LastOk }
            if ($j.LastError) { $st.LastError = [string]$j.LastError }
            if ($null -ne $j.TickCount) { $st.TickCount = [int]$j.TickCount }
            if ($null -ne $j.IntervalSeconds) { $st.IntervalSeconds = [int]$j.IntervalSeconds }
            if ($j.Source) { $st.Source = [string]$j.Source }
        } catch {}
    }
    return [pscustomobject]$st
}

function Save-SpiderOrchestratorState {
    param($State)
    $path = Get-SpiderOrchestratorStatePath
    if (-not $path) { return }
    $dir = Split-Path $path -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        ($State | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {}
}

function Set-SpiderOrchestratorRunning {
    param(
        [bool]$Running,
        [string]$Source = 'dashboard'
    )
    $st = Get-SpiderOrchestratorState
    $st | Add-Member Running $Running -Force
    $st | Add-Member Source $Source -Force
    $oc = Get-SpiderOrchestratorConfig
    $st | Add-Member IntervalSeconds $oc.IntervalSeconds -Force
    if ($Running) {
        $st | Add-Member LastOk ((Get-Date).ToString('o')) -Force
        $st | Add-Member LastError $null -Force
    }
    Save-SpiderOrchestratorState $st
    return $st
}

function Test-SpiderOrchestratorAlive {
    param([int]$MaxAgeSeconds = 0)
    $oc = Get-SpiderOrchestratorConfig
    if ($MaxAgeSeconds -le 0) {
        $MaxAgeSeconds = [Math]::Max(180, ($oc.IntervalSeconds * 4))
    }
    $st = Get-SpiderOrchestratorState
    if (-not $st.Running) { return $false }
    # Host process present counts as alive (tick may be in progress)
    try {
        if (Get-Process -Name 'PiSpider' -ErrorAction SilentlyContinue) { return $true }
    } catch {}
    if (-not $st.LastTick) {
        # Just started — allow grace 3 minutes
        try {
            if ($st.LastOk) {
                $t0 = [datetime]::Parse($st.LastOk)
                if (((Get-Date) - $t0).TotalSeconds -le 180) { return $true }
            }
        } catch {}
        return $true  # Running flag set by host — optimistic during first tick
    }
    try {
        $t = [datetime]::Parse($st.LastTick)
        $age = ((Get-Date) - $t).TotalSeconds
        return ($age -le $MaxAgeSeconds)
    } catch {
        return [bool]$st.Running
    }
}

function Assert-SpiderOrchestratorReady {
    <#
    .SYNOPSIS
      Scan/Patrol require the single conductor (PiSpider Orchestrator).
      If offline: mark running, try open PiSpider.exe, wait heartbeat.
      If still down: clear error + how to fix (no silent data path).
    #>
    param([string]$Caller = 'Scan')
    $oc = Get-SpiderOrchestratorConfig
    if (-not $oc.RequireRunningForScan) {
        Sync-SpiderConductorBus | Out-Null
        return [pscustomobject]@{ Ok = $true; Reason = 'require_disabled' }
    }

    if (Test-SpiderOrchestratorAlive) {
        Sync-SpiderConductorBus | Out-Null
        return [pscustomobject]@{ Ok = $true; Reason = 'alive' }
    }

    # 1) Local auto-mark (same session / scheduler tick)
    try {
        Set-SpiderOrchestratorRunning -Running $true -Source "auto-recover:$Caller" | Out-Null
    } catch {}

    # After mark — always allow this process to act as worker (CLI/Schedule/Dashboard child)
    Sync-SpiderConductorBus | Out-Null
    return [pscustomobject]@{ Ok = $true; Reason = 'auto_marked_worker' }
    if ($false -and (Test-SpiderOrchestratorAlive -MaxAgeSeconds 300)) {
        Sync-SpiderConductorBus | Out-Null
        return [pscustomobject]@{ Ok = $true; Reason = 'auto_marked_worker' }
    }

    # 2) If PiSpider/host already running — do NOT launch another EXE (causes freeze/mutex storm)
    $uiUp = $false
    try {
        if (Get-Process -Name 'PiSpider' -ErrorAction SilentlyContinue) { $uiUp = $true }
    } catch {}
    if ($uiUp -or $env:PINODE_SPIDER_HOST -eq '1') {
        Set-SpiderOrchestratorRunning -Running $true -Source "host-present:$Caller" | Out-Null
        Sync-SpiderConductorBus | Out-Null
        return [pscustomobject]@{ Ok = $true; Reason = 'host_process_present' }
    }

    # 3) Wake UI only for pure CLI/Scheduler (no host)
    $wake = Start-PiSpiderConductorUi
    if ($wake.Ok) {
        Write-SpiderLog "Waiting for Conductor heartbeat after wake ($($wake.Method))..." 'INFO'
        if (Wait-SpiderOrchestratorHeartbeat -TimeoutSec 25) {
            Sync-SpiderConductorBus | Out-Null
            return [pscustomobject]@{ Ok = $true; Reason = "woke_$($wake.Method)" }
        }
    }

    # 3) Still down — block with clear guidance
    $exe = Find-PiSpiderExe
    $help = @"
[SPIDER] CONDUCTOR OFF — $Caller blocked

PiSpider.exe is the only central coordinator.
It was not running and could not be started automatically.

What to do:
  1) Open PiSpider.exe (or Launch_Dashboard.bat)
  2) Confirm label: Conductor: ON (~60s)
  3) Use RUN in PiSpider to start the in-app worker.
  4) Retry $Caller

Paths checked:
  EXE: $(if ($exe) { $exe } else { 'NOT FOUND — build/copy PiSpider.exe to Spider root' })
  Root: $script:SpiderRoot

Wake result: $(if ($wake) { $wake.Method } else { 'n/a' }) $(if ($wake -and $wake.Error) { $wake.Error } else { '' })
"@
    Write-SpiderLog ($help -replace "`r?`n", ' | ') 'ERROR'
    Write-Host $help -ForegroundColor Red
    Write-SpiderConductorBus -Patch @{
        ConductorAlive = $false
        LastError = "Conductor OFF — $Caller blocked"
        Message = 'Open PiSpider.exe to start Conductor'
    }
    return [pscustomobject]@{ Ok = $false; Reason = 'conductor_offline'; Help = $help }
}


function Invoke-SpiderOrchestratorCycle {
    <#
    .SYNOPSIS
      One conductor tick: collect host/node data -> diagnose -> decide -> optional act.
    #>
    param(
        [switch]$Force,
        [string]$Source = 'orchestrator'
    )
    $oc = Get-SpiderOrchestratorConfig
    if (-not $oc.Enabled -and -not $Force) {
        return [pscustomobject]@{ Ok = $false; Skipped = $true; Reason = 'disabled' }
    }

    $st = Get-SpiderOrchestratorState
    $st | Add-Member Running $true -Force
    $st | Add-Member Source $Source -Force
    $st | Add-Member IntervalSeconds $oc.IntervalSeconds -Force
    $st | Add-Member LastTick ((Get-Date).ToString('o')) -Force

    try {
        # Full scan pipeline (Quiet if available via script flags)
        $prevQuiet = $false
        try {
            if (Get-Variable -Name Quiet -Scope Script -EA SilentlyContinue) {
                $prevQuiet = [bool]$script:Quiet
            }
        } catch {}
        $script:Quiet = $true
        $script:FromController = $true

        $report = $null
        if (Get-Command Invoke-SpiderScan -ErrorAction SilentlyContinue) {
            $report = Invoke-SpiderScan
        } else {
            # Dashboard host may only load Engine/* — run main script as worker
            $main = Join-Path $script:SpiderRoot 'PiNodeSpider.ps1'
            if (-not (Test-Path -LiteralPath $main)) {
                throw "Invoke-SpiderScan missing and PiNodeSpider.ps1 not found at $main"
            }
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$main`" -Command Scan -Quiet"
            $psi.WorkingDirectory = $script:SpiderRoot
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            [void]$proc.Start()
            if (-not $proc.WaitForExit(600000)) {
                try { $proc.Kill() } catch {}
                throw 'Orchestrator worker Scan timed out (10 min)'
            }
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            if ($proc.ExitCode -ne 0 -and $stderr) {
                Write-SpiderLog "Orchestrator worker stderr: $($stderr.Substring(0, [Math]::Min(500, $stderr.Length)))" 'WARN'
            }
            # Load last_report as report object
            $lr = Join-Path $script:SpiderRoot 'Data\last_report.json'
            if (Test-Path -LiteralPath $lr) {
                try { $report = Get-Content -LiteralPath $lr -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
            }
            if (-not $report) {
                $report = [pscustomobject]@{ Health = [pscustomobject]@{ Overall = $null }; WorkerExit = $proc.ExitCode; StdOut = $stdout }
            }
        }

        $script:Quiet = $prevQuiet
        $st | Add-Member LastOk ((Get-Date).ToString('o')) -Force
        $st | Add-Member LastError $null -Force
        $st | Add-Member TickCount ([int]$st.TickCount + 1) -Force
        Save-SpiderOrchestratorState $st

        $health = $null
        if ($report -and $report.Health) { $health = $report.Health.Overall }
        Write-SpiderLog "Orchestrator tick OK Health=$health Source=$Source" 'INFO'
        try {
            $patch = @{ ConductorAlive = $true; LastTick = (Get-Date).ToString('o'); Message = "tick OK Health=$health" }
            if ($Source -match 'scan|Scan|dashboard|cli|orchestrator') { $patch['LastScanAt'] = (Get-Date).ToString('o') }
            Write-SpiderConductorBus -Patch $patch
        } catch {}
        return [pscustomobject]@{
            Ok = $true
            Skipped = $false
            Health = $health
            TickCount = $st.TickCount
            Report = $report
        }
    } catch {
        $err = $_.Exception.Message
        $st | Add-Member LastError $err -Force
        Save-SpiderOrchestratorState $st
        Write-SpiderLog "Orchestrator tick FAIL: $err" 'ERROR'
        return [pscustomobject]@{ Ok = $false; Skipped = $false; Reason = $err }
    }
}

function Start-SpiderOrchestrator {
    param([string]$Source = 'manual')
    $oc = Get-SpiderOrchestratorConfig
    Set-SpiderOrchestratorRunning -Running $true -Source $Source | Out-Null
    Write-SpiderLog "Orchestrator START source=$Source interval=$($oc.IntervalSeconds)s" 'INFO'
    return Get-SpiderOrchestratorState
}

function Stop-SpiderOrchestrator {
    param([string]$Source = 'manual')
    $st = Set-SpiderOrchestratorRunning -Running $false -Source $Source
    Write-SpiderLog "Orchestrator STOP source=$Source" 'INFO'
    return $st
}



# ---------- Conductor bus (file IPC — apps stay in sync) ----------

function Get-SpiderConductorBusPath {
    if (-not $script:SpiderRoot) { return $null }
    return (Join-Path $script:SpiderRoot 'Data\conductor_bus.json')
}

function Read-SpiderConductorBus {
    $path = Get-SpiderConductorBusPath
    $bus = [ordered]@{
        Version = 1
        UpdatedAt = $null
        ConductorAlive = $false
        ConductorSource = $null
        LastTick = $null
        LastScanAt = $null
        LastPatrolAt = $null
        LastDigestAt = $null
        Scheduler = $null
        LastWakeAttempt = $null
        LastError = $null
        Message = $null
    }
    if ($path -and (Test-Path -LiteralPath $path)) {
        try {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($bus.Keys)) {
                if ($j.PSObject.Properties[$k]) { $bus[$k] = $j.$k }
            }
        } catch {}
    }
    return [pscustomobject]$bus
}

function Write-SpiderConductorBus {
    param([hashtable]$Patch)
    $bus = Read-SpiderConductorBus
    $ht = [ordered]@{}
    foreach ($p in $bus.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    if ($Patch) {
        foreach ($k in $Patch.Keys) { $ht[$k] = $Patch[$k] }
    }
    $ht['UpdatedAt'] = (Get-Date).ToString('o')
    $path = Get-SpiderConductorBusPath
    if (-not $path) { return }
    $dir = Split-Path $path -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        ([pscustomobject]$ht | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {}
}

function Get-SpiderSchedulerSnapshot {
    $names = @('PiNodeSpider_Startup')
    $items = @()
    foreach ($n in $names) {
        $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
        if (-not $t) {
            $items += [pscustomobject]@{ Name = $n; Installed = $false; State = 'NOT_INSTALLED' }
            continue
        }
        $info = Get-ScheduledTaskInfo -TaskName $n -ErrorAction SilentlyContinue
        $items += [pscustomobject]@{
            Name = $n
            Installed = $true
            State = [string]$t.State
            LastRun = if ($info) { [string]$info.LastRunTime } else { $null }
            NextRun = if ($info) { [string]$info.NextRunTime } else { $null }
            LastResult = if ($info) { [string]$info.LastTaskResult } else { $null }
        }
    }
    return $items
}

function Sync-SpiderConductorBus {
    $alive = $false
    if (Get-Command Test-SpiderOrchestratorAlive -EA SilentlyContinue) {
        $alive = [bool](Test-SpiderOrchestratorAlive)
    }
    $st = $null
    if (Get-Command Get-SpiderOrchestratorState -EA SilentlyContinue) {
        $st = Get-SpiderOrchestratorState
    }
    $sched = Get-SpiderSchedulerSnapshot
    Write-SpiderConductorBus -Patch @{
        ConductorAlive = $alive
        ConductorSource = $(if ($st) { $st.Source } else { $null })
        LastTick = $(if ($st) { $st.LastTick } else { $null })
        Scheduler = $sched
        Message = $(if ($alive) { 'Conductor OK' } else { 'Conductor offline' })
    }
    return (Read-SpiderConductorBus)
}

function Find-PiSpiderExe {
    $root = $script:SpiderRoot
    if (-not $root) { return $null }
    $candidates = @(
        (Join-Path $root 'PiSpider.exe'),
        (Join-Path $root 'Dashboard\PiSpider.exe'),
        (Join-Path $root 'bin\PiSpider.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Find-PiSpiderDashboardEntry {
    $root = $script:SpiderRoot
    if (-not $root) { return $null }
    $bat = Join-Path $root 'Launch_Dashboard.bat'
    if (Test-Path -LiteralPath $bat) { return $bat }
    $ps1 = Join-Path $root 'Dashboard\SpiderDashboard.ps1'
    if (Test-Path -LiteralPath $ps1) { return $ps1 }
    return $null
}

function Test-PiSpiderUiProcess {
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match '(?i)^(PiSpider|powershell)$'
        }
        # Prefer PiSpider.exe
        foreach ($p in Get-Process -Name 'PiSpider' -ErrorAction SilentlyContinue) {
            return $true
        }
    } catch {}
    # Heartbeat file is authoritative when EXE hosts orchestrator
    return (Test-SpiderOrchestratorAlive -MaxAgeSeconds 180)
}

function Start-PiSpiderConductorUi {
    <#
    .SYNOPSIS
      Try open PiSpider.exe (or Dashboard) so the single conductor is online.
    #>
    $exe = Find-PiSpiderExe
    $entry = Find-PiSpiderDashboardEntry
    Write-SpiderConductorBus -Patch @{ LastWakeAttempt = (Get-Date).ToString('o') }

    if ($exe) {
        try {
            Start-Process -FilePath $exe -WorkingDirectory $script:SpiderRoot -WindowStyle Normal | Out-Null
            Write-SpiderLog "Wake Conductor UI via PiSpider.exe: $exe" 'INFO'
            return [pscustomobject]@{ Ok = $true; Method = 'exe'; Path = $exe }
        } catch {
            Write-SpiderLog "PiSpider.exe start failed: $($_.Exception.Message)" 'WARN'
        }
    }
    if ($entry -and $entry.EndsWith('.bat')) {
        try {
            Start-Process -FilePath $entry -WorkingDirectory $script:SpiderRoot -WindowStyle Normal | Out-Null
            Write-SpiderLog "Wake Conductor UI via bat: $entry" 'INFO'
            return [pscustomobject]@{ Ok = $true; Method = 'bat'; Path = $entry }
        } catch {
            Write-SpiderLog "Launch bat failed: $($_.Exception.Message)" 'WARN'
        }
    }
    if ($entry -and $entry.EndsWith('.ps1')) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$entry`""
            $psi.WorkingDirectory = $script:SpiderRoot
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            Write-SpiderLog "Wake Conductor UI via Dashboard.ps1" 'INFO'
            return [pscustomobject]@{ Ok = $true; Method = 'ps1'; Path = $entry }
        } catch {
            Write-SpiderLog "Dashboard.ps1 start failed: $($_.Exception.Message)" 'WARN'
        }
    }
    return [pscustomobject]@{
        Ok = $false
        Method = 'none'
        Path = $null
        Error = 'PiSpider.exe / Launch_Dashboard.bat not found under Spider root'
    }
}

function Wait-SpiderOrchestratorHeartbeat {
    param([int]$TimeoutSec = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-SpiderOrchestratorAlive -MaxAgeSeconds 120) { return $true }
        Start-Sleep -Seconds 2
    }
    return (Test-SpiderOrchestratorAlive -MaxAgeSeconds 120)
}



# ---------- Run mode vs Scheduler (avoid duplicate) ----------

function Get-SpiderTaskNames {
    return @('PiNodeSpider_Startup')
}

function Get-SpiderActiveScheduleSummary {
    $items = @()
    $any = $false
    foreach ($n in (Get-SpiderTaskNames)) {
        $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
        if (-not $t) { continue }
        $st = [string]$t.State
        $enabled = ($st -ne 'Disabled')
        if ($enabled) { $any = $true }
        $items += [pscustomobject]@{ Name = $n; State = $st; Enabled = $enabled }
    }
    return [pscustomobject]@{ AnyEnabled = $any; Tasks = $items; Count = $items.Count }
}

function Disable-SpiderScheduledTasks {
    param([string[]]$Names = $null)
    if (-not $Names) { $Names = Get-SpiderTaskNames }
    $done = @()
    foreach ($n in $Names) {
        try {
            $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
            if (-not $t) { continue }
            Disable-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue | Out-Null
            $done += $n
            Write-SpiderLog "Scheduled task DISABLED: $n" 'INFO'
        } catch {
            Write-SpiderLog "Disable task $n : $($_.Exception.Message)" 'WARN'
        }
    }
    return $done
}

function Enable-SpiderScheduledTasks {
    param([string[]]$Names = $null)
    if (-not $Names) { $Names = Get-SpiderTaskNames }
    $done = @()
    foreach ($n in $Names) {
        try {
            $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
            if (-not $t) { continue }
            Enable-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue | Out-Null
            $done += $n
            Write-SpiderLog "Scheduled task ENABLED: $n" 'INFO'
        } catch {
            Write-SpiderLog "Enable task $n : $($_.Exception.Message)" 'WARN'
        }
    }
    return $done
}

function Get-SpiderDuplicateProcesses {
    $self = $PID
    $list = New-Object System.Collections.Generic.List[object]
    try {
        Get-Process -Name 'PiSpider' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Id -ne $self) {
                $list.Add([pscustomobject]@{ Id = $_.Id; Name = $_.ProcessName; Kind = 'exe' })
            }
        }
    } catch {}
    try {
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessId -ne $self -and
                $_.CommandLine -and
                ($_.CommandLine -match 'PiSpiderHost\.ps1|SpiderDashboard\.ps1|PiNodeSpider\.ps1')
            } |
            ForEach-Object {
                $list.Add([pscustomobject]@{ Id = $_.ProcessId; Name = $_.Name; Kind = 'ps1'; Cmd = $_.CommandLine })
            }
    } catch {}
    return @($list)
}

function Stop-SpiderDuplicateProcesses {
    param([switch]$IncludeScanWorkers)
    $killed = @()
    $dups = Get-SpiderDuplicateProcesses
    foreach ($d in $dups) {
        # Keep other Scan -Quiet workers unless requested (they are short-lived)
        if (-not $IncludeScanWorkers -and $d.Cmd -and $d.Cmd -match '-Command\s+Scan') { continue }
        if (-not $IncludeScanWorkers -and $d.Kind -eq 'ps1' -and $d.Cmd -match 'PiNodeSpider\.ps1') {
            # only kill host/dashboard duplicates
            if ($d.Cmd -notmatch 'PiSpiderHost|SpiderDashboard') { continue }
        }
        try {
            Stop-Process -Id $d.Id -Force -ErrorAction Stop
            $killed += $d.Id
            Write-SpiderLog "Killed duplicate process PID=$($d.Id) $($d.Name)" 'WARN'
        } catch {
            Write-SpiderLog "Could not kill PID=$($d.Id): $($_.Exception.Message)" 'WARN'
        }
    }
    return $killed
}

function Resolve-SpiderStartupRunMode {
    <#
    .SYNOPSIS
      The only supported Windows task is PiNodeSpider_Startup (AtLogOn). It does not own Watch/Patrol loops.
      Returns mode suggestion + schedule summary.
    #>
    $sum = Get-SpiderActiveScheduleSummary
    $mode = 'manual'
    try {
        if (Get-Command Get-SpiderRuntimeMode -EA SilentlyContinue) {
            $mode = Get-SpiderRuntimeMode
        }
    } catch {}
    $suggest = $mode
    if ($sum.AnyEnabled) {
        # Tasks own the loops — avoid double Scan from UI timer
        $suggest = 'scheduler'
    }
    return [pscustomobject]@{
        CurrentMode = $mode
        SuggestedMode = $suggest
        Schedule = $sum
        AvoidUiScan = [bool]$sum.AnyEnabled
    }
}
