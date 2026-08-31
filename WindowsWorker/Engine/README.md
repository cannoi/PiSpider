# Engine/ — Bộ não lõi PiNode Spider

| File | Vai trò |
|------|---------|
| **Core.ps1** | Config/Rules load, log, Protected Zone, Events, History, CircuitBreaker, Approval Console |
| **Safety.ps1** | Safety Policy gate trước mọi action nguy hiểm |
| **Telemetry.ps1** | Telemetry độc lập + enrich MonitorLive (tùy chọn) |
| **Discovery.ps1** | Thu thập snapshot + System Map + Baseline |
| **Dependency.ps1** | Spider Web dependency graph & redirect action |
| **Diagnostic.ps1** | Health Score 6 cấp + Root Cause Analysis |
| **Decision.ps1** | Autonomy mode + Risk + dependency-aware decision |
| **ActionEngine.ps1** | Catalog action: CleanRAM, Network, Docker, Node, Temp, Firewall, Maintenance |
| **Recovery.ps1** | Pipeline recovery đa bước + SmartRecovery |
| **Verify.ps1** | Kiểm tra sau action |

## Thứ tự nạp (bắt buộc)

```
Core → Safety → Telemetry → Discovery → Dependency → Diagnostic → Decision → ActionEngine → Recovery → Verify
```

## Nguyên tắc

1. Không action nào bỏ qua Safety (trừ NONE/MONITOR/WAIT).
2. Dependency: sửa tầng trên trước (Internet trước Node).
3. Recovery pipeline: step → verify → retry 1 lần → escalate.
4. Minimal intervention.
