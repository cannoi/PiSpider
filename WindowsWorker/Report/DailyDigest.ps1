#Requires -Version 5.1
# ============================================================
# Report/DailyDigest.ps1
# Daily issues report (19:00-20:00) — template-driven
# Edit Report/DigestTemplate.json to customize layout/text
# ============================================================

function Get-SpiderDigestTemplate {
    $path = Join-Path $script:SpiderRoot 'Report\DigestTemplate.json'
    if (-not (Test-Path -LiteralPath $path)) {
        $path = Join-Path $PSScriptRoot 'DigestTemplate.json'
    }
    $default = [pscustomobject]@{
        Title = '[SPIDER] DAILY DIGEST'
        Separator = '----------------'
        ShowPcUser = $true
        ShowHealth = $true
        ShowIssues = $true
        ShowNotes = $true
        ShowInsight = $true
        ShowApprovalHint = $true
        ShowTimestamp = $true
        MaxIssueDetailChars = 120
        MaxInsightChars = 280
        MaxNotes = 5
        Icons = [pscustomobject]@{ OK='[OK]'; Warn='[!]'; Crit='[X]'; Emer='[!!]'; Info='[i]' }
        ForceLanguage = $null
        Text = $null
    }
    if (-not (Test-Path -LiteralPath $path)) { return $default }
    try {
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return $j
    } catch {
        Write-SpiderLog "DigestTemplate load fail: $($_.Exception.Message)" 'WARN'
        return $default
    }
}

function Get-SpiderDigestLocale {
    param($Template)
    $force = $null
    if ($Template -and $Template.ForceLanguage) { $force = [string]$Template.ForceLanguage }
    if ($force -eq 'vi' -or $force -eq 'en') {
        return [pscustomobject]@{ IsVi = ($force -eq 'vi'); Culture = $force }
    }
    try {
        $cul = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    } catch { $cul = 'en' }
    return [pscustomobject]@{
        IsVi = ($cul -match '^vi')
        Culture = $cul
    }
}

function Get-SpiderDigestText {
    param($Template, $Key, [bool]$IsVi, [object[]]$FormatArgs = @())
    $bag = $null
    if ($Template -and $Template.Text) {
        if ($IsVi -and $Template.Text.vi) { $bag = $Template.Text.vi }
        elseif ($Template.Text.en) { $bag = $Template.Text.en }
    }
    $fallback = @{
        NoIssues = $(if ($IsVi) { 'Khong phat hien van de can chu y' } else { 'No issues needing attention' })
        Stable = $(if ($IsVi) { 'Node on dinh — giu nguyen' } else { 'Node stable — no change needed' })
        IssuesHeader = $(if ($IsVi) { '--- Van de ({0}) ---' } else { '--- Issues ({0}) ---' })
        NotesHeader = $(if ($IsVi) { '--- Ghi chu ---' } else { '--- Notes ---' })
        InsightHeader = $(if ($IsVi) { '--- Nhan dinh ---' } else { '--- Insight ---' })
        ApprovalHint = $(if ($IsVi) { 'Can xac nhan — mo PiSpider Dashboard' } else { 'Approval pending — open PiSpider Dashboard' })
        HealthLine = $(if ($IsVi) { '{0} Suc khoe {1}/100 {2}' } else { '{0} Health {1}/100 {2}' })
    }
    $fmt = $null
    if ($bag -and $bag.PSObject.Properties[$Key]) { $fmt = [string]$bag.$Key }
    if (-not $fmt) { $fmt = [string]$fallback[$Key] }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) {
        try { return ($fmt -f $FormatArgs) } catch { return $fmt }
    }
    return $fmt
}

