# ============================================================
# UI/SpiderConsole.ps1 - Entry console UI
# Load Approval + StatusBoard + Menu
# ============================================================

$__uiDir = $PSScriptRoot
if (-not $__uiDir) { $__uiDir = Join-Path $script:SpiderRoot 'UI' }
foreach ($m in @('Approval.ps1', 'StatusBoard.ps1', 'Menu.ps1')) {
    $p = Join-Path $__uiDir $m
    if (Test-Path $p) { . $p }
}

function Start-SpiderConsole {
    param(
        [ValidateSet('Menu','Status','Approval')]
        [string]$View = 'Menu'
    )
    switch ($View) {
        'Status' { Show-SpiderStatusBoard }
        'Approval' {
            Write-Host "Approval Console is invoked automatically when Decision.RequiresApproval." -ForegroundColor Gray
            Write-Host "Use Scan in ASSIST mode on an interactive desktop to test." -ForegroundColor Gray
        }
        default { Show-SpiderMenu }
    }
}

Write-SpiderLog "UI Console loaded" 'DEBUG'
