#Requires -Version 5.1
function Get-SpiderLiveBusDir {
    $root = $script:SpiderRoot
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $env:PINODE_SPIDER_ROOT }
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $PSScriptRoot }
    if ($root -and (Split-Path -Leaf $root) -eq 'Engine') { $root = Split-Path -Parent $root }
    $dir = Join-Path $root 'Data\live'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-SpiderLiveBusDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    $main = Get-SpiderLiveBusDir
    [void]$dirs.Add($main)
    $root = $script:SpiderRoot
    if ($root -and (Split-Path -Leaf $root) -eq 'Engine') { $root = Split-Path -Parent $root }
    if ($root) {
        $parent = Split-Path -Parent $root
        foreach ($extra in @((Join-Path $parent 'data\live'), (Join-Path $parent 'Data\live'))) {
            try {
                if (-not (Test-Path -LiteralPath $extra)) { New-Item -ItemType Directory -Path $extra -Force | Out-Null }
                if (-not $dirs.Contains($extra)) { [void]$dirs.Add($extra) }
            } catch {}
        }
    }
    return $dirs
}

function Write-SpiderLiveJson {
    param([string]$Name, $Object)
    $json = $Object | ConvertTo-Json -Depth 8
    foreach ($dir in (Get-SpiderLiveBusDirs)) {
        $path = Join-Path $dir $Name
        $tmp = $path + '.tmp'
        try {
            $json | Set-Content -LiteralPath $tmp -Encoding UTF8
            Move-Item -LiteralPath $tmp -Destination $path -Force
        } catch {}
    }
}

function Read-SpiderLiveJson {
    param([string]$Name)
    foreach ($dir in (Get-SpiderLiveBusDirs)) {
        $path = Join-Path $dir $Name
        if (Test-Path -LiteralPath $path) {
            try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
        }
    }
    return $null
}

function Write-SpiderLiveHeartbeat {
    param([bool]$Busy = $false, [string]$Note = '')
    Write-SpiderLiveJson -Name 'heartbeat.json' -Object ([ordered]@{
        Alive = $true
        Busy = $Busy
        At = (Get-Date).ToString('o')
        Pack = 'windows-worker'
        Note = $Note
        Pid = $PID
    })
}

function Read-SpiderLiveCommand {
    return (Read-SpiderLiveJson -Name 'command.json')
}

function Clear-SpiderLiveCommand {
    foreach ($dir in (Get-SpiderLiveBusDirs)) {
        $path = Join-Path $dir 'command.json'
        $last = Join-Path $dir 'command.last.json'
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            if (Test-Path -LiteralPath $last) { Remove-Item -LiteralPath $last -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $path -Destination $last -Force
        } catch {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-SpiderLiveResult {
    param([string]$Action, [string]$Summary = '', $Health = $null, [string]$Status = 'OK')
    Write-SpiderLiveJson -Name 'result.json' -Object ([ordered]@{
        Action = $Action
        Status = $Status
        Summary = $Summary
        Health = $Health
        At = (Get-Date).ToString('o')
    })
}

function Sync-SpiderLiveApproval {
    $root = $script:SpiderRoot
    if (-not $root) { $root = $env:PINODE_SPIDER_ROOT }
    if (-not $root) { return }
    $src = Join-Path $root 'Data\pending_approval.json'
    if (Test-Path -LiteralPath $src) {
        foreach ($dir in (Get-SpiderLiveBusDirs)) {
            try { Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'pending_approval.json') -Force } catch {}
        }
    }
}
