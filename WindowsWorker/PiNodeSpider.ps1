#Requires -Version 5.1
# ============================================================
# [SPIDER] PiNode Spider v2.2.0 - Autonomous Node Operations & Recovery
# Bộ não vận hành độc lập | Controller PRO = kênh liên lạc duy nhất với user
# Tôn chỉ: Minimal Intervention | Protect | Diagnose | Verify | Autonomous
# ============================================================
[CmdletBinding()]
param(
    [ValidateSet('Scan','Diagnose','Status','Repair','Patrol','History','Recovery','Emergency','SetMode','Map','Watch','Menu','DailyReport','LiveWorker')]
    [string]$Command = 'Scan',

    [ValidateSet('soft','network','docker','wsl','node','hard','all','reboot')]
    [string]$ResetLevel = 'soft',

    [ValidateSet('OBSERVE','ASSIST','AUTO-SAFE','AUTO-RECOVERY','EMERGENCY-GUARDIAN')]
    [string]$Mode,

    [switch]$Force,
    [switch]$Quiet,
    [switch]$FromController
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$SpiderRoot = $PSScriptRoot
if (-not $SpiderRoot) { $SpiderRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

. (Join-Path $SpiderRoot 'Engine\Core.ps1')
. (Join-Path $SpiderRoot 'Engine\Safety.ps1')
if (Test-Path (Join-Path $SpiderRoot 'Engine\NodeStatusReader.ps1')) { . (Join-Path $SpiderRoot 'Engine\NodeStatusReader.ps1') }
if (Test-Path (Join-Path $SpiderRoot 'Engine\Orchestrator.ps1')) { . (Join-Path $SpiderRoot 'Engine\Orchestrator.ps1') }
if (Test-Path (Join-Path $SpiderRoot 'Engine\CarePlan.ps1')) { . (Join-Path $SpiderRoot 'Engine\CarePlan.ps1') }
if (Test-Path (Join-Path $SpiderRoot 'Engine\LiveBus.ps1')) { . (Join-Path $SpiderRoot 'Engine\LiveBus.ps1') }
. (Join-Path $SpiderRoot 'Engine\Telemetry.ps1')
if (Test-Path (Join-Path $SpiderRoot 'Notify\TelegramNotify.ps1')) { . (Join-Path $SpiderRoot 'Notify\TelegramNotify.ps1') }
. (Join-Path $SpiderRoot 'Engine\Discovery.ps1')
. (Join-Path $SpiderRoot 'Engine\Dependency.ps1')
. (Join-Path $SpiderRoot 'Engine\Diagnostic.ps1')
. (Join-Path $SpiderRoot 'Engine\Decision.ps1')
. (Join-Path $SpiderRoot 'Engine\ActionEngine.ps1')
. (Join-Path $SpiderRoot 'Engine\Recovery.ps1')
. (Join-Path $SpiderRoot 'Engine\Verify.ps1')
. (Join-Path $SpiderRoot 'AI\AI.ps1')
. (Join-Path $SpiderRoot 'UI\SpiderConsole.ps1')
. (Join-Path $SpiderRoot 'Report\TelegramReport.ps1')
. (Join-Path $SpiderRoot 'Report\ConsoleReport.ps1')
. (Join-Path $SpiderRoot 'Report\JsonReport.ps1')
. (Join-Path $SpiderRoot 'Report\ReportHub.ps1')
if (Test-Path (Join-Path $SpiderRoot 'Report\DailyDigest.ps1')) { . (Join-Path $SpiderRoot 'Report\DailyDigest.ps1') }
if (Test-Path (Join-Path $SpiderRoot 'Report\StatusPanel.ps1')) { . (Join-Path $SpiderRoot 'Report\StatusPanel.ps1') }

Get-ChildItem (Join-Path $SpiderRoot 'Doctors\*.ps1') -EA SilentlyContinue | ForEach-Object { . $_.FullName }

$script:FromController = $FromController -or ($env:PINODE_CONTROLLER -eq '1')
$script:SpiderVersion = '2.2.1'

function Show-Banner {
    if ($Quiet) { return }
    Write-Host ""
    Write-Host "+==============================================================+" -ForegroundColor Cyan
    Write-Host "|     [SPIDER]  PI NODE SPIDER  v2.2.1 - AUTONOMOUS OPERATIONS      |" -ForegroundColor Cyan
    Write-Host "|     Bảo vệ - Cảnh sát - Bác sĩ - Quản gia - Bộ não          |" -ForegroundColor Green
    Write-Host "|     Minimal Intervention - Protect Node - Verify Always     |" -ForegroundColor Yellow
    Write-Host "+==============================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Show-HealthReport {
    param($Snapshot, $Health, $Findings, $Decision)
    if ($Quiet) { return }
    $icon = switch ($Health.Level) {
        'HEALTHY' {'[OK]'} 'INFO' {'[INFO]'} 'WARNING' {'[WARN]'} 'DEGRADED' {'[DEG]'} 'CRITICAL' {'[CRIT]'} default {'[EMER]'}
    }
    Write-Host "+------------------- NODE HEALTH -------------------+" -ForegroundColor Cyan
    Write-Host ("| Overall       {0} {1}/100  [{2}]" -f $icon, $Health.Overall, $Health.Level) -ForegroundColor White
    Write-Host ("| Docker        {0}" -f $Health.Scores.Docker)
    Write-Host ("| Pi Node       {0}" -f $Health.Scores.PiNode)
    Write-Host ("| Stellar       {0}" -f $Health.Scores.Stellar)
    Write-Host ("| Network       {0}" -f $Health.Scores.Network)
    Write-Host ("| RAM           {0}  ({1}%)" -f $Health.Scores.RAM, $Snapshot.Memory.UsedPct)
    Write-Host ("| Disk          {0}  (Free {1}GB)" -f $Health.Scores.Disk, $Snapshot.Disk.FreeGB)
    Write-Host ("| WSL           {0}" -f $Health.Scores.WSL)
    Write-Host ("| Ports         {0}" -f $Health.Scores.Ports)
    Write-Host "+---------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
    if ($Findings -and $Findings.Count -gt 0) {
        Write-Host "[AI] DIAGNOSIS:" -ForegroundColor Magenta
        foreach ($f in $Findings) {
            $fi = switch ($f.Severity) { 'CRITICAL' {'[CRIT]'} 'WARNING' {'[WARN]'} 'INFO' {'[INFO]'} 'HEALTHY' {'[OK]'} 'DEGRADED' {'[DEG]'} default {'[EMER]'} }
            Write-Host ("  {0} [{1}] {2}" -f $fi, $f.Severity, $f.RootCause)
            Write-Host ("     Confidence: {0}% | Action: {1} | Risk: {2} | Impact: {3}" -f $f.Confidence, $f.Action, $f.Risk, $f.ImpactOnNode) -ForegroundColor Gray
            if ($f.Details) { Write-Host ("     {0}" -f $f.Details) -ForegroundColor DarkGray }
        }
        Write-Host ""
    }
    if ($Decision) {
        Write-Host "📋 DECISION:" -ForegroundColor Cyan
        Write-Host ("   Action      : {0}" -f $Decision.Action)
        Write-Host ("   Reason      : {0}" -f $Decision.Reason)
        Write-Host ("   Mode        : {0}" -f $Decision.Mode)
        Write-Host ("   Risk        : {0}" -f $Decision.Risk)
        Write-Host ("   AutoExecute : {0} | NeedsApproval: {1}" -f $Decision.AutoExecute, $Decision.RequiresApproval)
        Write-Host ""
    }
}

function Invoke-SpiderScan {
    if (Get-Command Assert-SpiderOrchestratorReady -ErrorAction SilentlyContinue) {
        $gate = Assert-SpiderOrchestratorReady -Caller 'Scan'
        if (-not $gate.Ok) {
            Write-SpiderLog "SCAN ABORTED: Orchestrator not ready — $($gate.Reason)" 'ERROR'
            Write-Host "[SPIDER] ERROR: Conductor (Orchestrator) is OFF and could not restart." -ForegroundColor Red
            Write-Host "Open PiSpider.exe / Dashboard and start Auto (conductor), then retry." -ForegroundColor Yellow
            return $null
        }
    }

    Show-Banner
    Write-SpiderLog "=== SPIDER SCAN ===" 'INFO'
    $cfg = Get-SpiderConfig
    if ($Mode) {
        $cfg.Mode = $Mode
        $cfg | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $SpiderRoot 'Config.json') -Encoding UTF8
    }
    # Ensure System Map exists
    if (-not (Test-Path (Join-Path $script:DataDir 'SystemMap.json'))) {
        Build-SystemMap | Out-Null
    }
    $snapshot = Invoke-FullCollect
    if (-not (Test-Path $script:BaselinePath)) { Save-Baseline $snapshot | Out-Null }

    $health = Get-HealthScore $snapshot
    $findings = Invoke-RootCauseAnalysis $snapshot
    $doctorPanel = $null
    if (Get-Command Invoke-AllDoctors -ErrorAction SilentlyContinue) {
        $doctorPanel = Invoke-AllDoctors -Snapshot $snapshot
        if (-not $Quiet -and $doctorPanel) {
            Write-Host (Format-DoctorReport $doctorPanel) -ForegroundColor Cyan
            Write-Host ""
        }
    }
    $decision = Invoke-Decision -Snapshot $snapshot -Findings $findings
    $ai = Invoke-AIAnalysis -Snapshot $snapshot -Findings $findings -Decision $decision -DoctorPanel $doctorPanel

    Show-HealthReport -Snapshot $snapshot -Health $health -Findings $findings -Decision $decision

    $actionResult = $null
    $verifyResult = $null

    if ($decision.Action -notin @('NONE','MONITOR','WAIT_MONITOR','REPORT_CONFIG')) {
        $doIt = $false
        $approval = $null

        if ($Force) {
            $doIt = $true
            Write-SpiderLog "Force execute: $($decision.Action)" 'ACTION'
        }
        elseif ($decision.AutoExecute) {
            $doIt = $true
            Write-SpiderLog "Auto-execute by mode $($decision.Mode): $($decision.Action)" 'ACTION'
        }
        elseif ($decision.RequiresApproval -and -not $script:FromController -and -not $Quiet) {
            # Save for Dashboard approval panel
            if (Get-Command Save-SpiderPendingApproval -ErrorAction SilentlyContinue) {
                Save-SpiderPendingApproval -Decision $decision -Snapshot $snapshot
            }
            # Interactive: UI Approval first, fallback Core console
            if (Get-Command Request-SpiderApprovalIfNeeded -ErrorAction SilentlyContinue) {
                $approval = Request-SpiderApprovalIfNeeded -Decision $decision
                $doIt = [bool]$approval.Approved
                $decision | Add-Member -NotePropertyName Approval -NotePropertyValue $approval -Force
            } else {
                $detail = if ($decision.Finding) { [string]$decision.Finding.Details } else { '' }
                $timeout = 120
                if ($cfg.Failsafe -and $cfg.Failsafe.ApprovalTimeoutSec) { $timeout = [int]$cfg.Failsafe.ApprovalTimeoutSec }
                $doIt = Invoke-ApprovalConsole -Title ([string]$decision.Decision) -RootCause ([string]$decision.Reason) `
                    -Confidence ([double]$decision.Confidence) -Risk ([string]$decision.Risk) `
                    -Action ([string]$decision.Action) -Details $detail -TimeoutSec $timeout
            }
        }
        elseif ($decision.RequiresApproval -and $script:FromController) {
            Write-SpiderLog "Controller mode: action $($decision.Action) needs user confirm via Telegram - not auto-run" 'INFO'
            if (Get-Command Save-SpiderPendingApproval -ErrorAction SilentlyContinue) {
                Save-SpiderPendingApproval -Decision $decision -Snapshot $snapshot
            }
            $doIt = $false
        }
        elseif ($decision.RequiresApproval) {
            # Quiet/dashboard path: only queue pending, do not auto-run
            if (Get-Command Save-SpiderPendingApproval -ErrorAction SilentlyContinue) {
                Save-SpiderPendingApproval -Decision $decision -Snapshot $snapshot
            }
            $doIt = $false
            Write-SpiderLog "Pending approval queued for Dashboard: $($decision.Action)" 'INFO'
        }

        $findId = if ($decision.Finding) { $decision.Finding.Id } else { 'UNKNOWN' }
        $findSev = if ($decision.Finding) { $decision.Finding.Severity } else { 'WARNING' }
        $findDet = if ($decision.Finding) { $decision.Finding.Details } else { '' }

        if ($doIt) {
            if (Get-Command Clear-SpiderPendingApproval -ErrorAction SilentlyContinue) { Clear-SpiderPendingApproval -Result 'APPROVED_RUN' }
            if ($findSev -in @('CRITICAL','EMERGENCY')) { Play-AlertSound -Type 'Critical' }
            $actionResult = Invoke-SpiderAction -ActionName $decision.Action -Snapshot $snapshot `
                -Risk $decision.Risk -Mode $decision.Mode -Force:$Force `
                -UserApproved:($doIt -and ($decision.RequiresApproval -or $Force))
            $verifyResult = Invoke-Verify -BeforeSnapshot $snapshot -ActionResult $actionResult -Decision $decision
            if ($verifyResult -and $verifyResult.StillCritical) {
                Write-SpiderLog "Still CRITICAL after action → ESCALATE" 'WARN'
                Play-AlertSound -Type 'Critical'
            }
            Add-SpiderEvent -Category $findId -Severity $findSev `
                -Symptoms $findDet -RootCause $decision.Reason `
                -Confidence $decision.Confidence -Action $decision.Action `
                -Result $(if ($verifyResult -and $verifyResult.Success) { 'SUCCESS' } else { 'FAILED' }) `
                -DurationSec $(if ($actionResult -and $actionResult.DurationSec) { $actionResult.DurationSec } else { 0 })
        } else {
            Write-SpiderLog "Action deferred/denied: $($decision.Action)" 'WARN'
            Add-SpiderEvent -Category $findId -Severity $findSev `
                -Symptoms $findDet -RootCause $decision.Reason `
                -Confidence $decision.Confidence -Action $decision.Action -Result 'DENIED'
        }
    } else {
        Write-SpiderLog "No repair needed (or MONITOR/WAIT/REPORT)" 'INFO'
    }

    $histEntry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        ProblemId = if ($decision.Finding) { $decision.Finding.Id } else { 'NONE' }
        Severity  = if ($decision.Finding) { $decision.Finding.Severity } else { 'HEALTHY' }
        Action    = $decision.Action
        Confidence= $decision.Confidence
        Result    = if ($verifyResult) { if ($verifyResult.Success) { 'SUCCESS' } else { 'FAILED' } } else { 'NO_ACTION' }
        HealthBefore = $health.Overall
        HealthAfter  = if ($verifyResult) { $verifyResult.HealthAfter.Overall } else { $health.Overall }
        Mode = $cfg.Mode
    }
    Add-SpiderHistory $histEntry

    $report = [pscustomobject]@{
        SpiderVersion = '2.2.0'
        Timestamp = (Get-Date).ToString('o')
        Health = $health
        Findings = $findings
        Decision = $decision
        AI = $ai
        DoctorPanel = $doctorPanel
        ActionResult = $actionResult
        Verify = $verifyResult
        Snapshot = $snapshot
    }
    if (Get-Command Invoke-SpiderReportHub -ErrorAction SilentlyContinue) {
        Invoke-SpiderReportHub -Report $report -Archive | Out-Null
    } else {
        Save-Json $report (Join-Path $script:DataDir 'last_report.json')
        if (Get-Command Save-TelegramReportText -ErrorAction SilentlyContinue) {
            Save-TelegramReportText $report | Out-Null
        }
        if (Get-Command Save-SpiderStatusPanel -ErrorAction SilentlyContinue) {
            Save-SpiderStatusPanel -Report $report | Out-Null
        }
    }

    if ($script:FromController -or $Quiet) {
        Write-Output ("SPIDER|Health={0}|Level={1}|Action={2}|Result={3}" -f `
            $health.Overall, $health.Level, $decision.Action, `
            $(if ($verifyResult) { $verifyResult.Success } else { 'N/A' }))
    }
    Write-SpiderLog "=== SPIDER SCAN END ===" 'INFO'
    try {
        if (Get-Command Write-SpiderConductorBus -EA SilentlyContinue) {
            Write-SpiderConductorBus -Patch @{ LastScanAt = (Get-Date).ToString('o'); ConductorAlive = $true }
        }
        if (Get-Command Sync-SpiderConductorBus -EA SilentlyContinue) { Sync-SpiderConductorBus | Out-Null }
    } catch {}
    return $report
}

