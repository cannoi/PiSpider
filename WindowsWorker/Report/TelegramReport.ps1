# ============================================================
# Report/TelegramReport.ps1
# Báo cáo text cho Telegram (Controller đọc file - Spider không gọi Bot API)
# Tôn trọng MaxTelegramChars ~3900
# ============================================================

$script:TelegramMaxChars = 3800

function Format-SpiderTelegramReport {
    param(
        $Report,
        [ValidateSet('full','compact','alert')]
        [string]$Style = 'full'
    )
    if (-not $Report) { return "[SPIDER] Spider: không có báo cáo." }

    switch ($Style) {
        'compact' { return (Format-SpiderTelegramCompact $Report) }
        'alert'   { return (Format-SpiderTelegramAlert $Report) }
        default   { return (Format-SpiderTelegramFull $Report) }
    }
}

function Format-SpiderTelegramFull {
    param($Report)
    $h = $Report.Health
    if (-not $h) { return "[SPIDER] Spider: thiếu Health trong report." }

    $icon = switch ($h.Level) {
        'HEALTHY' {'[OK]'} 'INFO' {'[INFO]'} 'WARNING' {'[WARN]'} 'DEGRADED' {'[DEG]'}
        'CRITICAL' {'[CRIT]'} 'EMERGENCY' {'[EMER]'} default {'[.]'}
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("[SPIDER] PI NODE SPIDER")
    [void]$lines.Add("------------------")
    [void]$lines.Add("")
    [void]$lines.Add("$icon NODE HEALTH: $($h.Overall)/100  [$($h.Level)]")
    [void]$lines.Add("")
    [void]$lines.Add("SYSTEM")
    if ($h.Scores) {
        [void]$lines.Add("* Docker     $($h.Scores.Docker)")
        [void]$lines.Add("* Pi Node    $($h.Scores.PiNode)")
        [void]$lines.Add("* Stellar    $($h.Scores.Stellar)")
        [void]$lines.Add("* Network    $($h.Scores.Network)")
        [void]$lines.Add("* RAM        $($h.Scores.RAM)")
        [void]$lines.Add("* Disk       $($h.Scores.Disk)")
        [void]$lines.Add("* WSL        $($h.Scores.WSL)")
        if ($null -ne $h.Scores.Ports) { [void]$lines.Add("* Ports      $($h.Scores.Ports)") }
    }
    [void]$lines.Add("")

    # Doctor panel summary
    if ($Report.DoctorPanel -and $Report.DoctorPanel.Results) {
        [void]$lines.Add("DOCTORS  (C=$($Report.DoctorPanel.Critical) W=$($Report.DoctorPanel.Warning))")
        $bad = @($Report.DoctorPanel.Results | Where-Object { $_.Status -in @('CRITICAL','WARNING') } | Select-Object -First 6)
        foreach ($d in $bad) {
            $di = switch ($d.Status) { 'CRITICAL' {'[CRIT]'} 'WARNING' {'[WARN]'} default {'[INFO]'} }
            $iss = if ($d.Issues -and $d.Issues.Count) { ($d.Issues | Select-Object -First 2) -join ',' } else { '-' }
            [void]$lines.Add("$di $($d.Doctor): $iss")
        }
        if ($bad.Count -eq 0) { [void]$lines.Add("[OK] All doctors OK") }
        [void]$lines.Add("")
    }

    if ($Report.Findings -and @($Report.Findings).Count -gt 0) {
        [void]$lines.Add("DIAGNOSIS")
        foreach ($f in (@($Report.Findings) | Select-Object -First 3)) {
            [void]$lines.Add("* [$($f.Severity)] $($f.RootCause)")
            [void]$lines.Add("  Conf $($f.Confidence)% | Act: $($f.Action) | Risk: $($f.Risk)")
        }
        [void]$lines.Add("")
    }

    if ($Report.Decision) {
        [void]$lines.Add("DECISION")
        [void]$lines.Add("* Action : $($Report.Decision.Action)")
        [void]$lines.Add("* Risk   : $($Report.Decision.Risk)")
        [void]$lines.Add("* Mode   : $($Report.Decision.Mode)")
        if ($Report.Decision.DependencyNote) {
            [void]$lines.Add("* Dep    : $($Report.Decision.DependencyNote)")
        }
        [void]$lines.Add("")
    }

    if ($Report.Verify) {
        $vr = if ($Report.Verify.Success) { '[OK] RECOVERED / OK' } else { '[CRIT] NEEDS ATTENTION' }
        [void]$lines.Add("RESULT: $vr")
        if ($Report.Verify.Details) {
            foreach ($d in @($Report.Verify.Details | Select-Object -First 5)) {
                [void]$lines.Add("* $d")
            }
        }
        [void]$lines.Add("")
    }

    [void]$lines.Add("Pi Node protected - Minimal intervention")
    $text = $lines -join "`n"
    return (Limit-TelegramText $text)
}

function Format-SpiderTelegramCompact {
    param($Report)
    $h = $Report.Health
    $icon = switch ($h.Level) {
        'HEALTHY' {'[OK]'} 'WARNING' {'[WARN]'} 'CRITICAL' {'[CRIT]'} 'EMERGENCY' {'[EMER]'} default {'[INFO]'}
    }
    $act = if ($Report.Decision) { $Report.Decision.Action } else { 'NONE' }
    $res = if ($Report.Verify) { $Report.Verify.Success } else { 'N/A' }
    $line = "[SPIDER] $icon Health $($h.Overall)/100 [$($h.Level)] | $act | Result=$res"
    if ($Report.Findings -and $Report.Findings.Count -gt 0) {
        $f = $Report.Findings[0]
        $line += "`n* $($f.RootCause) ($($f.Confidence)%)"
    }
    return $line
}

function Format-SpiderTelegramAlert {
    param($Report)
    $h = $Report.Health
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("[ALERT] SPIDER ALERT")
    [void]$lines.Add("Level: $($h.Level) | Score: $($h.Overall)/100")
    if ($Report.Findings) {
        foreach ($f in (@($Report.Findings) | Where-Object { $_.Severity -in @('CRITICAL','EMERGENCY','WARNING') } | Select-Object -First 3)) {
            [void]$lines.Add("* [$($f.Severity)] $($f.RootCause)")
        }
    }
    if ($Report.Decision) {
        [void]$lines.Add("Proposed: $($Report.Decision.Action) (Risk $($Report.Decision.Risk))")
    }
    [void]$lines.Add("Chi tiết: /spiderstatus hoặc Data/telegram_report.txt")
    return ($lines -join "`n")
}

function Limit-TelegramText {
    param([string]$Text, [int]$Max = 0)
    if ($Max -le 0) { $Max = $script:TelegramMaxChars }
    if (-not $Text) { return $Text }
    if ($Text.Length -le $Max) { return $Text }
    return ($Text.Substring(0, $Max - 20) + "`n...(truncated)")
}

function Save-TelegramReportText {
    param(
        $Report,
        [ValidateSet('full','compact','alert','auto')]
        [string]$Style = 'auto'
    )
    if ($Style -eq 'auto') {
        $lv = if ($Report.Health) { $Report.Health.Level } else { 'INFO' }
        $Style = if ($lv -in @('CRITICAL','EMERGENCY')) { 'full' } else { 'full' }
    }

    $text = Format-SpiderTelegramReport -Report $Report -Style $Style
    $path = Join-Path $script:DataDir 'telegram_report.txt'
    Set-Content -Path $path -Value $text -Encoding UTF8

    # Compact + alert side files for Controller flexibility
    $compact = Format-SpiderTelegramReport -Report $Report -Style 'compact'
    Set-Content -Path (Join-Path $script:DataDir 'telegram_report_compact.txt') -Value $compact -Encoding UTF8
    $alert = Format-SpiderTelegramReport -Report $Report -Style 'alert'
    Set-Content -Path (Join-Path $script:DataDir 'telegram_report_alert.txt') -Value $alert -Encoding UTF8

    $ver = if ($script:SpiderVersion) { $script:SpiderVersion } else { '2.1.x' }
    $bridge = [pscustomobject]@{
        Source     = 'PiNodeSpider'
        Version    = $ver
        Timestamp  = (Get-Date).ToString('o')
        Health     = if ($Report.Health) { $Report.Health.Overall } else { $null }
        Level      = if ($Report.Health) { $Report.Health.Level } else { $null }
        Action     = if ($Report.Decision) { $Report.Decision.Action } else { 'NONE' }
        Risk       = if ($Report.Decision) { $Report.Decision.Risk } else { $null }
        Result     = if ($Report.Verify) { $Report.Verify.Success } else { $null }
        DoctorsCritical = if ($Report.DoctorPanel) { $Report.DoctorPanel.Critical } else { $null }
        DoctorsWarning  = if ($Report.DoctorPanel) { $Report.DoctorPanel.Warning } else { $null }
        Text       = $text
        Compact    = $compact
        Alert      = $alert
        Paths      = [pscustomobject]@{
            Full     = $path
            Compact  = (Join-Path $script:DataDir 'telegram_report_compact.txt')
            Alert    = (Join-Path $script:DataDir 'telegram_report_alert.txt')
            LastReport = (Join-Path $script:DataDir 'last_report.json')
        }
    }
    Save-Json $bridge (Join-Path $script:DataDir 'controller_bridge.json')
    return $path
}
