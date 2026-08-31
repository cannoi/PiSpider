# Digest report template

Edit **`Report/DigestTemplate.json`** — no code change needed.

## Quick options

| Field | Meaning |
|-------|---------|
| `Title` | First line of the message |
| `ForceLanguage` | `"vi"` / `"en"` / `null` (auto from Windows UI) |
| `ShowPcUser` / `ShowHealth` / `ShowIssues` / `ShowNotes` / `ShowInsight` | Toggle sections |
| `Text.en` / `Text.vi` | Localized phrases |
| `Icons` | Markers like `[OK]`, `[!]`, `[X]` |
| `MaxIssueDetailChars` | Truncate long details |

## Force Vietnamese always

```json
"ForceLanguage": "vi"
```

## Test

```powershell
powershell -File .\PiNodeSpider.ps1 -Command DailyReport
```

Output: `Data\daily_digest.txt` (+ Telegram in 19:00–20:00 if enabled).
