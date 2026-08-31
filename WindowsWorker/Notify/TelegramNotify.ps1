#Requires -Version 5.1
# ============================================================
# Notify/TelegramNotify.ps1 - ONE-WAY Telegram (Spider -> user)
# Secrets: DPAPI CurrentUser. Never log plaintext tokens/keys.
# ============================================================

function script:Get-SpiderSecretsPath {
    $root = $script:SpiderRoot
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $env:PINODE_SPIDER_ROOT }
    if ([string]::IsNullOrWhiteSpace($root) -and $PSScriptRoot) {
        $root = Split-Path -Parent $PSScriptRoot
    }
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'SpiderRoot is empty - cannot resolve secrets path'
    }
    $dir = Join-Path $root 'Data'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return (Join-Path $dir 'secrets.protected.json')
}

function script:Protect-SpiderSecretString {
    param([AllowNull()][string]$Plain)
    if ([string]::IsNullOrEmpty($Plain)) { return '' }
    # Normalize: trim only outer whitespace, never cut middle
    $Plain = $Plain.Trim()
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plain)
        $prot = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Convert]::ToBase64String($prot)
    } catch {
        # Fallback marked - still full length
        $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Plain))
        return 'b64:' + $b64
    }
}

function script:Unprotect-SpiderSecretString {
    param([AllowNull()][string]$Protected)
    if ([string]::IsNullOrEmpty($Protected)) { return '' }
    try {
        if ($Protected.StartsWith('b64:')) {
            return [System.Text.Encoding]::UTF8.GetString(
                [Convert]::FromBase64String($Protected.Substring(4)))
        }
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $bytes = [Convert]::FromBase64String($Protected)
        $raw = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($raw)
    } catch {
        return ''
    }
}

function script:Get-SpiderNotifyConfig {
    $path = Get-SpiderSecretsPath
    $cfg = [ordered]@{
        TelegramEnabled         = $false
        BotTokenProtected       = ''
        ChatId                  = ''
        NotifyOnPatrol          = $true  # reused as DailyDigest enabled
        NotifyOnApprovalNeed    = $true
        NotifyOnCritical        = $true
        GeminiKeyProtected      = ''
        SchemaVersion           = 2
    }
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            $j = $raw | ConvertFrom-Json
            foreach ($k in @($cfg.Keys)) {
                if ($null -ne $j.PSObject.Properties[$k]) {
                    $cfg[$k] = $j.$k
                }
            }
        } catch {}
    }
    return [pscustomobject]$cfg
}

function script:Set-SpiderSecretsAcl {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        # Remove inheritance; only current user Read+Write
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        icacls.exe $Path /inheritance:r 2>$null | Out-Null
        icacls.exe $Path /grant:r "${user}:(R,W)" 2>$null | Out-Null
    } catch {}
}

function script:Save-SpiderNotifyConfig {
    param($Config)
    $path = Get-SpiderSecretsPath
    # Preserve existing protected blobs if caller passed empty (keep previous)
    $prev = Get-SpiderNotifyConfig
    $tokProt = [string]$Config.BotTokenProtected
    $gemProt = [string]$Config.GeminiKeyProtected
    if ([string]::IsNullOrWhiteSpace($tokProt) -and $prev.BotTokenProtected) {
        $tokProt = [string]$prev.BotTokenProtected
    }
    if ([string]::IsNullOrWhiteSpace($gemProt) -and $prev.GeminiKeyProtected) {
        $gemProt = [string]$prev.GeminiKeyProtected
    }

    $obj = [ordered]@{
        SchemaVersion           = 2
        TelegramEnabled         = [bool]$Config.TelegramEnabled
        BotTokenProtected       = $tokProt
        ChatId                  = ([string]$Config.ChatId).Trim()
        NotifyOnPatrol          = [bool]$Config.NotifyOnPatrol
        NotifyOnApprovalNeed    = [bool]$Config.NotifyOnApprovalNeed
        NotifyOnCritical        = [bool]$Config.NotifyOnCritical
        GeminiKeyProtected      = $gemProt
        UpdatedAt               = (Get-Date).ToString('o')
        # Never store plaintext
    }
    $json = $obj | ConvertTo-Json -Depth 5
    # Write atomically
    $tmp = $path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $path -Force
    Set-SpiderSecretsAcl -Path $path
    if (Test-Path (Join-Path $PSScriptRoot 'SecurityHardening.ps1')) {
        . (Join-Path $PSScriptRoot 'SecurityHardening.ps1')
        try { Invoke-SpiderSecurityHarden | Out-Null } catch {}
    }
}

