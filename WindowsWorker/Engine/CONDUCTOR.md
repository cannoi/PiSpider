# Conductor (single coordinator)

**PiSpider.exe** hosts the Orchestrator — the only central coordinator.

## File bus (sync)

`Data/conductor_bus.json` — shared status for Dashboard, CLI Scan/Patrol, Scheduler:

- ConductorAlive, LastTick, LastScanAt, LastPatrolAt
- Scheduler[] task install/state
- LastError / Message

## Rules

1. Scan/Patrol call `Assert-SpiderOrchestratorReady`
2. If offline → try mark worker → try start **PiSpider.exe** → wait heartbeat
3. If still offline → **block** + print how to fix
4. Closing Dashboard stops conductor **unless** `PiNodeSpider_Orchestrator` task exists

## User fix when blocked

1. Open `PiSpider.exe`
2. See **Conductor: ON**
3. Schedule → install tasks (background)
4. Retry Scan/Patrol
