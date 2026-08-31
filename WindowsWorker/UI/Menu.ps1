# ============================================================
# UI/Menu.ps1 - Menu tương tác local (admin console)
# ============================================================

function Show-SpiderMenu {
    $exit = $false
    while (-not $exit) {
        Write-Host ""
        Write-Host "  [SPIDER]  PI NODE SPIDER - MENU" -ForegroundColor Cyan
        Write-Host "  -------------------------"
        Write-Host "  1) Scan"
        Write-Host "  2) Status board"
        Write-Host "  3) Patrol"
        Write-Host "  4) Repair (AUTO-SAFE temp)"
        Write-Host "  5) Recovery soft"
        Write-Host "  6) Map / Dependency"
        Write-Host "  7) History"
        Write-Host "  8) Set mode"
        Write-Host "  0) Exit"
        Write-Host ""
        $c = Read-Host "  Chọn"
        switch ($c) {
            '1' { & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command Scan }
            '2' {
                if (Get-Command Show-SpiderStatusBoard -ErrorAction SilentlyContinue) {
                    Show-SpiderStatusBoard
                } else {
                    & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command Status
                }
            }
            '3' { & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command Patrol }
            '4' { & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command Repair }
            '5' { & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command Recovery -ResetLevel soft }
            '6' { & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command Map }
            '7' { & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command History }
            '8' {
                Write-Host "  Modes: OBSERVE | ASSIST | AUTO-SAFE | AUTO-RECOVERY | EMERGENCY-GUARDIAN"
                $m = Read-Host "  Mode"
                if ($m) {
                    & (Join-Path $script:SpiderRoot 'PiNodeSpider.ps1') -Command SetMode -Mode $m
                }
            }
            '0' { $exit = $true }
            default { Write-Host "  ?" -ForegroundColor Yellow }
        }
    }
}