function script:Send-SpiderTelegram {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$ParseMode = ''
    )
    $cfg = Get-SpiderNotifyConfig
    if (-not $cfg.TelegramEnabled) {
        return [pscustomobject]@{ Ok = $false; Reason = 'disabled' }
    }
    $token = Unprotect-SpiderSecretString $cfg.BotTokenProtected
    $chat = [string]$cfg.ChatId
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chat)) {
        return [pscustomobject]@{ Ok = $false; Reason = 'missing_token_or_chat' }
    }
    # Validate token shape without logging it
    if ($token.Length -lt 30 -or $token -notmatch '^\d+:\S+$') {
        return [pscustomobject]@{ Ok = $false; Reason = 'token_format_invalid_or_truncated' }
    }
    if ($Text.Length -gt 3900) { $Text = $Text.Substring(0, 3850) + "`n...(cut)" }
    $uri = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{
        chat_id = $chat
        text    = $Text
        disable_web_page_preview = $true
    }
    if ($ParseMode) { $body.parse_mode = $ParseMode }
    try {
        $json = ($body | ConvertTo-Json -Compress)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req = [System.Net.HttpWebRequest]::Create($uri)
        $req.Method = 'POST'
        $req.ContentType = 'application/json; charset=utf-8'
        $req.Timeout = 20000
        $req.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream()
        $s.Write($bytes, 0, $bytes.Length)
        $s.Close()
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $raw = $sr.ReadToEnd()
        $sr.Close(); $resp.Close()
        $ok = $raw -match '"ok"\s*:\s*true'
        if (Get-Command Write-SpiderLog -ErrorAction SilentlyContinue) {
            Write-SpiderLog ("Telegram notify ok=" + $ok + " tokenLen=" + $token.Length) 'INFO'
        }
        return [pscustomobject]@{ Ok = $ok; Reason = $(if ($ok) { 'sent' } else { 'api_reject' }) }
    } catch {
        if (Get-Command Write-SpiderLog -ErrorAction SilentlyContinue) {
            Write-SpiderLog 'Telegram notify fail (details suppressed)' 'WARN'
        }
        return [pscustomobject]@{ Ok = $false; Reason = 'network_or_api_error' }
    }
}



function script:Format-SpiderTgBlock {
    param(
        [string]$Title,
        [string]$Body,
        [string]$Icon = [char]0x1F577  # spider-ish fallback; use ASCII markers for PS5.1 safety
    )
    # Prefer ASCII + simple symbols for max Telegram/client compatibility
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('[SPIDER] ' + $Title)
    [void]$lines.Add('----------------')
    if ($Body) {
        foreach ($ln in ($Body -split "`r?`n")) {
            if ($ln.Trim().Length -gt 0) { [void]$lines.Add($ln.TrimEnd()) }
        }
    }
    [void]$lines.Add('----------------')
    [void]$lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
    return ($lines -join "`n")
}

