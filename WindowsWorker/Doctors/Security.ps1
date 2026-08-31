# ============================================================
# Doctors/Security.ps1 - Security posture (lightweight)
# Protected processes present, suspicious high-RAM unknowns (report only)
# ============================================================
function Invoke-SecurityDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Security" 'DIAG'
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{}

    # Ensure core Pi/Docker processes not missing when node claimed healthy
    $protectedRunning = @()
    if ($Snapshot.TopProcesses) {
        $protectedRunning = @($Snapshot.TopProcesses | Where-Object { $_.Protected } | Select-Object -ExpandProperty Name -Unique)
    }
    $evidence.ProtectedSeen = $protectedRunning

    # Flag very large non-candidate non-protected processes (observation only)
    $suspicious = @()
    if ($Snapshot.TopProcesses) {
        foreach ($p in $Snapshot.TopProcesses) {
            if (-not $p.Protected -and -not (Test-CleanupCandidate $p.Name) -and $p.MB -ge 1500) {
                $suspicious += "$($p.Name):$($p.MB)MB"
            }
        }
    }
    $evidence.LargeUnknownProcesses = $suspicious
    if ($suspicious.Count -gt 0) { [void]$issues.Add('LARGE_UNKNOWN_PROCESS') }

    $status = if ($issues.Count -gt 0) { 'INFO' } else { 'OK' }

    return [pscustomobject]@{
        Doctor = 'Security'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = 'NONE'
        Notes = 'Observation only - no auto kill outside CleanupCandidates'
    }
}
