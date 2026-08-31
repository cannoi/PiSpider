# Who runs the daily report?

| Component | Role |
|-----------|------|
| **PiSpider.exe / Dashboard** | UI only. Closing it does **not** stop reports. |
| **Task Scheduler `PiNodeSpider_DailyReport`** | Runs every day ~19:15 |
| **`PiNodeSpider.ps1 -Command DailyReport`** | Builds digest + optional Telegram |
| **`Report\DailyDigest.ps1`** | Template + AI/data text |
| **`Notify\TelegramNotify.ps1`** | One-way send (if enabled) |

## Checklist if no Telegram at 19h

1. Task installed? `Scheduler\Status_Watch_Task.ps1`
2. Telegram enabled in Dashboard Settings + token/chat saved?
3. "Daily digest 19-20h" checkbox ON?
4. PC was ON at 19:15?
5. See `Data\daily_digest_meta.json` for Sent/Reason
6. See `Data\daily_digest.txt` for file content

## Manual test (sends if Telegram on; forces window)

```powershell
# File always; Telegram only in 19-20h unless you patch Force:
powershell -NoProfile -ExecutionPolicy Bypass -File .\PiNodeSpider.ps1 -Command DailyReport
```