function Invoke-SpiderPatrol {
    try {
        if (Get-Command Get-SpiderDataLiveStatus -EA SilentlyContinue) {
            Get-SpiderDataLiveStatus | Out-Null
            Write-SpiderLog 'Patrol: full 5-layer node status (incl. resources/data)' 'PATROL'
        }
    } catch {}

    if (Get-Command Assert-SpiderOrchestratorReady -ErrorAction SilentlyContinue) {
        $gate = Assert-SpiderOrchestratorReady -Caller 'Patrol'
        if (-not $gate.Ok) {
            Write-SpiderLog "PATROL ABORTED: Orchestrator not ready — $($gate.Reason)" 'ERROR'
            Write-Host "[SPIDER] ERROR: Conductor OFF — patrol skipped." -ForegroundColor Red
            return
        }
    }

    Show-Banner
    Write-SpiderLog "=== DAILY PATROL START ===" 'PATROL'
    Build-SystemMap | Out-Null
    $snapshot = Invoke-FullCollect
    $baseCmp = Compare-Baseline $snapshot
    if ($baseCmp -and $baseCmp.HasDiff) {
        Write-SpiderLog "Baseline diffs: $($baseCmp.Diffs -join '; ')" 'PATROL'
    }
    $health = Get-HealthScore $snapshot
    $findings = Invoke-RootCauseAnalysis $snapshot
    Show-HealthReport -Snapshot $snapshot -Health $health -Findings $findings -Decision $null
    # Light maintenance if AUTO modes
    $cfg = Get-SpiderConfig
    if ($cfg.Mode -in @('AUTO-SAFE','AUTO-RECOVERY','EMERGENCY-GUARDIAN')) {
        Invoke-SpiderAction -ActionName 'MAINTENANCE_LIGHT' -Snapshot $snapshot | Out-Null
    }
    Save-Baseline $snapshot | Out-Null
    $patrolReport = [pscustomobject]@{
        SpiderVersion = $script:SpiderVersion
        Timestamp = (Get-Date).ToString('o')
        Type = 'PATROL'
        Health = $health
        Findings = $findings
        Decision = $null
        Baseline = $baseCmp
        Snapshot = $snapshot
    }
    if (Get-Command Invoke-SpiderReportHub -ErrorAction SilentlyContinue) {
        Invoke-SpiderReportHub -Report $patrolReport -Archive | Out-Null
    } else {
        Save-Json $patrolReport (Join-Path $script:DataDir 'last_report.json')
        if (Get-Command Save-TelegramReportText -ErrorAction SilentlyContinue) {
            Save-TelegramReportText $patrolReport | Out-Null
        }
    }
    if ($script:FromController -or $Quiet) {
        Write-Output ("SPIDER|Health={0}|Level={1}|Action=PATROL|Result=True" -f $health.Overall, $health.Level)
    }
    Write-SpiderLog "=== DAILY PATROL END ===" 'PATROL'
    try {
        if (Get-Command Write-SpiderConductorBus -EA SilentlyContinue) {
            Write-SpiderConductorBus -Patch @{ LastPatrolAt = (Get-Date).ToString('o'); ConductorAlive = $true }
        }
        if (Get-Command Sync-SpiderConductorBus -EA SilentlyContinue) { Sync-SpiderConductorBus | Out-Null }
    } catch {}
}

