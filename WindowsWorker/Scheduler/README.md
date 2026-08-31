# Scheduler

PiNode Spider intentionally uses **one Windows Task Scheduler entry only**:

- `PiNodeSpider_Startup` — starts PiSpider at Windows logon.
- Watch / Patrol / DailyReport are **not** installed as Windows scheduled tasks.
- The active PiSpider process controls its own background worker after `RUN`.

## Install

Use PiSpider → **RUN**. It automatically removes legacy `PiNodeSpider_*` tasks and installs the single startup task.

Manual install:

```powershell
.\Install_Startup_Task.ps1
```

The old `Install_Watch_Task.ps1` name remains only as a compatibility wrapper and now installs the startup task instead of Watch/Patrol schedules.

## Status

```powershell
.\Status_Watch_Task.ps1
```

## Remove

```powershell
.\Uninstall_Watch_Task.ps1
```

This removes all `PiNodeSpider_*` tasks.
