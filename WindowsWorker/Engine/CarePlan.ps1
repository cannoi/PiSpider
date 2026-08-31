#Requires -Version 5.1
# ============================================================
# Engine/CarePlan.ps1 — Smart proactive caretaker (community + AI)
# Not only CleanRAM: disk, ports, DNS, weekly light care, advisories
# NEVER: remove blockchain data, Docker purge, blind WSL kill
# ============================================================

function Get-SpiderCareStatePath {
    if (-not $script:SpiderRoot) { return $null }
    return (Join-Path $script:SpiderRoot 'Data\care_state.json')
}
function Get-SpiderCareActivityPath {
    if (-not $script:SpiderRoot) { return $null }
    return (Join-Path $script:SpiderRoot 'Data\care_activity.json')
}

function Get-SpiderCareState {
    $path = Get-SpiderCareStatePath
    $st = [ordered]@{
        LastCareAt = $null; LastCareKind = $null; LastCareResult = $null
        LastWeeklyAt = $null; CareCountToday = 0; CareDay = $null
        LastDiskAlertAt = $null; LastPortCheckAt = $null; LastDnsAt = $null
        LastPowerAdvisoryAt = $null; Notes = @()
    }
    if ($path -and (Test-Path -LiteralPath $path)) {
        try {
            $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($st.Keys)) {
                if ($j.PSObject.Properties[$k]) { $st[$k] = $j.$k }
            }
        } catch {}
    }
    return [pscustomobject]$st
}

