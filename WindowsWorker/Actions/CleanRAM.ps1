# ============================================================
# Actions/CleanRAM.ps1 - SMART RAM cleanup (Risk: LOW)
# Chỉ kill CleanupCandidates, không đụng Protected Zone
# ============================================================
function Invoke-CleanRAM {
    param($Snapshot)
    Write-SpiderLog "ACTION: CLEAN_RAM" 'ACTION'
    $cfg = Get-SpiderConfig
    $minMB = if ($cfg.MinProcessMB_CleanRAM) { $cfg.MinProcessMB_CleanRAM } else { 500 }
    $maxKill = if ($cfg.MaxProcessesToKill) { $cfg.MaxProcessesToKill } else { 8 }
    $killed = @()
    $skipped = @()

    $candidates = @(
        Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessName -and
            (Test-CleanupCandidate $_.ProcessName) -and
            -not (Test-ProtectedProcess $_.ProcessName) -and
            $_.WorkingSet64 -ge ($minMB * 1MB)
        } |
        Sort-Object WorkingSet64 -Descending
    )

    foreach ($p in $candidates) {
        if ($killed.Count -ge $maxKill) { break }
        if (Test-ProtectedProcess $p.ProcessName) {
            $skipped += $p.ProcessName
            continue
        }
        if (-not (Assert-NotProtectedTarget -ProcessName $p.ProcessName)) {
            $skipped += $p.ProcessName
            continue
        }
        $mb = [math]::Round($p.WorkingSet64 / 1MB, 0)
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            $killed += "$($p.ProcessName)(${mb}MB)"
            Write-SpiderLog "TERMINATED: $($p.ProcessName) PID=$($p.Id) ${mb}MB" 'ACTION'
        } catch {
            Write-SpiderLog "Could not kill $($p.ProcessName) PID=$($p.Id)" 'WARN'
        }
    }

    # Light TEMP (files older than 6h only)
    $tempCount = 0
    try {
        Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-6) } |
            ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $tempCount++
                } catch {}
            }
    } catch {}

    try { cmd /c "ipconfig /flushdns" >$null 2>&1 } catch {}
    Start-Sleep -Seconds 2
    $after = Get-MemorySnapshot
    $beforePct = if ($Snapshot -and $Snapshot.Memory) { $Snapshot.Memory.UsedPct } else { $null }

    return [pscustomobject]@{
        Action      = 'CLEAN_RAM'
        Risk        = 'LOW'
        Killed      = $killed
        Skipped     = $skipped
        TempCleaned = $tempCount
        RAM_Before  = $beforePct
        RAM_After   = if ($after) { $after.UsedPct } else { $null }
        Success     = ($killed.Count -gt 0 -or $tempCount -gt 0)
    }
}
