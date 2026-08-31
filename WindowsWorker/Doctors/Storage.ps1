# ============================================================
# Doctors/Storage.ps1 - Storage / Disk Doctor
# Free space, growth pressure (best-effort)
# ============================================================
function Invoke-StorageDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Storage" 'DIAG'
    $cfg = Get-SpiderConfig
    $disk = $Snapshot.Disk
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{
        FreeGB = $disk.FreeGB
        UsedGB = $disk.UsedGB
        TotalGB = $disk.TotalGB
        FreePct = $disk.FreePct
    }

    $warn = $cfg.Thresholds.Disk_Free_GB_Warning
    $crit = $cfg.Thresholds.Disk_Free_GB_Critical

    if ($disk.FreeGB -lt $crit) { [void]$issues.Add('DISK_CRITICAL') }
    elseif ($disk.FreeGB -lt $warn) { [void]$issues.Add('DISK_LOW') }

    if ($disk.FreePct -gt 0 -and $disk.FreePct -lt 10) {
        if ($issues -notcontains 'DISK_CRITICAL') { [void]$issues.Add('DISK_PCT_LOW') }
    }

    # Docker/WSL storage note (informational)
    $evidence.Hint = 'Check Docker data + WSL vhdx if free space drops fast'

    $status = 'OK'
    if ($issues -contains 'DISK_CRITICAL') { $status = 'CRITICAL' }
    elseif ($issues.Count -gt 0) { $status = 'WARNING' }

    $action = if ($issues.Count -gt 0) { 'CLEAN_TEMP' } else { 'NONE' }

    return [pscustomobject]@{
        Doctor = 'Storage'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "Free=$($disk.FreeGB)GB ($($disk.FreePct)%)"
    }
}
