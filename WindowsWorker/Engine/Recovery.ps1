# ============================================================
# Engine/Recovery.ps1
# Recovery pipeline: dependency-aware multi-step recovery + verify loop
# ============================================================

function Invoke-RecoveryPipeline {
    param(
        [string]$Level = 'soft',
        $Snapshot,
        [string]$Mode = 'ASSIST',
        [switch]$Force,
        [switch]$UserApproved
    )

    Write-SpiderLog "=== RECOVERY PIPELINE Level=$Level ===" 'ACTION'
    if (-not $Snapshot) { $Snapshot = Invoke-FullCollect }

    $steps = @()
    # Ladder: never jump to wsl --shutdown for sync lag alone
    switch ($Level) {
        'soft' {
            $steps = @('MAINTENANCE_LIGHT')
        }
        'network' {
            $steps = @('NETWORK_REPAIR', 'FIREWALL_CHECK')
        }
        'node' {
            $steps = @('RESTART_NODE')  # container only
        }
        'docker' {
            $steps = @('SOFT_DOCKER_RESTART')  # no wsl
        }
        'wsl' {
            $steps = @('ORDERED_WSL_RECYCLE')  # Desktop stop THEN wsl --shutdown
        }
        'hard' {
            $steps = @('RESTART_NODE', 'SOFT_DOCKER_RESTART', 'ORDERED_WSL_RECYCLE')
        }
        'all' {
            # Still ordered minimal first; HOST_REBOOT is NEVER in automatic chain
            $steps = @('RESTART_NODE', 'SOFT_DOCKER_RESTART', 'ORDERED_WSL_RECYCLE')
        }
        'reboot' {
            $steps = @('HOST_REBOOT')
        }
        default {
            $steps = @('MAINTENANCE_LIGHT')
        }
    }

    # Dependency redirect first step if needed
    if (Get-Command Resolve-ActionByDependency -ErrorAction SilentlyContinue) {
        $dep = Resolve-ActionByDependency -ProposedAction $steps[0] -Snapshot $Snapshot
        if ($dep.Redirected) {
            Write-SpiderLog "Recovery redirected: $($dep.Reason)" 'DIAG'
            $steps[0] = $dep.RecommendedAction
        }
    }

    $results = @()
    $allOk = $true
    $currentSnap = $Snapshot

    foreach ($action in $steps) {
        $risk = 'MEDIUM'
        $pol = Get-RecoveryPolicy
        if ($pol -and $pol.Actions -and $pol.Actions.PSObject.Properties.Name -contains $action) {
            $risk = [string]$pol.Actions.$action.Risk
        }

        # Safety gate
        if (Get-Command Invoke-SafetyGate -ErrorAction SilentlyContinue) {
            $gate = Invoke-SafetyGate -ActionName $action -Risk $risk -Mode $Mode -Force:$Force -UserApproved:$UserApproved
            if (-not $gate.Allowed) {
                $results += [pscustomobject]@{ Action=$action; Success=$false; Message='Blocked by Safety'; Safety=$gate }
                $allOk = $false
                break
            }
        }

        $ar = Invoke-SpiderAction -ActionName $action -Snapshot $currentSnap
        $vr = Invoke-Verify -BeforeSnapshot $currentSnap -ActionResult $ar -Decision ([pscustomobject]@{ Action = $action })
        $results += [pscustomobject]@{
            Action = $action
            ActionResult = $ar
            Verify = $vr
            Success = [bool]$vr.Success
        }
        if (-not $vr.Success) {
            $allOk = $false
            # Retry once if policy allows
            $maxRetry = 1
            if ($pol -and $pol.Actions -and $pol.Actions.$action) {
                $maxRetry = [int]$pol.Actions.$action.Retry
            }
            if ($maxRetry -gt 0) {
                Write-SpiderLog "Recovery retry once: $action" 'WARN'
                Start-Sleep -Seconds 5
                $ar2 = Invoke-SpiderAction -ActionName $action -Snapshot $currentSnap
                $vr2 = Invoke-Verify -BeforeSnapshot $currentSnap -ActionResult $ar2 -Decision ([pscustomobject]@{ Action = $action })
                $results += [pscustomobject]@{ Action="$action/retry"; ActionResult=$ar2; Verify=$vr2; Success=[bool]$vr2.Success }
                if (-not $vr2.Success) { $allOk = $false; break }
            } else {
                break
            }
        }
        $currentSnap = if ($vr.SnapshotAfter) { $vr.SnapshotAfter } else { Invoke-FullCollect }
        Start-Sleep -Seconds 2
    }

    $finalHealth = Get-HealthScore $currentSnap
    $pipeline = [pscustomobject]@{
        Level = $Level
        Success = $allOk
        Steps = $results
        FinalHealth = $finalHealth
        Timestamp = (Get-Date).ToString('o')
    }

    Add-SpiderEvent -Category 'RECOVERY' -Severity $(if($allOk){'INFO'}else{'CRITICAL'}) `
        -Symptoms "Recovery level=$Level" -RootCause "Pipeline" `
        -Confidence 90 -Action $Level -Result $(if($allOk){'SUCCESS'}else{'FAILED'})

    Write-SpiderLog ("RECOVERY PIPELINE done Success={0} Health={1}" -f $allOk, $finalHealth.Overall) 'ACTION'
    return $pipeline
}

function Invoke-SmartRecovery {
    param(
        $Snapshot,
        $Decision,
        [string]$Mode = 'ASSIST',
        [switch]$Force,
        [switch]$UserApproved
    )
    # Map decision action to recovery level or single action
    if (-not $Decision -or $Decision.Action -in @('NONE','MONITOR','WAIT_MONITOR')) {
        return [pscustomobject]@{ Success=$true; Message='No recovery needed' }
    }

    $action = $Decision.Action
    if (Get-Command Resolve-ActionByDependency -ErrorAction SilentlyContinue) {
        $dep = Resolve-ActionByDependency -ProposedAction $action -Snapshot $Snapshot
        if ($dep.Redirected) {
            Write-SpiderLog "SmartRecovery redirect: $($dep.Reason)" 'DIAG'
            $action = $dep.RecommendedAction
        }
    }

    $risk = if ($Decision.Risk) { $Decision.Risk } else { 'MEDIUM' }
    if (Get-Command Invoke-SafetyGate -ErrorAction SilentlyContinue) {
        $gate = Invoke-SafetyGate -ActionName $action -Risk $risk -Mode $Mode -Force:$Force -UserApproved:$UserApproved
        if (-not $gate.Allowed) {
            return [pscustomobject]@{ Success=$false; Message='Safety blocked'; Safety=$gate; Action=$action }
        }
    }

    $ar = Invoke-SpiderAction -ActionName $action -Snapshot $Snapshot
    $vr = Invoke-Verify -BeforeSnapshot $Snapshot -ActionResult $ar -Decision ([pscustomobject]@{ Action = $action })
    return [pscustomobject]@{
        Success = [bool]$vr.Success
        Action = $action
        ActionResult = $ar
        Verify = $vr
    }
}

Write-SpiderLog "Engine Recovery loaded" 'DEBUG'