function script:Format-SpiderStatusIcons {
    param($ReportText)
    # Compress long reports into icon lines when possible
    $h = $null; $lvl = $null
    if ($ReportText -match '(\d{1,3})\s*/\s*100') { $h = $Matches[1] }
    if ($ReportText -match '\[(HEALTHY|WARNING|CRITICAL|EMERGENCY|DEGRADED)\]') { $lvl = $Matches[1] }
    $icon = switch ($lvl) {
        'HEALTHY' { '[OK]' }
        'WARNING' { '[!]' }
        'CRITICAL' { '[X]' }
        'EMERGENCY' { '[!!]' }
        'DEGRADED' { '[~]' }
        default { '[.]' }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$icon HEALTH $(if($h){"$h/100"}else{'n/a'}) $(if($lvl){$lvl}else{''})".Trim())
    if ($ReportText -match '(?i)Docker\s+(\d+)') { [void]$sb.AppendLine("[D] Docker $($Matches[1])") }
    if ($ReportText -match '(?i)Pi Node\s+(\d+)') { [void]$sb.AppendLine("[N] Node $($Matches[1])") }
    if ($ReportText -match '(?i)Network\s+(\d+)') { [void]$sb.AppendLine("[W] Net $($Matches[1])") }
    if ($ReportText -match '(?i)RAM\s+(\d+)') { [void]$sb.AppendLine("[R] RAM $($Matches[1])") }
    if ($ReportText -match '(?i)Action\s*:\s*(\S+)') { [void]$sb.AppendLine("[A] $($Matches[1])") }
    $compact = $sb.ToString().Trim()
    if ($compact.Length -lt 20 -and $ReportText) {
        # fallback: first 12 non-empty lines of report
        $keep = ($ReportText -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 12) -join "`n"
        return $keep
    }
    return $compact
}

function script:Send-SpiderPatrolReport {
    param([string]$ReportText)
    $cfg = Get-SpiderNotifyConfig
    if (-not $cfg.NotifyOnPatrol) { return }
    if (-not $ReportText) {
        $p = Join-Path $script:SpiderRoot 'Data	elegram_report.txt'
        if (Test-Path $p) { $ReportText = Get-Content $p -Raw -Encoding UTF8 }
    }
    if (-not $ReportText) { $ReportText = '[.] No report file' }
    $body = Format-SpiderStatusIcons -ReportText $ReportText
    $msg = Format-SpiderTgBlock -Title 'PATROL' -Body $body
    Send-SpiderTelegram -Text $msg | Out-Null
}

function script:Send-SpiderApprovalNotify {
    param([string]$Summary)
    $cfg = Get-SpiderNotifyConfig
    if (-not $cfg.NotifyOnApprovalNeed) { return }
    $body = @(
        '[!] ACTION NEEDS APPROVAL',
        '',
        $Summary,
        '',
        '>> Open PiSpider Dashboard',
        '>> Approve or Deny'
    ) -join "`n"
    $msg = Format-SpiderTgBlock -Title 'APPROVAL' -Body $body
    Send-SpiderTelegram -Text $msg | Out-Null
}

function script:Send-SpiderCriticalNotify {
    param([string]$Summary)
    $cfg = Get-SpiderNotifyConfig
    if (-not $cfg.NotifyOnCritical) { return }
    $body = @(
        '[X] CRITICAL',
        '',
        $Summary
    ) -join "`n"
    $msg = Format-SpiderTgBlock -Title 'ALERT' -Body $body
    Send-SpiderTelegram -Text $msg | Out-Null
}


function script:Test-SpiderTelegramSend {
    param([string]$Text = '[PiSpider] Test OK')
    $cfg = Get-SpiderNotifyConfig
    # Allow test even if TelegramEnabled is false when token+chat exist
    $token = Unprotect-SpiderSecretString $cfg.BotTokenProtected
    $chat = [string]$cfg.ChatId
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chat)) {
        return [pscustomobject]@{ Ok = $false; Reason = 'missing_token_or_chat' }
    }
    if ($token.Length -lt 30 -or $token -notmatch '^\d+:\S+$') {
        return [pscustomobject]@{ Ok = $false; Reason = 'token_format_invalid' }
    }
    $uri = "https://api.telegram.org/bot$token/sendMessage"
    $body = @{ chat_id = $chat; text = $Text; disable_web_page_preview = $true }
    try {
        $json = ($body | ConvertTo-Json -Compress)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req = [System.Net.HttpWebRequest]::Create($uri)
        $req.Method = 'POST'
        $req.ContentType = 'application/json; charset=utf-8'
        $req.Timeout = 20000
        try { $req.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy() } catch {}
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream()
        $s.Write($bytes, 0, $bytes.Length)
        $s.Close()
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $raw = $sr.ReadToEnd()
        $sr.Close(); $resp.Close()
        $ok = $raw -match '"ok"\s*:\s*true'
        return [pscustomobject]@{ Ok = $ok; Reason = $(if ($ok) { 'sent' } else { 'api_reject' }); Raw = $raw }
    } catch {
        return [pscustomobject]@{ Ok = $false; Reason = $_.Exception.Message }
    }
}
