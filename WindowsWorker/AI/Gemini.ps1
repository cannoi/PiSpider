# ============================================================
# AI/Gemini.ps1 - Optional Gemini HTTP (advisory only)
# Disabled unless API key present. NEVER executes actions.
# ============================================================

function Test-GeminiAvailable {
    $cfg = Get-SpiderAIConfig
    if (-not $cfg) { return $false }
    $key = $env:GEMINI_API_KEY
    if (-not $key -and $cfg.GeminiApiKey) { $key = [string]$cfg.GeminiApiKey }

    # Dashboard stores the Gemini key in DPAPI-protected Notify config.
    # Read it only at runtime; never copy plaintext into AI_Config.json.
    if (-not $key -and (Get-Command Get-SpiderNotifyConfig -ErrorAction SilentlyContinue)) {
        try {
            $n = Get-SpiderNotifyConfig
            if ($n.GeminiKeyProtected -and (Get-Command Unprotect-SpiderSecretString -ErrorAction SilentlyContinue)) {
                $key = Unprotect-SpiderSecretString $n.GeminiKeyProtected
            }
        } catch {}
    }
    return -not [string]::IsNullOrWhiteSpace($key)
}

function Invoke-GeminiAdvisory {
    param(
        [string]$Prompt,
        [string]$SystemGuard
    )
    $cfg = Get-SpiderAIConfig
    if (-not $cfg) {
        return [pscustomobject]@{ Ok = $false; Text = 'No AI config' }
    }

    $key = $env:GEMINI_API_KEY
    if (-not $key) { $key = [string]$cfg.GeminiApiKey }

    # Prefer the DPAPI-protected dashboard key when no environment key is supplied.
    if ([string]::IsNullOrWhiteSpace($key) -and (Get-Command Get-SpiderNotifyConfig -ErrorAction SilentlyContinue)) {
        try {
            $n = Get-SpiderNotifyConfig
            if ($n.GeminiKeyProtected -and (Get-Command Unprotect-SpiderSecretString -ErrorAction SilentlyContinue)) {
                $key = Unprotect-SpiderSecretString $n.GeminiKeyProtected
            }
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($key)) {
        return [pscustomobject]@{ Ok = $false; Text = 'No Gemini API key' }
    }

    $model = 'gemini-3.1-flash-lite-preview'
    if ($cfg.Providers -and $cfg.Providers.Gemini -and $cfg.Providers.Gemini.DefaultModel) {
        $model = [string]$cfg.Providers.Gemini.DefaultModel
    }
    $timeout = 30
    if ($cfg.Providers.Gemini.TimeoutSec) { $timeout = [int]$cfg.Providers.Gemini.TimeoutSec }

    $url = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$key"
    $fullPrompt = "$SystemGuard`n`n$Prompt"

    $bodyObj = @{
        contents = @(
            @{
                role = 'user'
                parts = @(
                    @{ text = $fullPrompt }
                )
            }
        )
        generationConfig = @{
            temperature = 0.2
            maxOutputTokens = 512
        }
    }
    $json = $bodyObj | ConvertTo-Json -Depth 8 -Compress

    try {
        # Use WebRequest for PS 5.1 compatibility
        $resp = Invoke-WebRequest -Uri $url -Method POST -Body $json -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeout -UseBasicParsing -ErrorAction Stop
        $data = $resp.Content | ConvertFrom-Json
        $text = $null
        try {
            $text = $data.candidates[0].content.parts[0].text
        } catch {}
        if (-not $text) {
            return [pscustomobject]@{ Ok = $false; Text = 'Empty Gemini response' }
        }
        return [pscustomobject]@{ Ok = $true; Text = $text; Model = $model }
    } catch {
        Write-SpiderLog "Gemini call failed: $($_.Exception.Message)" 'WARN'
        return [pscustomobject]@{ Ok = $false; Text = $_.Exception.Message }
    }
}