function Invoke-SpiderRepair {
    Write-SpiderLog "=== REPAIR (safe) ===" 'INFO'
    $cfg = Get-SpiderConfig
    $orig = $cfg.Mode
    if ($cfg.Mode -in @('OBSERVE','ASSIST')) { $cfg.Mode = 'AUTO-SAFE' }
    $cfg | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $SpiderRoot 'Config.json') -Encoding UTF8
    $r = Invoke-SpiderScan
    $cfg.Mode = $orig
    $cfg | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $SpiderRoot 'Config.json') -Encoding UTF8
    return $r
}

function Invoke-SpiderRecovery {
    param([string]$Level)
    Write-SpiderLog "=== RECOVERY Level=$Level ===" 'WARN'
    $cfg = Get-SpiderConfig
    $snapshot = Invoke-FullCollect
    $approved = $false
    if ($Level -in @('docker','wsl','node','all') -and $cfg.Mode -ne 'EMERGENCY-GUARDIAN' -and -not $Force) {
        $ok = Invoke-ApprovalConsole -Title "RECOVERY $Level" -RootCause "Manual recovery pipeline" `
            -Confidence 100 -Risk 'HIGH' -Action $Level -Details "Multi-step recovery" -TimeoutSec 120
        if (-not $ok) { Write-SpiderLog "Recovery denied" 'WARN'; return }
        $approved = $true
    } else {
        $approved = $true
    }
    if (Get-Command Invoke-RecoveryPipeline -ErrorAction SilentlyContinue) {
        $pipeline = Invoke-RecoveryPipeline -Level $Level -Snapshot $snapshot -Mode $cfg.Mode -Force:$Force -UserApproved:$approved
        Write-SpiderLog "RECOVERY $Level pipeline Success=$($pipeline.Success)" 'INFO'
        return $pipeline
    }
    # Fallback single-step
    $action = switch ($Level) {
        'soft'    { 'MAINTENANCE_LIGHT' }
        'network' { 'NETWORK_REPAIR' }
        'node'    { 'RESTART_NODE' }
        'docker'  { 'SOFT_DOCKER_RESTART' }
        'wsl'     { 'ORDERED_WSL_RECYCLE' }
        'hard'    { 'RESTART_NODE' }
        'all'     { 'SOFT_DOCKER_RESTART' }
        'reboot'  { 'HOST_REBOOT' }
        default   { 'MAINTENANCE_LIGHT' }
    }
    $result = Invoke-SpiderAction -ActionName $action -Snapshot $snapshot -UserApproved:$approved
    if ($Level -eq 'all' -and $result.Success) {
        Start-Sleep -Seconds 15
        Invoke-SpiderAction -ActionName 'RESTART_NODE' -Snapshot $snapshot -UserApproved:$approved | Out-Null
    }
    $verify = Invoke-Verify -BeforeSnapshot $snapshot -ActionResult $result -Decision ([pscustomobject]@{ Action = $action })
    Write-SpiderLog "RECOVERY $Level done. Success=$($verify.Success)" 'INFO'
    return $verify
}

function Show-Status {
    if (Get-Command Show-SpiderStatusBoard -ErrorAction SilentlyContinue) {
        Show-SpiderStatusBoard
        return
    }
    $snapshot = Load-SpiderState
    if (-not $snapshot) { Write-Host "Chưa có dữ liệu. Chạy Scan trước." -ForegroundColor Yellow; return }
    $health = Get-HealthScore $snapshot
    Show-Banner
    Show-HealthReport -Snapshot $snapshot -Health $health -Findings @() -Decision $null
    Write-Host "Last scan: $($snapshot.Timestamp)" -ForegroundColor Gray
}

function Show-History {
    $h = Load-Json (Join-Path $script:DataDir 'History.json')
    $e = Load-Json (Join-Path $script:DataDir 'Events.json')
    Write-Host "=== HISTORY (recent) ===" -ForegroundColor Cyan
    if ($h) { $h | Select-Object -Last 10 | Format-Table Timestamp, ProblemId, Severity, Action, Result -AutoSize }
    else { Write-Host "No history yet." }
    Write-Host "=== EVENTS (recent) ===" -ForegroundColor Cyan
    if ($e) { $e | Select-Object -Last 10 | Format-Table EventId, Category, Severity, Action, Result -AutoSize }
    else { Write-Host "No events yet." }
}

function Set-SpiderMode {
    param([string]$NewMode)
    $cfg = Get-SpiderConfig
    $cfg.Mode = $NewMode
    $cfg | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $SpiderRoot 'Config.json') -Encoding UTF8
    Write-SpiderLog "Mode → $NewMode" 'INFO'
    Write-Host "Spider Mode = $NewMode" -ForegroundColor Green
}

# ---------- MAIN ----------

function Invoke-SpiderNotifyAfterPatrol {
    try {
        if (Get-Command Send-SpiderPatrolReport -ErrorAction SilentlyContinue) {
            Send-SpiderPatrolReport | Out-Null
        }
    } catch {}
}


function Save-SpiderPendingApproval {
    param($Decision, $Snapshot)
    try {
        $path = Join-Path $script:SpiderRoot 'Data\pending_approval.json'
        $obj = [ordered]@{
            Timestamp = (Get-Date).ToString('o')
            Status    = 'PENDING'
            Action    = $Decision.Action
            Risk      = $Decision.Risk
            Reason    = $Decision.Reason
            Mode      = $Decision.Mode
            Health    = if ($Snapshot -and $Snapshot.PSObject.Properties['NodeHealthy']) { $Snapshot.NodeHealthy } else { $null }
        }
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        ($obj | ConvertTo-Json) | Set-Content -LiteralPath $path -Encoding UTF8
        Write-SpiderLog "Pending approval saved: $($Decision.Action)" 'INFO'
        try {
            if (Get-Command Send-SpiderApprovalNotify -ErrorAction SilentlyContinue) {
                Send-SpiderApprovalNotify -Summary ("Action=$($Decision.Action) Risk=$($Decision.Risk)`n$($Decision.Reason)")
            }
        } catch {}
    } catch {
        Write-SpiderLog "Save pending approval fail: $($_.Exception.Message)" 'WARN'
    }
}

