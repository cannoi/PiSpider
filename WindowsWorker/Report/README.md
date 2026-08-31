# Report/

Xuất báo cáo cho **Controller / Telegram / Console / Archive**.  
Spider **không** gửi Telegram trực tiếp.

| File | Chức năng |
|------|-----------|
| TelegramReport.ps1 | full / compact / alert text + controller_bridge.json |
| ConsoleReport.ps1 | Báo cáo màu trên console |
| JsonReport.ps1 | last_report.json + archive bundle |
| ReportHub.ps1 | Gọi một lần → ghi mọi định dạng |

## File trong Data/

| File | Mô tả |
|------|--------|
| telegram_report.txt | Text full (≤ ~3800 ký tự) |
| telegram_report_compact.txt | 1–2 dòng |
| telegram_report_alert.txt | Cảnh báo ngắn |
| controller_bridge.json | Machine-readable cho Bridge |
| last_report.json | Full object scan |
| Reports/report_*.json | Archive (giữ 30 bản) |

## Gọi

```powershell
Invoke-SpiderReportHub -Report $report -Console -Archive
```
