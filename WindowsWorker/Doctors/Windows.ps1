# ============================================================
# Doctors/Windows.ps1 - Windows OS Doctor
# CPU, RAM, Uptime, Admin, Virtualization, processes pressure
# ============================================================
function Invoke-WindowsDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Windows" 'DIAG'
    $cfg = Get-SpiderConfig
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{}

    $ram = if ($Snapshot.Memory) { $Snapshot.Memory.UsedPct } else { 0 }
    $cpu = if ($null -ne $Snapshot.CPU) { [int]$Snapshot.CPU } else { 0 }
    $uptime = if ($Snapshot.UptimeHours) { $Snapshot.UptimeHours } else { 0 }
    $admin = [bool]$Snapshot.Admin
    $virt = $Snapshot.Virtualization

    $evidence.RAM_Pct = $ram
    $evidence.CPU_Pct = $cpu
    $evidence.UptimeHours = $uptime
    $evidence.Admin = $admin
    $evidence.Virtualization = if ($virt) { $virt.Enabled } else { $null }

    if ($ram -ge $cfg.Thresholds.RAM_Critical) { [void]$issues.Add('RAM_CRITICAL') }
    elseif ($ram -ge $cfg.Thresholds.RAM_Warning) { [void]$issues.Add('RAM_HIGH') }

    if ($cpu -ge $cfg.Thresholds.CPU_Critical) { [void]$issues.Add('CPU_CRITICAL') }
    elseif ($cpu -ge $cfg.Thresholds.CPU_Warning) { [void]$issues.Add('CPU_HIGH') }

    if ($virt -and $virt.Available -and ($virt.Enabled -eq $false)) {
        [void]$issues.Add('VIRTUALIZATION_DISABLED')
    }

    if (-not $admin) { [void]$issues.Add('NOT_ADMIN') }

    # Top non-protected memory consumers
    $culprits = @()
    if ($Snapshot.TopProcesses) {
        $culprits = @($Snapshot.TopProcesses | Where-Object { -not $_.Protected } | Select-Object -First 5)
    }
    $evidence.TopUserProcesses = $culprits

    $status = 'OK'
    if ($issues -contains 'RAM_CRITICAL' -or $issues -contains 'CPU_CRITICAL' -or $issues -contains 'VIRTUALIZATION_DISABLED') {
        $status = 'CRITICAL'
    } elseif ($issues.Count -gt 0) {
        $status = 'WARNING'
    }

    $action = 'NONE'
    if ($issues -contains 'RAM_CRITICAL' -or $issues -contains 'RAM_HIGH') {
        if ($culprits.Count -gt 0) { $action = 'CLEAN_RAM' } else { $action = 'MONITOR' }
    }

    return [pscustomobject]@{
        Doctor = 'Windows'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = $action
        Notes = "Uptime ${uptime}h | Admin=$admin"
    }
}