function New-SpiderDailyDigestText {
    param(
        $Snapshot = $null,
        $Findings = $null,
        $Health = $null,
        $Decision = $null,
        $DoctorPanel = $null,
        $AiResult = $null
    )

    $tpl = Get-SpiderDigestTemplate
    $loc = Get-SpiderDigestLocale -Template $tpl
    $ico = $tpl.Icons
    if (-not $ico) { $ico = [pscustomobject]@{ OK='[OK]'; Warn='[!]'; Crit='[X]'; Emer='[!!]'; Info='[i]' } }

    $maxDet = 120
    if ($tpl.MaxIssueDetailChars) { $maxDet = [int]$tpl.MaxIssueDetailChars }
    $maxIns = 280
    if ($tpl.MaxInsightChars) { $maxIns = [int]$tpl.MaxInsightChars }
    $maxNotes = 5
    if ($tpl.MaxNotes) { $maxNotes = [int]$tpl.MaxNotes }

    $issues = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]

    if ($Findings) {
        foreach ($f in @($Findings)) {
            $sev = [string]$f.Severity
            if ($sev -in @('WARNING', 'CRITICAL', 'EMERGENCY')) {
                $id = [string]$f.Id
                $det = [string]$f.Details
                if ($det.Length -gt $maxDet) { $det = $det.Substring(0, [Math]::Max(0, $maxDet - 3)) + '...' }
                $tag = switch ($sev) {
                    'EMERGENCY' { $ico.Emer }
                    'CRITICAL'  { $ico.Crit }
                    default     { $ico.Warn }
                }
                [void]$issues.Add("$tag $id — $det")
            } elseif ($sev -eq 'INFO' -and $f.Id -match 'MONITOR|OPTIONAL') {
                [void]$notes.Add("$($ico.Info) $($f.Id)")
            }
        }
    }

    if ($DoctorPanel -and $DoctorPanel.Results) {
        foreach ($r in @($DoctorPanel.Results)) {
            $st = [string]$r.Status
            if ($st -in @('WARNING', 'CRITICAL')) {
                $line = "$($ico.Warn) Doctor $($r.Name): $st"
                if ($r.PSObject.Properties['Message'] -and $r.Message) {
                    $m = [string]$r.Message
                    if ($m.Length -gt 80) { $m = $m.Substring(0, 77) + '...' }
                    $line += " — $m"
                }
                if (-not ($issues -contains $line)) { [void]$issues.Add($line) }
            }
        }
    }

    $score = $null
    $level = $null
    if ($Health) {
        if ($Health.PSObject.Properties['Overall']) { $score = $Health.Overall }
        if ($Health.PSObject.Properties['Level']) { $level = $Health.Level }
    }

    $hostName = $env:COMPUTERNAME
    $user = $env:USERNAME
    $lines = New-Object System.Collections.Generic.List[string]
    $title = if ($tpl.Title) { [string]$tpl.Title } else { '[SPIDER] DAILY DIGEST' }
    $sep = if ($tpl.Separator) { [string]$tpl.Separator } else { '----------------' }

    [void]$lines.Add($title)
    [void]$lines.Add($sep)

    if ($tpl.ShowPcUser -ne $false) {
        [void]$lines.Add("PC: $hostName | User: $user")
    }

    if ($tpl.ShowHealth -ne $false -and $null -ne $score) {
        $mark = switch -Regex ([string]$level) {
            'HEALTHY' { $ico.OK }
            'WARNING|DEGRADED' { $ico.Warn }
            'CRITICAL|EMERGENCY' { $ico.Crit }
            default { '[.]' }
        }
        $hl = Get-SpiderDigestText -Template $tpl -Key 'HealthLine' -IsVi $loc.IsVi -FormatArgs @($mark, $score, $level)
        [void]$lines.Add($hl)
    }

    if ($tpl.ShowIssues -ne $false) {
        if ($issues.Count -eq 0) {
            [void]$lines.Add((Get-SpiderDigestText -Template $tpl -Key 'NoIssues' -IsVi $loc.IsVi))
            [void]$lines.Add((Get-SpiderDigestText -Template $tpl -Key 'Stable' -IsVi $loc.IsVi))
        } else {
            [void]$lines.Add((Get-SpiderDigestText -Template $tpl -Key 'IssuesHeader' -IsVi $loc.IsVi -FormatArgs @($issues.Count)))
            foreach ($i in $issues) { [void]$lines.Add($i) }
        }
    }

    if ($tpl.ShowNotes -ne $false -and $notes.Count -gt 0) {
        [void]$lines.Add((Get-SpiderDigestText -Template $tpl -Key 'NotesHeader' -IsVi $loc.IsVi))
        $n = 0
        foreach ($note in $notes) {
            if ($n -ge $maxNotes) { break }
            [void]$lines.Add($note)
            $n++
        }
    }

    $insight = $null
    if ($AiResult) {
        if ($AiResult.PSObject.Properties['Explanation'] -and $AiResult.Explanation) {
            $insight = [string]$AiResult.Explanation
        } elseif ($AiResult.PSObject.Properties['Recommendation']) {
            $insight = "Suggest: $($AiResult.Recommendation)"
        }
    }
    if (-not $insight -and $Decision -and $Decision.Action -and $Decision.Action -ne 'NONE') {
        $insight = "Action candidate: $($Decision.Action) (risk $($Decision.Risk))"
    }
    if ($tpl.ShowInsight -ne $false -and $insight) {
        if ($insight.Length -gt $maxIns) { $insight = $insight.Substring(0, [Math]::Max(0, $maxIns - 3)) + '...' }
        [void]$lines.Add((Get-SpiderDigestText -Template $tpl -Key 'InsightHeader' -IsVi $loc.IsVi))
        [void]$lines.Add($insight)
    }

    if ($tpl.ShowApprovalHint -ne $false -and $Decision -and $Decision.RequiresApproval) {
        [void]$lines.Add((Get-SpiderDigestText -Template $tpl -Key 'ApprovalHint' -IsVi $loc.IsVi))
    }

    if ($tpl.ShowTimestamp -ne $false) {
        [void]$lines.Add($sep)
        [void]$lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
    }

    return ($lines -join "`n")
}

