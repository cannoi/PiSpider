#Requires -Version 5.1
# Legacy compatibility wrapper. The Spider no longer installs Watch/Patrol/DailyReport schedules.
& (Join-Path $PSScriptRoot 'Install_Startup_Task.ps1')
