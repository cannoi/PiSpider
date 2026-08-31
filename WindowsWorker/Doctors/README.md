# Doctors/ — Chuyên khoa chẩn đoán

Mỗi Doctor nhận `$Snapshot` từ Discovery và trả về:

```
Doctor, Status (OK|INFO|WARNING|CRITICAL), Issues[], Evidence, RecommendedAction, Notes
```

| File | Phạm vi |
|------|---------|
| Windows.ps1 | CPU, RAM, Uptime, Admin, process pressure |
| Hardware.ps1 | CPU/RAM hardware, Virtualization (READ-ONLY) |
| Network.ps1 | Adapter, IP, GW, DNS, Internet, Latency |
| Firewall.ps1 | Pi ports + firewall rules |
| WSL.ps1 | WSL available, vmmem |
| Docker.ps1 | Engine, Pi containers |
| PiNode.ps1 | Node healthy, processes, ports |
| Stellar.ps1 | Sync, ledger age, peers |
| Storage.ps1 | Disk free space |
| Security.ps1 | Protected zone observation |
| DataLive.ps1 | Optional MonitorLive freshness |
| DoctorHub.ps1 | `Invoke-AllDoctors` + format report |

## Gọi

```powershell
$snap = Invoke-FullCollect
$panel = Invoke-AllDoctors -Snapshot $snap
Format-DoctorReport $panel
```

Doctors **không** tự sửa — chỉ chẩn đoán. Action do Decision + ActionEngine quyết định.