function Invoke-SpiderDailyDigest {
    param(
        [switch]$SendTelegram,
        [switch]$ForceOutsideWindow
    )

    $now = Get-Date
    # Window 19:00-20:59 local (task default 19:15). Independent of Dashboard/PiSpider.exe.
    $inWindow = (($now.Hour -eq 19) -or ($now.Hour -eq 20) -or $ForceOutsideWindow)
    if (-not $inWindow -and $SendTelegram) {
        Write-SpiderLog "DailyDigest: outside 19-20h window (hour=$($now.Hour)) — file only, no Telegram" 'INFO'
    }

    $snapshot = $null
    $findings = $null
    $health = $null
    $decision = $null
    $doctors = $null
    $ai = $null

    try {
        if (Get-Command Invoke-Discovery -EA SilentlyContinue) {
            $snapshot = Invoke-Discovery
        }
        if ($snapshot -and (Get-Command Invoke-AllDoctors -EA SilentlyContinue)) {
            $doctors = Invoke-AllDoctors -Snapshot $snapshot
        }
        if ($snapshot -and (Get-Command Invoke-Diagnostic -EA SilentlyContinue)) {
            $diag = Invoke-Diagnostic -Snapshot $snapshot -DoctorPanel $doctors
            $findings = $diag.Findings
            if ($diag.PSObject.Properties['Health']) { $health = $diag.Health }
        }
        if (Get-Command Invoke-Decision -EA SilentlyContinue) {
            $decision = Invoke-Decision -Snapshot $snapshot -Findings $findings -DoctorPanel $doctors
        }
        if (Get-Command Invoke-AIAnalysis -EA SilentlyContinue) {
            $ai = Invoke-AIAnalysis -Snapshot $snapshot -Findings $findings -Decision $decision -DoctorPanel $doctors
        }
        if (-not $health) {
            $lr = Join-Path $script:SpiderRoot 'Data\last_report.json'
            if (Test-Path $lr) {
                try {
                    $j = Get-Content $lr -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($j.Health) { $health = $j.Health }
                } catch {}
            }
        }
    } catch {
        Write-SpiderLog "DailyDigest collect: $($_.Exception.Message)" 'WARN'
    }

    $text = New-SpiderDailyDigestText -Snapshot $snapshot -Findings $findings -Health $health `
        -Decision $decision -DoctorPanel $doctors -AiResult $ai

    $outDir = Join-Path $script:SpiderRoot 'Data'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $path = Join-Path $outDir 'daily_digest.txt'
    $text | Set-Content -LiteralPath $path -Encoding UTF8
    Write-SpiderLog "DailyDigest saved: $path" 'INFO'
    Write-Host $text

    $cfg = $null
    if (Get-Command Get-SpiderNotifyConfig -EA SilentlyContinue) {
        $cfg = Get-SpiderNotifyConfig
    }
    $wantTg = $false
    $skipReason = ''
    if (-not $SendTelegram) {
        $skipReason = 'SendTelegram switch not set'
    } elseif (-not $cfg) {
        $skipReason = 'no notify config'
    } elseif (-not $cfg.TelegramEnabled) {
        $skipReason = 'TelegramEnabled=false — enable in PiSpider Dashboard Settings'
    } elseif ($null -ne $cfg.NotifyOnPatrol -and -not [bool]$cfg.NotifyOnPatrol) {
        $skipReason = 'Daily digest notify disabled in Settings'
    } else {
        $wantTg = $true
    }

    $sent = $false
    $tgReason = $skipReason
    if ($wantTg -and $inWindow) {
        if (Get-Command Send-SpiderTelegram -EA SilentlyContinue) {
            $r = Send-SpiderTelegram -Text $text
            $sent = [bool]$r.Ok
            $tgReason = if ($r.Ok) { 'sent' } else { [string]$r.Reason }
            Write-SpiderLog "DailyDigest Telegram Ok=$($r.Ok) reason=$tgReason" 'INFO'
        } else {
            $tgReason = 'Send-SpiderTelegram missing'
        }
    } elseif ($wantTg -and -not $inWindow) {
        $tgReason = "outside_window hour=$($now.Hour)"
        Write-SpiderLog "DailyDigest: Telegram skipped ($tgReason). File saved." 'INFO'
    } else {
        Write-SpiderLog "DailyDigest: Telegram not sent ($tgReason). File saved." 'INFO'
    }

    # Meta for troubleshooting (no secrets)
    try {
        $meta = [ordered]@{
            Timestamp = (Get-Date).ToString('o')
            InWindow = [bool]$inWindow
            Hour = $now.Hour
            TelegramEnabled = [bool]($cfg -and $cfg.TelegramEnabled)
            Sent = $sent
            Reason = $tgReason
            DigestPath = $path
            Note = 'Daily report runs via Task Scheduler PiNodeSpider_DailyReport — Dashboard does not need to stay open'
        }
        ($meta | ConvertTo-Json) | Set-Content (Join-Path $outDir 'daily_digest_meta.json') -Encoding UTF8
    } catch {}

    return [pscustomobject]@{
        Text = $text
        Path = $path
        InWindow = $inWindow
        Sent = $sent
        Reason = $tgReason
    }
}
