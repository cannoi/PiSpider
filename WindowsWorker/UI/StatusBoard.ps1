# ============================================================
# UI/StatusBoard.ps1 - Bảng trạng thái console
# ============================================================

function Show-SpiderStatusBoard {
    param($Report)

    if (-not $Report) {
        $path = Join-Path $script:DataDir 'last_report.json'
        if (Test-Path $path) {
            try { $Report = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
        }
    }
    if (-not $Report) {
        Write-Host "[SPIDER] Chưa có báo cáo. Chạy: .\PiNodeSpider.ps1 -Command Scan" -ForegroundColor Yellow
        return
    }

    $h = $Report.Health
    $levelColor = switch ($h.Level) {
        'HEALTHY' {'Green'} 'INFO' {'Cyan'} 'WARNING' {'Yellow'}
        'DEGRADED' {'DarkYellow'} 'CRITICAL' {'Red'} 'EMERGENCY' {'Magenta'} default {'White'}
    }
    $icon = switch ($h.Level) {
        'HEALTHY' {'[OK]'} 'WARNING' {'[WARN]'} 'CRITICAL' {'[CRIT]'} 'EMERGENCY' {'[EMER]'} default {'[INFO]'}
    }

    Clear-Host
    Write-Host ""
    Write-Host "  +====================================================+" -ForegroundColor Cyan
    Write-Host "  |            [SPIDER]  PI NODE SPIDER STATUS               |" -ForegroundColor Cyan
    Write-Host "  +====================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $icon  HEALTH  $($h.Overall)/100   [$($h.Level)]" -ForegroundColor $levelColor
    Write-Host ""
    Write-Host "  +------------+--------+" -ForegroundColor DarkGray
    if ($h.Scores) {
        foreach ($name in @('Docker','PiNode','Stellar','Network','RAM','Disk','WSL','Ports')) {
            $v = $h.Scores.$name
            if ($null -eq $v) { continue }
            $c = if ($v -ge 85) {'Green'} elseif ($v -ge 60) {'Yellow'} else {'Red'}
            Write-Host ("  | {0,-10} | " -f $name) -NoNewline -ForegroundColor DarkGray
            Write-Host ("{0,3} " -f $v) -NoNewline -ForegroundColor $c
            Write-Host "   |" -ForegroundColor DarkGray
        }
    }
    Write-Host "  +------------+--------+" -ForegroundColor DarkGray

    if ($Report.Decision) {
        Write-Host ""
        Write-Host "  Decision : $($Report.Decision.Action)  (Risk $($Report.Decision.Risk))" -ForegroundColor White
        Write-Host "  Mode     : $($Report.Decision.Mode)" -ForegroundColor Gray
    }
    if ($Report.AI -and $Report.AI.Explanation) {
        Write-Host ""
        Write-Host "  AI: $($Report.AI.Explanation)" -ForegroundColor DarkCyan
    }
    if ($Report.Verify) {
        $vs = if ($Report.Verify.Success) { 'OK' } else { 'ATTENTION' }
        Write-Host "  Verify   : $vs" -ForegroundColor $(if ($Report.Verify.Success) {'Green'} else {'Red'})
    }
    Write-Host ""
    Write-Host "  Minimal intervention - Pi Node protected" -ForegroundColor DarkGray
    Write-Host ""
}
