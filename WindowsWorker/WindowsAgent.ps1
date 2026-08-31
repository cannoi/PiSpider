#Requires -Version 5.1
# Whitelist agent: SoloHost POST /api/run {script:scan|repair|status|patrol|digest|worker}
[CmdletBinding()]
param([int]$PollSeconds = 8)

$ErrorActionPreference = 'Continue'
$script:SpiderRoot = $PSScriptRoot
$env:PINODE_SPIDER_ROOT = $script:SpiderRoot
. (Join-Path $script:SpiderRoot 'Engine\LiveBus.ps1')

$Whitelist = @{
    scan    = @{ File = 'PiNodeSpider.ps1'; Args = @('-Command','Scan','-Quiet') }
    repair  = @{ File = 'PiNodeSpider.ps1'; Args = @('-Command','Repair','-Quiet') }
    status  = @{ File = 'PiNodeSpider.ps1'; Args = @('-Command','Status','-Quiet') }
    patrol  = @{ File = 'PiNodeSpider.ps1'; Args = @('-Command','Patrol','-Quiet') }
    digest  = @{ File = 'PiNodeSpider.ps1'; Args = @('-Command','DailyReport','-Quiet') }
    worker  = @{ File = 'LiveWorker.ps1';   Args = @() }
}

Write-Host "[AGENT] root=$script:SpiderRoot bus=$(Get-SpiderLiveBusDir)"
Write-SpiderLiveHeartbeat -Busy $false -Note 'agent-idle'
$lastId = ''

while ($true) {
    try {
        Write-SpiderLiveHeartbeat -Busy $false -Note 'agent-idle'
        $cmd = Read-SpiderLiveCommand
        if ($cmd -and $cmd.Id -and $cmd.Id -ne $lastId) {
            $key = ''
            if ($cmd.PSObject.Properties['Script'] -and $cmd.Script) { $key = [string]$cmd.Script }
            elseif ($cmd.Action) { $key = [string]$cmd.Action }
            $key = $key.ToLower()
            if (-not $Whitelist.ContainsKey($key)) {
                Write-SpiderLiveResult -Action $key -Status 'SKIP' -Summary 'not in whitelist'
                Clear-SpiderLiveCommand
                $lastId = [string]$cmd.Id
            } else {
                $spec = $Whitelist[$key]
                $file = Join-Path $script:SpiderRoot $spec.File
                Write-SpiderLiveHeartbeat -Busy $true -Note $key
                $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $file) + @($spec.Args)
                $p = Start-Process -FilePath $ps -ArgumentList $arg -WorkingDirectory $script:SpiderRoot -Wait -PassThru -WindowStyle Hidden
                $code = 0; try { $code = [int]$p.ExitCode } catch {}
                Write-SpiderLiveResult -Action $key.ToUpper() -Status $(if ($code -eq 0) {'OK'} else {'FAIL'}) -Summary "exit=$code"
                Clear-SpiderLiveCommand
                $lastId = [string]$cmd.Id
                Write-SpiderLiveHeartbeat -Busy $false -Note 'agent-idle'
            }
        }
    } catch {
        Write-Host "[AGENT] $($_.Exception.Message)"
    }
    Start-Sleep -Seconds ([Math]::Max(5, $PollSeconds))
}
