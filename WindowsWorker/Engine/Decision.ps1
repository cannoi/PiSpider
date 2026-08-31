# ============================================================
# Engine/Decision.ps1 - Autonomy + Risk + Minimal Intervention
# ============================================================

function Invoke-Decision {
    param($Snapshot, $Findings)
    $cfg = Get-SpiderConfig
    $mode = $cfg.Mode
    $policy = $cfg.RiskPolicy

    if (-not $Findings -or $Findings.Count -eq 0) {
        return [pscustomobject]@{
            Decision='NONE'; Action='NONE'; Reason='No findings'
            AutoExecute=$false; RequiresApproval=$false; Mode=$mode; Risk='NONE'
        }
    }

    $primary = $Findings | Select-Object -First 1

    if ($primary.Action -eq 'NONE' -or $primary.Severity -eq 'HEALTHY') {
        return [pscustomobject]@{
            Decision='HEALTHY'; Action='NONE'; Reason=$primary.RootCause
            Finding=$primary; AutoExecute=$false; RequiresApproval=$false; Mode=$mode; Risk='NONE'
        }
    }

    $risk = if ($primary.Risk) { $primary.Risk } else { 'MEDIUM' }
    $autoAllowed = $false
    $needsApproval = $true

    # Risk policy
    $riskCfg = $null
    if ($policy.PSObject.Properties.Name -contains $risk) {
        $riskCfg = $policy.$risk
    }

    if ($risk -eq 'EXTREME' -or ($riskCfg -and $riskCfg.NeverAuto)) {
        $autoAllowed = $false
        $needsApproval = $true
    } else {
        switch ($mode) {
            'OBSERVE' {
                $autoAllowed = $false; $needsApproval = $false
            }
            'ASSIST' {
                $autoAllowed = $false; $needsApproval = $true
            }
            'AUTO-SAFE' {
                if ($risk -eq 'LOW' -or $risk -eq 'NONE') {
                    $autoAllowed = $true; $needsApproval = $false
                } else {
                    $autoAllowed = $false; $needsApproval = $true
                }
            }
            'AUTO-RECOVERY' {
                if ($risk -in @('LOW','NONE','MEDIUM')) {
                    $autoAllowed = $true
                    $needsApproval = ($risk -eq 'MEDIUM' -or $risk -eq 'HIGH')
                } elseif ($risk -eq 'HIGH') {
                    $autoAllowed = $false; $needsApproval = $true
                }
            }
            'EMERGENCY-GUARDIAN' {
                # Prefer Node stability; allow HIGH if ImpactOnNode HIGH and no contact
                $autoAllowed = ($risk -ne 'EXTREME')
                $needsApproval = ($risk -eq 'HIGH' -or $risk -eq 'EXTREME')
            }
        }
    }

    # Dependency awareness: do not reset lower layers if upper dependency broken
    if ($primary.Action -in @('RESTART_NODE','RESTART_DOCKER') -and -not $Snapshot.Network.Internet) {
        Write-SpiderLog "Dependency: Internet down → prefer NETWORK_REPAIR over $($primary.Action)" 'DIAG'
        return [pscustomobject]@{
            Decision = 'CRITICAL'
            Action = 'NETWORK_REPAIR'
            Reason = "Internet down (dependency). Original: $($primary.RootCause)"
            Finding = $primary
            Confidence = $primary.Confidence
            AutoExecute = ($mode -in @('AUTO-SAFE','AUTO-RECOVERY','EMERGENCY-GUARDIAN'))
            RequiresApproval = ($mode -eq 'ASSIST')
            Mode = $mode
            Risk = 'MEDIUM'
        }
    }

    $finalAction = $primary.Action
    $depNote = $null
    if (Get-Command Resolve-ActionByDependency -ErrorAction SilentlyContinue) {
        $dep = Resolve-ActionByDependency -ProposedAction $primary.Action -Snapshot $Snapshot
        if ($dep.Redirected) {
            $finalAction = $dep.RecommendedAction
            $depNote = $dep.Reason
            Write-SpiderLog "Decision dependency: $($dep.Reason)" 'DIAG'
        }
    }

    return [pscustomobject]@{
        Decision = $primary.Severity
        Action = $finalAction
        Reason = $primary.RootCause
        Confidence = $primary.Confidence
        Finding = $primary
        AutoExecute = $autoAllowed
        RequiresApproval = $needsApproval
        Mode = $mode
        Risk = $risk
        ImpactOnNode = $primary.ImpactOnNode
        DependencyNote = $depNote
    }
}
