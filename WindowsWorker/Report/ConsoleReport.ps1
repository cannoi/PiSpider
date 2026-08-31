# ============================================================
# Report/ConsoleReport.ps1 - Báo cáo console đẹp (local / admin)
# ============================================================

function Format-SpiderConsoleReport {
    param($Report)
    if (-not $Report) { return 'No report.' }
    $h = $Report.Health
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('+======================================================+')
    [void]$sb.AppendLine('|           [SPIDER]  PI NODE SPIDER REPORT                  |')
    [void]$sb.AppendLine('+======================================================+')
    if ($h) {
        [void]$sb.AppendLine(("  Health : {0}/100  [{1}]" -f $h.Overall, $h.Level))
        if ($h.Scores) {
            foreach ($name in @('Docker','PiNode','Stellar','Network','RAM','Disk','WSL','Ports')) {
                $v = $h.Scores.$name
                if ($null -ne $v) { [void]$sb.AppendLine(("  {0,-10} {1}" -f $name, $v)) }
            }
        }
    }
    if ($Report.DoctorPanel) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('  Doctors: Critical={0} Warning={1} OK={2}' -f `
            $Report.DoctorPanel.Critical, $Report.DoctorPanel.Warning, $Report.DoctorPanel.OK))
    }
    if ($Report.Decision) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(("  Decision: {0} | Risk={1} | Mode={2}" -f `
            $Report.Decision.Action, $Report.Decision.Risk, $Report.Decision.Mode))
    }
    if ($Report.Verify) {
        [void]$sb.AppendLine(("  Verify  : Success={0}" -f $Report.Verify.Success))
    }
    [void]$sb.AppendLine('')
    return $sb.ToString()
}

function Show-SpiderConsoleReport {
    param($Report)
    $text = Format-SpiderConsoleReport $Report
    $color = 'White'
    if ($Report.Health) {
        $color = switch ($Report.Health.Level) {
            'HEALTHY' {'Green'} 'WARNING' {'Yellow'} 'CRITICAL' {'Red'} 'EMERGENCY' {'Magenta'} default {'Cyan'}
        }
    }
    Write-Host $text -ForegroundColor $color
}