function Save-SpiderCareState {
    param($State)
    $path = Get-SpiderCareStatePath
    if (-not $path) { return }
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    try { ($State | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8 } catch {}
}

function Write-SpiderCareActivity {
    param([string]$Title, [string]$Purpose, [string]$Result = 'OK', [string]$Kind = 'care')
    $path = Get-SpiderCareActivityPath
    if (-not $path) { return }
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $entry = [ordered]@{
        At = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Kind = $Kind; Title = $Title; Purpose = $Purpose; Result = $Result
    }
    $list = @()
    if (Test-Path -LiteralPath $path) {
        try {
            $prev = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($prev) { $list = @($prev) }
        } catch {}
    }
    $list = @([pscustomobject]$entry) + @($list) | Select-Object -First 50
    try { ($list | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8 } catch {}
}

function Test-SpiderCareAllowed {
    param($Snapshot, $Decision)
    if ($Decision -and $Decision.Action -and $Decision.Action -notin @('NONE','WAIT_MONITOR','MONITOR','REPORT')) {
        return $false
    }
    if ($Snapshot -and $Snapshot.Memory -and $Snapshot.Memory.UsedPct -ge 92) { return $false }
    if ($Snapshot -and $Snapshot.Stellar -and $Snapshot.Stellar.Synced -eq $false) { return $false }
    return $true
}

function Get-SpiderMinutesSince {
    param([string]$Iso)
    if (-not $Iso) { return 99999 }
    try { return [int]((Get-Date) - [datetime]::Parse($Iso)).TotalMinutes } catch { return 99999 }
}

function Invoke-SpiderCareDiskGuard {
    param($Snapshot)
    $free = $null; $pct = $null
    if ($Snapshot -and $Snapshot.Disk) {
        $free = $Snapshot.Disk.FreeGB
        $pct = $Snapshot.Disk.FreePct
    }
    $alert = $false
    if ($null -ne $free -and [double]$free -lt 25) { $alert = $true }
    if ($null -ne $pct -and [double]$pct -lt 12) { $alert = $true }
    if (-not $alert) {
        return [pscustomobject]@{ Ran = $false; Result = 'OK_SPACE' }
    }
    $msg = "LOW DISK: Free=${free}GB (${pct}%). Community tip: blockchain data grows under Pi Network docker_volumes — free space or move data (manual). Spider will NOT delete chain data."
    Write-SpiderLog $msg 'CARE'
    Write-SpiderCareActivity -Title 'DISK_GUARD' -Purpose $msg -Result 'ALERT' -Kind 'guard'
    return [pscustomobject]@{ Ran = $true; Result = 'ALERT'; Purpose = $msg }
}

function Invoke-SpiderCarePortPulse {
    param($Snapshot)
    $ports = $null
    if ($Snapshot -and $Snapshot.Ports -and $Snapshot.Ports.Ports) { $ports = $Snapshot.Ports.Ports }
    $need = @('31401','31402','31403')
    $missing = @()
    foreach ($p in $need) {
        $ok = $false
        try {
            if ($ports -and $ports.PSObject.Properties[$p]) { $ok = [bool]$ports.$p }
        } catch {}
        if (-not $ok) { $missing += $p }
    }
    $ctnUp = $true
    if ($Snapshot -and $Snapshot.Docker) { $ctnUp = [bool]$Snapshot.Docker.PiRunning }
    if ($missing.Count -eq 0) {
        return [pscustomobject]@{ Ran = $false; Result = 'PORTS_OK' }
    }
    if (-not $ctnUp) {
        return [pscustomobject]@{ Ran = $false; Result = 'SKIP_CTN_DOWN' }
    }
    $purpose = "Ports missing: $($missing -join ', '). Check firewall / Pi Desktop. Optional safe action: FirewallCheck."
    $result = 'WARN'
    try {
        if (Get-Command Invoke-SpiderAction -EA SilentlyContinue) {
            Invoke-SpiderAction -ActionName 'FIREWALL_CHECK' -Snapshot $Snapshot -UserApproved:$true | Out-Null
            $result = 'FIREWALL_CHECK'
        }
    } catch {}
    Write-SpiderCareActivity -Title 'PORT_PULSE' -Purpose $purpose -Result $result -Kind 'guard'
    return [pscustomobject]@{ Ran = $true; Result = $result; Purpose = $purpose }
}

function Invoke-SpiderCareDns {
    param($Snapshot)
    try {
        if (Get-Command Invoke-SpiderAction -EA SilentlyContinue) {
            Invoke-SpiderAction -ActionName 'DNSREFRESH' -Snapshot $Snapshot -UserApproved:$true | Out-Null
            Write-SpiderCareActivity -Title 'DNS_REFRESH' -Purpose 'Refresh DNS so history/peers resolve reliably' -Result 'OK' -Kind 'care'
            return [pscustomobject]@{ Ran = $true; Result = 'OK' }
        }
    } catch {}
    try {
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-SpiderCareActivity -Title 'DNS_REFRESH' -Purpose 'Clear-DnsClientCache' -Result 'OK' -Kind 'care'
        return [pscustomobject]@{ Ran = $true; Result = 'OK' }
    } catch {
        return [pscustomobject]@{ Ran = $false; Result = 'FAIL' }
    }
}

function Invoke-SpiderCarePowerAdvisory {
    # Advisory only — do not change power policy without user
    $purpose = 'Ensure Windows Sleep/Hibernate = Never while plugged in so Node stays online (community standard).'
    $result = 'ADVISORY'
    try {
        $scheme = powercfg /getactivescheme 2>$null
        $purpose = "$purpose Active: $scheme"
    } catch {}
    Write-SpiderCareActivity -Title 'POWER_ADVISORY' -Purpose $purpose -Result $result -Kind 'advisory'
    return [pscustomobject]@{ Ran = $true; Result = $result; Purpose = $purpose }
}

function Select-SpiderCareCandidate {
    param($Snapshot, $Decision, $Health, $State)
    $candidates = New-Object System.Collections.Generic.List[object]

    # Priority order from community failure modes
    $disk = Invoke-SpiderCareDiskGuard -Snapshot $Snapshot
    if ($disk.Ran) {
        return [pscustomobject]@{ Id = 'DISK_GUARD'; Priority = 100; AlreadyRan = $true; Detail = $disk }
    }

    $minDns = Get-SpiderMinutesSince $State.LastDnsAt
    $minPort = Get-SpiderMinutesSince $State.LastPortCheckAt
    $minWeekly = Get-SpiderMinutesSince $State.LastWeeklyAt
    $minPower = Get-SpiderMinutesSince $State.LastPowerAdvisoryAt
    $minCare = Get-SpiderMinutesSince $State.LastCareAt

    if ($minPort -gt 180) {
        $candidates.Add([pscustomobject]@{ Id = 'PORT_PULSE'; Priority = 90; Score = 90 })
    }
    $ram = 0
    if ($Snapshot -and $Snapshot.Memory) { $ram = [double]$Snapshot.Memory.UsedPct }
    if ($ram -ge 82 -and $minCare -gt 60) {
        $candidates.Add([pscustomobject]@{ Id = 'RAM_PRESSURE'; Priority = 80; Score = 80 + ($ram - 82) })
    }
    if ($minDns -gt 360) {
        $candidates.Add([pscustomobject]@{ Id = 'DNS_REFRESH'; Priority = 70; Score = 70 })
    }
    if ($minCare -gt 120) {
        $candidates.Add([pscustomobject]@{ Id = 'TEMP_HOUSEKEEP'; Priority = 50; Score = 50 })
    }
    if ($minWeekly -gt (7 * 24 * 60)) {
        $candidates.Add([pscustomobject]@{ Id = 'WEEKLY_LIGHT'; Priority = 60; Score = 60 })
    }
    if ($minPower -gt (7 * 24 * 60)) {
        $candidates.Add([pscustomobject]@{ Id = 'POWER_ADVISORY'; Priority = 40; Score = 40 })
    }

    if ($candidates.Count -eq 0) { return $null }

    # Optional AI advisory boost (never overrides safety)
    $pick = $candidates | Sort-Object Priority -Descending | Select-Object -First 1
    try {
        if (Get-Command Invoke-SpiderAI -EA SilentlyContinue) {
            $hint = "Pick one care id from: $(($candidates | ForEach-Object { $_.Id }) -join ', ') given RAM=$ram"
            # AI is advisory — we keep rule pick; log only
            Write-SpiderLog "Care AI hint context: $hint (rule pick=$($pick.Id))" 'CARE'
        }
    } catch {}
    return $pick
}

function Invoke-SpiderProactiveCare {
    param($Snapshot, $Decision, $Health)

    $st = Get-SpiderCareState
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($st.CareDay -ne $today) {
        $st | Add-Member CareDay $today -Force
        $st | Add-Member CareCountToday 0 -Force
    }

    $cfgMax = 6
    try {
        if (Get-Command Get-SpiderConfig -EA SilentlyContinue) {
            $cfg = Get-SpiderConfig
            if ($cfg.Care -and $cfg.Care.MaxPerDay) { $cfgMax = [int]$cfg.Care.MaxPerDay }
        }
    } catch {}

    # Disk guard always allowed (alert only)
    $disk = Invoke-SpiderCareDiskGuard -Snapshot $Snapshot
    if ($disk.Ran) {
        $st | Add-Member LastDiskAlertAt ((Get-Date).ToString('o')) -Force
        Save-SpiderCareState $st
        return [pscustomobject]@{ DidCare = $true; Kind = 'DISK_GUARD'; Result = $disk.Result; Purpose = $disk.Purpose }
    }

    if (-not (Test-SpiderCareAllowed -Snapshot $Snapshot -Decision $Decision)) {
        Write-SpiderCareActivity -Title 'Care deferred' -Purpose 'Node busy / catching up / repair — protect first (community: wait before reset)' -Result 'DEFER' -Kind 'protect'
        return [pscustomobject]@{ DidCare = $false; Reason = 'not_allowed' }
    }
    if ([int]$st.CareCountToday -ge $cfgMax) {
        Write-SpiderCareActivity -Title 'Care budget' -Purpose "Max $cfgMax cares/day" -Result 'SKIP' -Kind 'limit'
        return [pscustomobject]@{ DidCare = $false; Reason = 'budget' }
    }

    $pick = Select-SpiderCareCandidate -Snapshot $Snapshot -Decision $Decision -Health $Health -State $st
    if (-not $pick) {
        return [pscustomobject]@{ DidCare = $false; Reason = 'nothing_due' }
    }

    $kind = $pick.Id
    $purpose = ''
    $result = 'OK'
    $ran = $false

    switch ($kind) {
        'PORT_PULSE' {
            $r = Invoke-SpiderCarePortPulse -Snapshot $Snapshot
            $ran = $r.Ran; $result = $r.Result; $purpose = $r.Purpose
            $st | Add-Member LastPortCheckAt ((Get-Date).ToString('o')) -Force
        }
        'DNS_REFRESH' {
            $r = Invoke-SpiderCareDns -Snapshot $Snapshot
            $ran = $r.Ran; $result = $r.Result
            $purpose = 'DNS refresh for archive/peers'
            $st | Add-Member LastDnsAt ((Get-Date).ToString('o')) -Force
        }
        'RAM_PRESSURE' {
            $purpose = 'Trim user memory pressure; Node volumes untouched'
            try {
                if (Get-Command Invoke-SpiderAction -EA SilentlyContinue) {
                    Invoke-SpiderAction -ActionName 'CLEANRAM' -Snapshot $Snapshot -UserApproved:$true | Out-Null
                    $ran = $true
                }
            } catch { $result = 'FAIL' }
        }
        'TEMP_HOUSEKEEP' {
            $purpose = 'Clear old user temp files only'
            try {
                if (Get-Command Invoke-SpiderAction -EA SilentlyContinue) {
                    Invoke-SpiderAction -ActionName 'CLEANTEMP' -Snapshot $Snapshot -UserApproved:$true | Out-Null
                    $ran = $true
                } else {
                    $temp = [IO.Path]::GetTempPath(); $n = 0
                    Get-ChildItem $temp -File -EA SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) -and $_.Length -lt 20MB } |
                        Select-Object -First 40 | ForEach-Object { try { Remove-Item $_.FullName -Force -EA SilentlyContinue; $n++ } catch {} }
                    $result = "removed~$n"; $ran = $true
                }
            } catch { $result = 'FAIL' }
        }
        'WEEKLY_LIGHT' {
            $purpose = 'Weekly light maintenance (community cadence) — no chain wipe'
            try {
                if (Get-Command Invoke-SpiderAction -EA SilentlyContinue) {
                    Invoke-SpiderAction -ActionName 'MAINTENANCE_LIGHT' -Snapshot $Snapshot -UserApproved:$true | Out-Null
                    $ran = $true
                } else {
                    $ran = $true; $result = 'NO_ACTION_MODULE'
                }
            } catch { $result = 'FAIL' }
            $st | Add-Member LastWeeklyAt ((Get-Date).ToString('o')) -Force
        }
        'POWER_ADVISORY' {
            $r = Invoke-SpiderCarePowerAdvisory
            $ran = $r.Ran; $result = $r.Result; $purpose = $r.Purpose
            $st | Add-Member LastPowerAdvisoryAt ((Get-Date).ToString('o')) -Force
        }
        default {
            return [pscustomobject]@{ DidCare = $false; Reason = "unknown $kind" }
        }
    }

    if ($ran) {
        $st | Add-Member LastCareAt ((Get-Date).ToString('o')) -Force
        $st | Add-Member LastCareKind $kind -Force
        $st | Add-Member LastCareResult $result -Force
        $st | Add-Member CareCountToday ([int]$st.CareCountToday + 1) -Force
        Save-SpiderCareState $st
        if ($kind -notin @('PORT_PULSE','DNS_REFRESH','POWER_ADVISORY')) {
            Write-SpiderCareActivity -Title $kind -Purpose $purpose -Result $result -Kind 'care'
        }
        Write-SpiderLog "Proactive care: $kind ($result) — $purpose" 'CARE'
        return [pscustomobject]@{ DidCare = $true; Kind = $kind; Result = $result; Purpose = $purpose }
    }
    return [pscustomobject]@{ DidCare = $false; Reason = 'no_op'; Kind = $kind }
}

function Get-SpiderCareMissionText {
    return @(
        'MISSION: Proactive caretaker for Pi Node (community-informed).',
        '• Disk guard — warn before Docker breaks (never wipe chain)',
        '• Port pulse — 31401/02/03',
        '• DNS refresh — history & peers',
        '• RAM/temp light care when healthy',
        '• Weekly light maintenance',
        '• Power advisory (Sleep=Never)',
        '• When Catching up: WAIT — do not reset storm'
    ) -join "`r`n"
}
