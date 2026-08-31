#Requires -Version 5.1
$ErrorActionPreference='SilentlyContinue'
$name='PiNodeSpider_Startup'
Write-Host ""
Write-Host "[SPIDER] Startup Task Status" -ForegroundColor Cyan
Write-Host "===================================="
$t=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
if(-not $t){ Write-Host "  $name : NOT INSTALLED" -ForegroundColor Yellow }
else {
  $i=Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue
  Write-Host "  $name" -ForegroundColor White
  Write-Host "    State      : $($t.State)"
  Write-Host "    LastRun    : $($i.LastRunTime)"
  Write-Host "    LastResult : $($i.LastTaskResult)"
  Write-Host "    NextRun    : $($i.NextRunTime)"
}
Write-Host ""
Write-Host "Only this Task Scheduler entry is supported by PiNode Spider." -ForegroundColor Green
Write-Host "Watch/Patrol/DailyReport are no longer scheduled tasks; they run from the active PiSpider app." -ForegroundColor Gray
Write-Host ""
