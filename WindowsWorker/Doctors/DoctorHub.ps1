# ============================================================
# Doctors/DoctorHub.ps1 - Orchestrate all doctors
# ============================================================
function Invoke-AllDoctors {
    param($Snapshot)
    if (-not $Snapshot) { $Snapshot = Invoke-FullCollect }

    $doctors = @(
        'Invoke-WindowsDoctor',
        'Invoke-HardwareDoctor',
        'Invoke-NetworkDoctor',
        'Invoke-FirewallDoctor',
        'Invoke-WSLDoctor',
        'Invoke-DockerDoctor',
        'Invoke-PiNodeDoctor',
        'Invoke-StellarDoctor',
        'Invoke-StorageDoctor',
        'Invoke-SecurityDoctor',
        'Invoke-DataLiveDoctor'
    )

    $results = @()
    foreach ($fn in $doctors) {
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            try {
                $r = & $fn -Snapshot $Snapshot
                $results += $r
            } catch {
                $results += [pscustomobject]@{
                    Doctor = $fn
                    Status = 'ERROR'
                    Issues = @('DOCTOR_EXCEPTION')
                    Notes = $_.Exception.Message
                }
            }
        }
    }

    $critical = @($results | Where-Object { $_.Status -eq 'CRITICAL' })
    $warning = @($results | Where-Object { $_.Status -eq 'WARNING' })
    $summary = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Total = $results.Count
        Critical = $critical.Count
        Warning = $warning.Count
        OK = @($results | Where-Object { $_.Status -eq 'OK' }).Count
        Results = $results
        WorstStatus = if ($critical.Count -gt 0) { 'CRITICAL' } elseif ($warning.Count -gt 0) { 'WARNING' } else { 'OK' }
    }
    return $summary
}

function Format-DoctorReport {
    param($DoctorSummary)
    if (-not $DoctorSummary) { return 'No doctor results.' }
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("🩺 DOCTOR PANEL - $($DoctorSummary.WorstStatus)")
    [void]$lines.Add("Critical=$($DoctorSummary.Critical) Warning=$($DoctorSummary.Warning) OK=$($DoctorSummary.OK)")
    foreach ($r in $DoctorSummary.Results) {
        $icon = switch ($r.Status) {
            'OK' {'[OK]'} 'WARNING' {'[WARN]'} 'CRITICAL' {'[CRIT]'} 'INFO' {'[INFO]'} default {'[.]'}
        }
        $iss = if ($r.Issues -and $r.Issues.Count) { $r.Issues -join ',' } else { '-' }
        [void]$lines.Add("$icon $($r.Doctor): $($r.Status) [$iss]")
        if ($r.Notes) { [void]$lines.Add("   $($r.Notes)") }
    }
    return ($lines -join "`n")
}
