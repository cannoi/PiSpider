# PiSpider — Autonomous Pi Node Guardian (Windows)

**One app. One runner. Protect your Pi Node.**

---

## What is PiSpider?

PiSpider is a **Windows control and recovery system** for **Pi Node (Pi Desktop)**.

It watches the full stack that your Node depends on:

- Windows host (RAM, disk, CPU)
- WSL / Docker
- Pi Node container (`testnet2` / mainnet)
- Network ports (31401–31403)
- Ledger sync state (when readable)

Then it **decides the smallest safe action** — or waits — so the Node stays stable for bonus and uptime.

You do **not** need to be a Docker expert. Open **PiSpider.exe** and let the Conductor run.

---

## Who is it for?

- Operators running **Pi Desktop on Windows**
- Users who want **clear status** and **safe auto-care**
- Anyone tired of manual reset / WSL chaos when the Node lags

---

## Vision & mission

| | |
|--|--|
| **Vision** | A stable, synced Pi Node on every Windows host — ready for work and bonus. |
| **Mission** | Observe → diagnose → act with **minimal risk** → always verify. |
| **Principle** | Protect the Node first. Never “restart everything” by default. |

---

## Single runner

| File | Role |
|------|------|
| **`PiSpider.exe`** | **Only program you start** — Conductor + control panel |
| `Dashboard/PiSpiderHost.ps1` | Loads Orchestrator then UI |
| `PiNodeSpider.ps1` | Scan / Patrol / Repair engine (called by Conductor) |

There is **no separate Orchestrator app**.

---

## What it does (simple)

1. **Every ~60 seconds** (while PiSpider is open): read host + Node status  
2. **5-layer Node check** (fast path every tick; heavy checks on Patrol):
   - L1 Container running?
   - L2 Consensus / sync (stellar-core or logs)
   - L3 Ports open?
   - L4 CPU/RAM of container (Patrol)
   - L5 Data volume sample (Patrol)
3. **Decide**: wait, restart **only the Node container**, or ask you to Approve  
4. **Evening digest** (optional Telegram, ~19:15) — short summary, not spam every scan  
5. **Schedule** (optional): Windows tasks so care continues if you close the window  

---

## How to start (simple)

1. Open **PiSpider.exe**
2. Press **START CARE** once
3. Read the panel: **NOW / DONE / NEXT** and Node snapshot
4. Optional: **Show settings** for Telegram / AI key

## How to start

1. Unzip into a folder (e.g. `Desktop\PiNodeSpider`)
2. If needed once: run `Build_PiSpider_EXE.bat` to create `PiSpider.exe`
3. Double-click **`PiSpider.exe`**
4. Confirm **Conductor: ON**
5. Optional: **Schedule** button → background Watch / Patrol / Daily report / Orchestrator

---

## Auto modes (panel)

| Mode | Meaning |
|------|---------|
| Manual | Buttons only |
| In-app auto | Loops while the window is open |
| Scheduler auto | Windows Task Scheduler (can close the UI) |

---

## Safety

- High-risk steps need **Approve** (depending on mode)
- Recovery order: **container → soft Docker → ordered WSL → reboot last**
- Secrets (bot token / API key) stored with **Windows DPAPI**, not plain text in reports

---

## Telegram (optional, one-way)

Configure in the panel:

- Bot token + chat id  
- Daily digest ~19:00–20:00  
- Notify when approval is needed  

PiSpider does **not** replace Telegram Controller; it can notify you independently.

---

## Requirements

- Windows 10/11  
- PowerShell 5.1+  
- Docker Desktop + Pi Node container  
- PiSpider folder kept together (do not move only the `.exe`)

---

## Privacy & independence

- Runs **locally** on your PC  
- Does **not** depend on Controller MonitorLive to work  
- Optional: Telegram outbound HTTPS only  

---

## Support files

| Path | Purpose |
|------|---------|
| `ABOUT.md` | Short vision text |
| `Engine/CONDUCTOR.md` | Conductor / bus protocol |
| `Engine/TELEMETRY_SYNC_NOTES.md` | 5-layer status notes |
| `Data/node_status_latest.json` | Last Node snapshot |
| `Data/last_report.json` | Last full report |
| `Logs/` | Application logs |

---

## Version

See `VERSION` in the package root.

**Protect the Node. Minimal intervention. Verify always.**
