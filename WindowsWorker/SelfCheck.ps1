#Requires -Version 5.1
# Self-check structure + load modules (no destructive actions)
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$fail = 0
function Ok($m) { Write-Host "  OK  $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }

Write-Host "[SPIDER] Spider SelfCheck" -ForegroundColor Cyan
$required = @(
    'PiNodeSpider.ps1','Config.json','VERSION',
    'Engine\Core.ps1','Engine\Decision.ps1','Engine\ActionEngine.ps1','Engine\Verify.ps1',
    'Doctors\DoctorHub.ps1','Actions\CleanRAM.ps1','Rules\Rules.json','Rules\Protected.json',
    'Bridge\Spider_For_Controller.ps1','Report\ReportHub.ps1','AI\AI.ps1','UI\Approval.ps1',
    'Scheduler\Install_Startup_Task.ps1'
)
foreach ($r in $required) {
    $p = Join-Path $Root $r
    if (Test-Path $p) { Ok $r } else { Bad "missing $r" }
}
# JSON
foreach ($j in @('Config.json','Rules\Rules.json','Rules\Protected.json','Rules\Recovery.json','AI\AI_Config.json')) {
    $p = Join-Path $Root $j
    try {
        Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        Ok "JSON $j"
    } catch { Bad "JSON $j : $_" }
}
# Dot-source main pieces
try {
    $env:PINODE_CONTROLLER = '1'
    . (Join-Path $Root 'Engine\Core.ps1')
    Ok 'Load Core'
} catch { Bad "Load Core: $_" }

if ($fail -eq 0) {
    Write-Host "`nALL CHECKS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$fail CHECK(S) FAILED" -ForegroundColor Red
    exit 1
}


# Syntax / structure scan (dashboard critical)
$dash = Join-Path $Root 'Dashboard\SpiderDashboard.ps1'
if (Test-Path $dash) {
    $raw = Get-Content $dash -Raw -Encoding UTF8
    if ($raw -match 'function\s+\w+\s*function\s+\w+') {
        Write-Host "[FAIL] SpiderDashboard.ps1 has concatenated function names" -ForegroundColor Red
        $fail++
    } else {
        Write-Host "[OK] SpiderDashboard.ps1 function headers" -ForegroundColor Green
    }
}

