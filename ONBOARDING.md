# PiSpider Hybrid — User Setup

PiSpider has two parts:

1. **SoloHost** — the web dashboard.
2. **Windows Worker** — PowerShell running on the Windows PC that hosts Pi Node/Docker.

## First run

Open the SoloHost dashboard. Accept the terms. The dashboard then shows the Windows Worker setup screen.

### Easiest

Open the PiSpider SoloHost application folder on Windows and double-click:

`Start-Worker.cmd`

### PowerShell

From the SoloHost application folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\WindowsWorker\LiveWorker.ps1"
```

### CMD

From the SoloHost application folder:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WindowsWorker\LiveWorker.ps1"
```

### Fallback

Run `WindowsWorker\Activate_Worker.bat`.

## Verify

Return to the dashboard and press **CHECK WORKER**.

The dashboard considers the Worker installed only after it receives a fresh heartbeat. A green **WORKER VERIFIED** result opens the normal dashboard.

If verification fails:

- keep the Worker PowerShell window open;
- wait 5–15 seconds;
- make sure the Worker is under the same SoloHost application folder;
- retry the check;
- do not run two Worker processes at once.

## Important architecture rule

SoloHost runs in a container and cannot directly launch a Windows PowerShell process. The browser therefore does **not** pretend that a Worker was started. The user starts it on Windows, and SoloHost verifies it through the shared live bus.

The dashboard does not expose arbitrary command execution. Commands sent to the Worker remain whitelisted.
