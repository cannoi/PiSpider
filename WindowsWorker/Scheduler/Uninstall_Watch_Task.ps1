#Requires -Version 5.1
$ErrorActionPreference='Continue'
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'PiNodeSpider_*' } | ForEach-Object {
    try { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop; Write-Host "Removed $($_.TaskName)" } catch { Write-Warning $_.Exception.Message }
}
