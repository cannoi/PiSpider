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


## Automatic Windows path discovery

The Worker launcher searches under:

`%APPDATA%\Pi Network\pi-apps\`

and selects a `WindowsWorker\LiveWorker.ps1` installation. The user does not need to type the Windows username or Pi app folder name.

For a downloaded package, extract the ZIP contents into the target app's `WindowsWorker\` directory. The required final path is:

`%APPDATA%\Pi Network\pi-apps\<PiSpider app folder>\WindowsWorker\LiveWorker.ps1`

The Worker has a single-instance mutex. Starting it again does not create a second command consumer.

When the canonical SoloHost compose file differs, the Worker creates a timestamped `.pispider-backup-*` backup, synchronizes `docker-compose.yml`, writes a `Data\live\solohost_restart_request.json` event, then attempts `docker compose stop pispider-core` followed by `docker compose up -d --force-recreate pispider-core`. If Docker is unavailable, the synchronized compose remains in place and the user can start SoloHost normally.

## If PowerShell says `GetContentReaderUnauthorizedAccessError`

If the Worker prints `Access to ...\config.json is denied`, do not change Windows permissions.
Current Worker versions do not need to read that protected file. Replace the Worker package with the current package and start it again. The Worker uses the SoloHost localhost ports (18770, 18780) and can also use `PISPIDER_SOLOHOST_PORT` when explicitly configured.

## Windows Worker Dashboard

After `Start-Worker.cmd` or `Activate_Worker.bat`, the command window is hidden. A simple Windows dashboard opens and runs elevated through UAC. It shows Worker state, AUTO mode, current progress, SoloHost commands, results/errors and essential settings.

Do not close the dashboard if you want the normal operator view. The Worker itself continues in the background.
