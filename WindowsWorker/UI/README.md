# UI/

Giao diện **local console**. Telegram UI nằm ở Controller PRO (Bridge).

| File | Vai trò |
|------|---------|
| **SpiderConsole.ps1** | Load UI + `Start-SpiderConsole` |
| **Approval.ps1** | Approval Console (Y/N/S + timeout) |
| **StatusBoard.ps1** | Bảng health đẹp |
| **Menu.ps1** | Menu tương tác Scan/Patrol/Repair... |

## Approval Console

- Hiện khi `Decision.RequiresApproval = true` (thường Mode **ASSIST** hoặc Risk cao).
- **Không** hiện khi `-FromController`, `-Quiet`, hoặc non-interactive → Skipped (Controller xử lý confirm riêng).

```
[Y] Approve   [N] Deny   [S] Skip
Timeout → Deny
```

## Chạy

```powershell
. .\UI\SpiderConsole.ps1
Start-SpiderConsole          # Menu
Start-SpiderConsole Status   # Board
```

Hoặc: `.\PiNodeSpider.ps1 -Command Menu` (nếu đã wire).
