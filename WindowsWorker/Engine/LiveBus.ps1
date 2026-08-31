#Requires -Version 5.1
# File bus between SoloHost Core and Windows Worker
function Get-SpiderLiveBusDir {
    $root = $script:SpiderRoot
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $env:PINODE_SPIDER_ROOT }
    if ([string]::IsNullOrWhiteSpace($root)) { $root = $PSScriptRoot }
    if ($root -and (Split-Path -Leaf $root) -eq 'Engine') { $root = Split-Path -Parent $root }
    $dir = Join-Path $root 'Data\live'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Write-SpiderLiveJson {
    param([string]$Name, $Object)
    $dir = Get-SpiderLiveBusDir
    $path = Join-Path $dir $Name
    $tmp = $path + '.tmp'
    ($Object | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Read-SpiderLiveJson {
    param([string]$Name)
    $path = Join-Path (Get-SpiderLiveBusDir) $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
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
    $path = Join-Path (Get-SpiderLiveBusDir) 'command.json'
    if (Test-Path -LiteralPath $path) {
        try { Rename-Item -LiteralPath $path -NewName 'command.last.json' -Force } catch {
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
        try {
            Copy-Item -LiteralPath $src -Destination (Join-Path (Get-SpiderLiveBusDir) 'pending_approval.json') -Force
        } catch {}
    }
}
