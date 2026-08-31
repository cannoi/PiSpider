# Pi Node Spider

## Vision
Stable Pi Node on Windows — synced, reachable, ready for bonus.

## Mission
Central conductor reads the host, decides, and acts with minimal risk.

## Conductor (Orchestrator)
PiSpider.exe starts the Orchestrator (~60s):
**Machine data → Diagnose → Decide → Act (safe) → Verify**

Scan/Patrol require Conductor ON. If stopped, Spider tries auto-restart; if that fails, scan is blocked.

## Modes
- Conductor while Dashboard open (default ~60s)
- Scheduler tasks when window closed (optional 1 min Orchestrator task)

## Principle
Protect Node. Minimal intervention. Verify always.
