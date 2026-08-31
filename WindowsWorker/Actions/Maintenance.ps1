# ============================================================
# Actions/Maintenance.ps1 - Light weekly-style maintenance (Risk: LOW)
# From Weekly_Maintenance.ps1 - safe subset
# ============================================================
function Invoke-MaintenanceLight {
    Write-SpiderLog "ACTION: MAINTENANCE_LIGHT" 'ACTION'
    $isAdmin = Test-IsAdmin
    $steps = [System.Collections.Generic.List[string]]::new()

    # Time sync
    try {
        cmd /c "w32tm /resync" >$null 2>&1
        [void]$steps.Add('time_sync')
    } catch {}

    # Junk apps (safe list only, never protected)
    foreach ($n in @('chrome','msedge','OneDrive','Copilot','SearchApp','SearchIndexer','TabTip','TextInputHost')) {
        if (-not (Test-ProtectedProcess $n)) {
            Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    [void]$steps.Add('junk_trim')

    # TEMP
    if (Get-Command Invoke-CleanTemp -ErrorAction SilentlyContinue) {
        Invoke-CleanTemp | Out-Null
        [void]$steps.Add('clean_temp')
    }

    # DNS
    try {
        cmd /c "ipconfig /flushdns" >$null 2>&1
        [void]$steps.Add('dns')
    } catch {}

    # Anti-sleep (AC)
    if ($isAdmin) {
        foreach ($x in @('monitor-timeout-ac','standby-timeout-ac','hibernate-timeout-ac')) {
            cmd /c "powercfg /change $x 0" >$null 2>&1
        }
        [void]$steps.Add('anti_sleep')
    }

    # Docker Desktop priority
    try {
        Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue | ForEach-Object {
            $_.PriorityClass = 'AboveNormal'
        }
        [void]$steps.Add('docker_priority')
    } catch {}

    return [pscustomobject]@{
        Action  = 'MAINTENANCE_LIGHT'
        Risk    = 'LOW'
        Success = $true
        Steps   = @($steps)
    }
}
