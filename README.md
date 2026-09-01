# PiSpider Hybrid Core (SoloHost)

Dashboard for PiSpider on SoloHost. Windows Worker stays on the Node PC.

## First-run flow

The dashboard intentionally uses a simple three-stage flow:

1. **Terms** — explains that PiSpider has a SoloHost dashboard and a Windows Worker.
2. **Worker setup** — gives several Windows start methods (double-click, PowerShell, CMD, fallback `.bat`).
3. **Verification** — waits for a fresh Worker heartbeat before opening the normal PiSpider dashboard.

SoloHost does **not** attempt to launch a Windows PowerShell process from inside its container. This avoids a false "installed/started" state and makes the final verification real.

See `ONBOARDING.md` for the same instructions in text form.

## Publish

```bash
git init
git add .
git commit -m "PiSpider Hybrid Core 1.0.0"
git branch -M main
git remote add origin https://github.com/YOUR_ORG/pispider-hybrid-core.git
git push -u origin main
```

GitHub Actions builds `ghcr.io/YOUR_ORG/pispider-hybrid-core:latest`.

In SoloHost `docker-compose.yml` and `config.json`, replace `YOUR_ORG`.

## Local image build

```bash
docker build -t pispider-hybrid-core:1.0.0 .
```

## Run (the 2 SoloHost files)

```bash
docker compose up -d
# http://SOLOHOST_IP:18770
```

## Windows Worker discovery and SoloHost channel

The Windows launcher automatically searches `%APPDATA%\Pi Network\pi-apps\` for `WindowsWorker\LiveWorker.ps1`; users do not need to type their Windows username or application folder name.

If downloaded separately, extract the ZIP **contents into the target app's `WindowsWorker\` folder**. The required final file is `%APPDATA%\Pi Network\pi-apps\<PiSpider app folder>\WindowsWorker\LiveWorker.ps1`.

`LiveWorker.ps1` has a global single-instance mutex, so a second launch exits safely instead of creating a competing command consumer.

When the packaged canonical SoloHost compose differs from the app's `docker-compose.yml`, the Worker creates a timestamped backup, replaces the compose file with the canonical communication configuration, writes a restart request into `Data\live`, and attempts `docker compose stop pispider-core` followed by `docker compose up -d --force-recreate pispider-core`. It does not restart anything when the compose is already synchronized.
