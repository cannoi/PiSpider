# ============================================================
# AI/AI.ps1 - AI Brain orchestrator
# Pipeline: Local analysis always → optional Gemini enrich
# AI NEVER bypasses Safety / ActionEngine / Mode policy
# ============================================================

# Dot-source siblings when AI.ps1 is loaded from main
$__aiDir = $PSScriptRoot
if (-not $__aiDir) { $__aiDir = Join-Path $script:SpiderRoot 'AI' }
foreach ($m in @('Knowledge.ps1', 'Prompt.ps1', 'Analysis.ps1', 'Gemini.ps1')) {
    $mp = Join-Path $__aiDir $m
    if (Test-Path $mp) { . $mp }
}

function Invoke-AIAnalysis {
    param(
        $Snapshot,
        $Findings,
        $Decision,
        $DoctorPanel = $null
    )

    $cfg = Get-SpiderAIConfig
    if ($cfg -and $cfg.Enabled -eq $false) {
        return [pscustomobject]@{
            Enabled         = $false
            Provider        = 'Off'
            Explanation     = 'AI disabled in AI_Config.json. Rule engine decision stands.'
            Recommendation  = if ($Decision) { $Decision.Action } else { 'NONE' }
            ConfidenceBoost = 0
            AdvisoryOnly    = $true
            SafetyBypass    = $false
        }
    }

    # 1) Local (always)
    $local = Invoke-LocalAIAnalysis -Snapshot $Snapshot -Findings $Findings -Decision $Decision -DoctorPanel $DoctorPanel

    $provider = 'Local'
    $explanation = $local.Explanation
    $boost = 0
    $remote = $null

    # 2) Optional Gemini if configured
    $wantGemini = $false
    if ($cfg -and $cfg.Provider -eq 'Gemini') { $wantGemini = $true }
    if ($env:SPIDER_AI_PROVIDER -eq 'Gemini') { $wantGemini = $true }

    if ($wantGemini -and (Get-Command Test-GeminiAvailable -ErrorAction SilentlyContinue) -and (Test-GeminiAvailable)) {
        $lang = if ($cfg.Language) { $cfg.Language } else { 'vi' }
        $prompt = Build-SpiderAIPrompt -Snapshot $Snapshot -Findings $Findings -Decision $Decision -DoctorPanel $DoctorPanel -Language $lang
        $guard = Build-SpiderAISystemGuard
        $remote = Invoke-GeminiAdvisory -Prompt $prompt -SystemGuard $guard
        if ($remote.Ok) {
            $provider = 'Gemini+Local'
            $explanation = [string]$remote.Text
            # Small boost only; rule engine remains source of truth for Action
            $maxBoost = 5
            if ($cfg.Policy -and $cfg.Policy.MaxConfidenceBoost) { $maxBoost = [int]$cfg.Policy.MaxConfidenceBoost }
            $boost = [math]::Min(3, $maxBoost)
            Write-SpiderLog "AI Gemini advisory received ($($remote.Model))" 'INFO'
        } else {
            Write-SpiderLog "AI Gemini unavailable, using Local: $($remote.Text)" 'DEBUG'
            $provider = 'Local'
        }
    }

    $rec = if ($Decision) { $Decision.Action } else { 'NONE' }
    # CRITICAL: recommendation follows Decision, not free-form AI action inventing
    return [pscustomobject]@{
        Enabled         = $true
        Provider        = $provider
        Explanation     = $explanation
        LocalExplanation = $local.Explanation
        Recommendation  = $rec
        ConfidenceBoost = $boost
        AdvisoryOnly    = $true
        SafetyBypass    = $false
        RemoteOk        = if ($remote) { [bool]$remote.Ok } else { $false }
    }
}

Write-SpiderLog "AI Brain loaded (advisory only)" 'DEBUG'
