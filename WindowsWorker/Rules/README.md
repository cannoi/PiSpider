# Rules/

Quy tắc vận hành Spider — **dữ liệu**, không phải script sửa hệ thống.

| File | Nội dung |
|------|----------|
| **Rules.json** | Root Cause rules: Id, Severity, Condition, Action, Risk, Confidence |
| **Protected.json** | Protected Zone — process/path không được đụng |
| **Recovery.json** | Dependency order, timeout/retry từng action, level pipelines |
| **Severity.json** | 6 cấp HEALTHY → EMERGENCY |
| **Modes.json** | 5 autonomy modes + MaxAutoRisk |
| **Anomaly.json** | Spider Sense — ngưỡng mềm (baseline) |

## Schema rule

```json
{
  "Id": "RAM_USER_PRESSURE",
  "Severity": "WARNING",
  "Condition": "RAM >= RAM_Warning AND TopMemoryIsUserApp AND NodeHealthy",
  "RootCause": "...",
  "ConfidenceBase": 90,
  "Action": "CLEAN_RAM",
  "Risk": "LOW",
  "ImpactOnNode": "LOW"
}
```

## Ai đọc file nào

| Engine module | File |
|---------------|------|
| Core | Rules.json, Protected.json, Recovery.json |
| Diagnostic | Rules.json (+ Config thresholds) |
| Decision | Modes (Config) + Rules severity |
| Safety | Protected.json + Recovery.json |
| Dependency / Recovery | Recovery.json DependencyOrder + LevelPipelines |
| Future Anomaly Sense | Anomaly.json |

## Nguyên tắc

1. Sửa rule bằng JSON — không hard-code trong Action.
2. EXTREME / BIOS không bao giờ auto.
3. Minimal intervention: WAIT trước RESET khi confidence thấp.
4. Dependency: không reset tầng dưới khi tầng trên gãy.

Threshold số (RAM 85/92, disk GB…) nằm trong **Config.json** để dễ chỉnh theo máy.
