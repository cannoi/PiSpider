#Requires -Version 5.1
# PiNode Spider: install ONLY the logon startup task. Removes all legacy Spider tasks first.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dash = Join-Path $Root 'Dashboard\SpiderDashboard.ps1'
$Exe = Join-Path $Root 'PiSpider.exe'
$Ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $Dash)) { throw "Missing Dashboard\SpiderDashboard.ps1" }
$names = @()
try {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'PiNodeSpider_*' }
    foreach($t in @($tasks)) {
        try { Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop; Write-Host "REMOVED $($t.TaskName)" } catch { Write-Host "REMOVE_FAILED $($t.TaskName): $($_.Exception.Message)" }
    }
} catch { Write-Host "TASK_ENUM_WARNING: $($_.Exception.Message)" }
$name='PiNodeSpider_Startup'
$target = if (Test-Path $Exe) { $Exe } else { $Ps }
if ($target -eq $Exe) {
    # Updated launcher builds forward -StartupLaunch to the dashboard.
    $arg = '-StartupLaunch'
    $action = New-ScheduledTaskAction -Execute $Exe -Argument $arg -WorkingDirectory $Root
} else {
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dash`" -StartupLaunch"
    $action = New-ScheduledTaskAction -Execute $Ps -Argument $arg -WorkingDirectory $Root
}
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'PiNode Spider: start the application at Windows logon. No scan/patrol schedule.' -Force | Out-Null
$state=[ordered]@{InstalledAt=(Get-Date).ToString('o'); Task=$name; Trigger='AtLogOn'; Target=$target; LegacyTasksRemoved=$true}
($state|ConvertTo-Json -Depth 5)|Set-Content (Join-Path $Root 'Data\scheduler_state.json') -Encoding UTF8
Write-Host "INSTALLED $name (AtLogOn)"
