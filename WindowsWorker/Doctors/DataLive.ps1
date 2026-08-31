# ============================================================
# Doctors/DataLive.ps1 - MonitorLive / DataLive presence Doctor
# Optional: không bắt buộc cho Spider autonomous
# ============================================================
function Invoke-DataLiveDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: DataLive" 'DIAG'
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{}

    $mlPath = $null
    if (Get-Command Find-MonitorLiveLatest -ErrorAction SilentlyContinue) {
        $mlPath = Find-MonitorLiveLatest
    }
    $evidence.MonitorLivePath = $mlPath
    $evidence.MonitorLiveFound = [bool]$mlPath

    if ($mlPath) {
        try {
            $item = Get-Item -LiteralPath $mlPath -ErrorAction SilentlyContinue
            $ageMin = if ($item) { [math]::Round(((Get-Date) - $item.LastWriteTime).TotalMinutes, 1) } else { -1 }
            $evidence.DataAgeMinutes = $ageMin
            if ($ageMin -gt 30) { [void]$issues.Add('MONITOR_DATA_STALE') }
        } catch {
            [void]$issues.Add('MONITOR_READ_FAIL')
        }
    } else {
        [void]$issues.Add('MONITOR_NOT_FOUND')
        # Not critical - Spider is independent
    }

    # Process presence
    $dl = Get-Process -Name 'DataLive','PiNodeMonitorLive','DataLive_HttpApi' -ErrorAction SilentlyContinue
    $evidence.DataLiveProcesses = if ($dl) { @($dl | Select-Object -ExpandProperty ProcessName -Unique) } else { @() }

    $status = 'OK'
    if ($issues -contains 'MONITOR_DATA_STALE') { $status = 'WARNING' }
    elseif ($issues -contains 'MONITOR_NOT_FOUND') { $status = 'INFO' }

    return [pscustomobject]@{
        Doctor = 'DataLive'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = 'NONE'
        Notes = 'Optional telemetry source - Spider runs without it'
    }
}
