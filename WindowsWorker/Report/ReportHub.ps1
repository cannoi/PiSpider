# ============================================================
# Report/ReportHub.ps1 - Xuất mọi định dạng sau một scan
# ============================================================

function Invoke-SpiderReportHub {
    param(
        $Report,
        [switch]$Console,
        [switch]$Archive
    )
    if (-not $Report) {
        Write-SpiderLog "ReportHub: no report object" 'WARN'
        return $null
    }

    $paths = [ordered]@{}

    # Full JSON
    if (Get-Command Save-SpiderFullReport -ErrorAction SilentlyContinue) {
        $paths.LastReport = Save-SpiderFullReport -Report $Report
    } else {
        $p = Join-Path $script:DataDir 'last_report.json'
        Save-Json $Report $p
        $paths.LastReport = $p
    }

    # Telegram family
    if (Get-Command Save-TelegramReportText -ErrorAction SilentlyContinue) {
        $paths.Telegram = Save-TelegramReportText -Report $Report
        $paths.Compact  = Join-Path $script:DataDir 'telegram_report_compact.txt'
        $paths.Alert    = Join-Path $script:DataDir 'telegram_report_alert.txt'
        $paths.Bridge   = Join-Path $script:DataDir 'controller_bridge.json'
    }

    if ($Archive -and (Get-Command Export-SpiderReportBundle -ErrorAction SilentlyContinue)) {
        $paths.Archive = Export-SpiderReportBundle -Report $Report
    }

    if ($Console -and (Get-Command Show-SpiderConsoleReport -ErrorAction SilentlyContinue)) {
        Show-SpiderConsoleReport -Report $Report
    }

    Write-SpiderLog ("ReportHub saved: {0}" -f (($paths.Keys | ForEach-Object { $_ }) -join ', ')) 'INFO'
    return [pscustomobject]$paths
}
