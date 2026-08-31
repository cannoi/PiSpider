# ============================================================
# Engine/Verify.ps1
# ============================================================

function Invoke-Verify {
    param($BeforeSnapshot, $ActionResult, $Decision)
    Write-SpiderLog "=== VERIFY START ===" 'INFO'
    Start-Sleep -Seconds 3
    $after = Invoke-FullCollect
    $health = Get-HealthScore $after
    $improved = $false
    $stillCritical = $false
    $details = @()

    switch ($Decision.Action) {
        'CLEAN_RAM' {
            $beforeRAM = $BeforeSnapshot.Memory.UsedPct
            $afterRAM = $after.Memory.UsedPct
            $improved = ($afterRAM -lt $beforeRAM - 3)
            $details += "RAM: $beforeRAM% → $afterRAM%"
            if ($afterRAM -ge (Get-SpiderConfig).Thresholds.RAM_Critical) { $stillCritical = $true }
        }
        'NETWORK_REPAIR' {
            $improved = $after.Network.Internet
            $details += "Internet: $($after.Network.Internet) IP=$($after.Network.IP)"
            if (-not $after.Network.Internet) { $stillCritical = $true }
        }
        'CLEAN_TEMP' {
            $improved = ($after.Disk.FreeGB -gt $BeforeSnapshot.Disk.FreeGB)
            $details += "Disk Free: $($BeforeSnapshot.Disk.FreeGB)GB → $($after.Disk.FreeGB)GB"
        }
        'RESTART_DOCKER' {
            $improved = ($after.Docker.EngineHealthy -eq $true)
            $details += "Docker Engine: $($after.Docker.EngineHealthy)"
            if (-not $improved) { $stillCritical = $true }
        }
        'RESTART_NODE' {
            $improved = $after.Docker.PiRunning
            $details += "Pi Running: $($after.Docker.PiRunning)"
            if (-not $improved) { $stillCritical = $true }
        }
        default {
            $improved = ($health.Overall -ge 70)
            $details += "Overall Health: $($health.Overall)/100 ($($health.Level))"
        }
    }
    $nodeStillOK = $after.NodeHealthy
    $details += "Pi Node Healthy: $nodeStillOK"
    $result = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Action = $Decision.Action
        Improved = $improved
        StillCritical = $stillCritical
        NodeProtected = $nodeStillOK
        HealthAfter = $health
        Details = $details
        SnapshotAfter = $after
        Success = ($improved -or ($Decision.Action -in @('MONITOR','WAIT_MONITOR','NONE','REPORT_CONFIG')))
    }
    Write-SpiderLog ("VERIFY: Improved={0} Critical={1} NodeOK={2} Health={3}" -f $result.Improved, $result.StillCritical, $result.NodeProtected, $health.Overall) 'INFO'
    Write-SpiderLog "=== VERIFY END ===" 'INFO'
    return $result
}