function Clear-SpiderPendingApproval {
    param([string]$Result = 'CLEARED')
    try {
        $path = Join-Path $script:SpiderRoot 'Data\pending_approval.json'
        if (Test-Path $path) {
            $j = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $j | Add-Member -NotePropertyName Status -NotePropertyValue $Result -Force
            $j | Add-Member -NotePropertyName ResolvedAt -NotePropertyValue ((Get-Date).ToString('o')) -Force
            ($j | ConvertTo-Json) | Set-Content $path -Encoding UTF8
        }
    } catch {}
}

switch ($Command) {
    'Scan'       { Invoke-SpiderScan | Out-Null }
    'Diagnose'   { Invoke-SpiderScan | Out-Null }
    'Status'     { Show-Status }
    'Repair'     { Invoke-SpiderRepair | Out-Null }
    'Patrol'     { Invoke-SpiderPatrol }
    'History'    { Show-History }
    'Recovery'   { Invoke-SpiderRecovery -Level $ResetLevel | Out-Null }
    'Emergency'  {
        Set-SpiderMode -NewMode 'EMERGENCY-GUARDIAN'
        Invoke-SpiderScan | Out-Null
    }
    'SetMode'    {
        if ($Mode) { Set-SpiderMode -NewMode $Mode }
        else { Write-Host "Cần -Mode OBSERVE|ASSIST|AUTO-SAFE|AUTO-RECOVERY|EMERGENCY-GUARDIAN" -ForegroundColor Yellow }
    }
    'Map'        { Build-SystemMap | ConvertTo-Json -Depth 6 | Write-Host }
    'Orchestrator' {
        if (Get-Command Start-SpiderOrchestrator -EA SilentlyContinue) { Start-SpiderOrchestrator -Source 'cli' | Out-Null }
        if (Get-Command Invoke-SpiderOrchestratorCycle -EA SilentlyContinue) {
            Invoke-SpiderOrchestratorCycle -Source 'cli' | Out-Null
        } else { Invoke-SpiderScan | Out-Null }
    }
    'Watch'      {
        Write-SpiderLog "WATCH loop - one cycle (schedule externally for continuous)" 'INFO'
        Invoke-SpiderScan | Out-Null
    }
    'DailyReport'{ if (Get-Command Invoke-SpiderDailyDigest -EA SilentlyContinue) { Invoke-SpiderDailyDigest -SendTelegram } else { Write-Host 'DailyDigest module missing' } }
    'LiveWorker' {
        $lw = Join-Path $SpiderRoot 'LiveWorker.ps1'
        if (Test-Path -LiteralPath $lw) { & $lw }
        else { Write-Host 'LiveWorker.ps1 missing' -ForegroundColor Yellow }
    }
    'Menu'       {
        if (Get-Command Start-SpiderConsole -ErrorAction SilentlyContinue) {
            Start-SpiderConsole -View Menu
        } else {
            Write-Host "UI not loaded." -ForegroundColor Yellow
        }
    }
    default      { Invoke-SpiderScan | Out-Null }
}