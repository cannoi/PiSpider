# ============================================================
# Report/JsonReport.ps1 - Xuất JSON có cấu trúc cho Controller / archive
# ============================================================

function Save-SpiderFullReport {
    param(
        $Report,
        [string]$Path
    )
    if (-not $Path) {
        $Path = Join-Path $script:DataDir 'last_report.json'
    }
    Save-Json $Report $Path
    return $Path
}

function New-SpiderBridgePayload {
    param($Report)
    $ver = if ($script:SpiderVersion) { $script:SpiderVersion } else { '2.1.x' }
    return [pscustomobject]@{
        Source    = 'PiNodeSpider'
        Version   = $ver
        Timestamp = (Get-Date).ToString('o')
        Health    = if ($Report.Health) { $Report.Health.Overall } else { $null }
        Level     = if ($Report.Health) { $Report.Health.Level } else { $null }
        Action    = if ($Report.Decision) { $Report.Decision.Action } else { 'NONE' }
        Result    = if ($Report.Verify) { $Report.Verify.Success } else { $null }
        FindingId = if ($Report.Decision -and $Report.Decision.Finding) { $Report.Decision.Finding.Id } else { $null }
    }
}

function Export-SpiderReportBundle {
    param($Report)
    $dir = $script:DataDir
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $bundleDir = Join-Path $dir 'Reports'
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
    $path = Join-Path $bundleDir ("report_{0}.json" -f $stamp)
    Save-Json $Report $path
    # Keep last 30 report files
    try {
        Get-ChildItem $bundleDir -Filter 'report_*.json' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 30 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}
    return $path
}
