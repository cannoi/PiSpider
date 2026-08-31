# ============================================================
# Doctors/Hardware.ps1 - Hardware / Virtualization Doctor
# READ-ONLY: CPU cores, RAM total, virtualization firmware
# Không bao giờ sửa BIOS/firmware
# ============================================================
function Invoke-HardwareDoctor {
    param($Snapshot)
    Write-SpiderLog "Doctor: Hardware" 'DIAG'
    $issues = [System.Collections.Generic.List[string]]::new()
    $evidence = [ordered]@{}

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $evidence.CPUName = $cpu.Name
        $evidence.Cores = $cpu.NumberOfCores
        $evidence.LogicalProcessors = $cpu.NumberOfLogicalProcessors
    } catch {}

    if ($Snapshot.Memory) {
        $evidence.TotalRAM_GB = $Snapshot.Memory.TotalGB
        # Soft advisory only if truly low AND measured TotalGB is sane (>0.5)
        if ($Snapshot.Memory.TotalGB -ge 0.5 -and $Snapshot.Memory.TotalGB -lt 8) {
            [void]$issues.Add('RAM_BELOW_8GB')
        }
    }

    $virt = $Snapshot.Virtualization
    if ($virt) {
        $evidence.VirtualizationEnabled = $virt.Enabled
        $evidence.FirmwareFlag = $virt.FirmwareFlag
        $evidence.HypervisorPresent = $virt.HypervisorPresent
        $evidence.DockerImpliesOK = $virt.DockerImpliesOK
        $evidence.Method = $virt.Method
        # CRITICAL only when Enabled is explicitly false AND no practical hypervisor evidence
        if ($virt.Enabled -eq $false) {
            [void]$issues.Add('VT_DISABLED_IN_BIOS')
        }
    }

    $status = 'OK'
    # VT false-negative is common; only CRITICAL if Enabled==false (not null)
    if ($issues -contains 'VT_DISABLED_IN_BIOS') { $status = 'CRITICAL' }
    elseif ($issues -contains 'RAM_BELOW_8GB') { $status = 'WARNING' }
    elseif ($issues.Count -gt 0) { $status = 'WARNING' }

    return [pscustomobject]@{
        Doctor = 'Hardware'
        Status = $status
        Issues = @($issues)
        Evidence = [pscustomobject]$evidence
        RecommendedAction = 'NONE'  # never auto-fix BIOS
        Notes = 'READ-ONLY - enable VT-x/AMD-V in BIOS manually if disabled'
    }
}
