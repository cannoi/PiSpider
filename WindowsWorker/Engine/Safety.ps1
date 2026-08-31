# ============================================================
# Engine/Safety.ps1
# Safety Policy | Protected Zone gates | Risk gate | Destructive guards
# Mọi action nguy hiểm PHẢI qua đây trước khi ActionEngine thực thi
# ============================================================

function Test-SafetyPolicy {
    param(
        [string]$ActionName,
        [string]$Risk = 'MEDIUM',
        [string]$Mode = 'ASSIST',
        [switch]$Force,
        [switch]$UserApproved
    )

    $cfg = Get-SpiderConfig
    $zone = Get-ProtectedZone
    $policy = Get-RecoveryPolicy
    $reasons = [System.Collections.Generic.List[string]]::new()
    $allowed = $true

    # 1) EXTREME never auto
    if ($Risk -eq 'EXTREME') {
        if (-not $UserApproved -and -not $Force) {
            $allowed = $false
            [void]$reasons.Add('EXTREME risk requires explicit user approval')
        }
        if ($zone -and $zone.NeverAutoUpgradeEXTREME -and -not $UserApproved) {
            $allowed = $false
            [void]$reasons.Add('Protected zone: NeverAutoUpgradeEXTREME')
        }
    }

    # 2) Circuit breaker
    if (-not (Test-CircuitBreaker $ActionName)) {
        $allowed = $false
        [void]$reasons.Add("CircuitBreaker OPEN for $ActionName")
    }

    # 3) Mode vs Risk policy
    $riskCfg = $null
    if ($cfg -and $cfg.RiskPolicy -and $cfg.RiskPolicy.PSObject.Properties.Name -contains $Risk) {
        $riskCfg = $cfg.RiskPolicy.$Risk
    }
    if ($riskCfg -and $riskCfg.NeverAuto -and -not $UserApproved -and -not $Force) {
        $allowed = $false
        [void]$reasons.Add("RiskPolicy NeverAuto for $Risk")
    }

    # OBSERVE never executes repair actions
    if ($Mode -eq 'OBSERVE' -and $ActionName -notin @('NONE','MONITOR','WAIT_MONITOR','REPORT_CONFIG')) {
        $allowed = $false
        [void]$reasons.Add('Mode OBSERVE forbids execution')
    }

    # 4) Action must exist in recovery catalog if policy present
    if ($policy -and $policy.Actions) {
        $known = $policy.Actions.PSObject.Properties.Name
        if ($known -notcontains $ActionName -and $ActionName -notin @('NONE','MONITOR','WAIT_MONITOR','REPORT_CONFIG','DNS_REFRESH')) {
            # Allow unknown but flag
            [void]$reasons.Add("Action $ActionName not in Recovery catalog (allowed with caution)")
        }
    }

    # 5) Destructive path guard
    if ($ActionName -match '(?i)format|diskpart|bcdedit|firmware|bios') {
        $allowed = $false
        [void]$reasons.Add('Destructive system/firmware action blocked by Safety')
    }

    return [pscustomobject]@{
        Allowed = $allowed
        Action  = $ActionName
        Risk    = $Risk
        Mode    = $Mode
        Reasons = @($reasons)
        Timestamp = (Get-Date).ToString('o')
    }
}

function Assert-NotProtectedTarget {
    param(
        [string]$ProcessName,
        [string]$Path
    )
    if ($ProcessName -and (Test-ProtectedProcess $ProcessName)) {
        Write-SpiderLog "SAFETY BLOCK: protected process $ProcessName" 'WARN'
        return $false
    }
    if ($Path -and (Test-ProtectedPath $Path)) {
        Write-SpiderLog "SAFETY BLOCK: protected path $Path" 'WARN'
        return $false
    }
    return $true
}

function Invoke-SafetyGate {
    param(
        [string]$ActionName,
        [string]$Risk = 'MEDIUM',
        [string]$Mode = 'ASSIST',
        [switch]$Force,
        [switch]$UserApproved
    )
    $result = Test-SafetyPolicy -ActionName $ActionName -Risk $Risk -Mode $Mode -Force:$Force -UserApproved:$UserApproved
    if (-not $result.Allowed) {
        Write-SpiderLog ("SAFETY DENY {0}: {1}" -f $ActionName, ($result.Reasons -join '; ')) 'WARN'
    } else {
        Write-SpiderLog "SAFETY ALLOW $ActionName (Risk=$Risk Mode=$Mode)" 'DEBUG'
    }
    return $result
}

function Get-MaxRiskForMode {
    param([string]$Mode)
    switch ($Mode) {
        'OBSERVE'             { return 'NONE' }
        'ASSIST'              { return 'NONE' }  # needs approval for anything real
        'AUTO-SAFE'           { return 'LOW' }
        'AUTO-RECOVERY'       { return 'HIGH' }
        'EMERGENCY-GUARDIAN'  { return 'HIGH' }
        default               { return 'LOW' }
    }
}

function Test-ActionWithinModeRisk {
    param([string]$ActionRisk, [string]$Mode)
    $order = @{ 'NONE'=0; 'LOW'=1; 'MEDIUM'=2; 'HIGH'=3; 'EXTREME'=4 }
    $max = Get-MaxRiskForMode $Mode
    $ar = if ($order.ContainsKey($ActionRisk)) { $order[$ActionRisk] } else { 2 }
    $mr = if ($order.ContainsKey($max)) { $order[$max] } else { 1 }
    # ASSIST/OBSERVE still allow proposal; execution gated elsewhere
    if ($Mode -in @('ASSIST','OBSERVE')) { return $true }
    return ($ar -le $mr)
}

Write-SpiderLog "Engine Safety loaded" 'DEBUG'
