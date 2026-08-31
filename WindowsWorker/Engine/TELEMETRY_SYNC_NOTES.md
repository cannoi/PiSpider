# 5-Layer Pi Node status (v2.3.16)

| Layer | What | When |
|-------|------|------|
| L1 | docker inspect State | Every tick (fast) |
| L2 | stellar-core info + host logs | Every tick |
| L3 | docker port + host listen | Every tick |
| L4 | docker stats | Patrol / IncludeSlow (deferred) |
| L5 | volume sample | Patrol / IncludeSlow (deferred) |

No temperature. No MonitorLive dependency.

Actions mapped:
- Container not running / OOM / paused → RESTART_NODE
- Catching up → WAIT_MONITOR or RESTART_NODE by age
- CPU high alone → WAIT_MONITOR
