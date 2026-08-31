# Security baseline (community standard)

## Secrets
- Bot token / API keys: `Data\secrets.protected.json` (DPAPI CurrentUser)
- Never log plaintext tokens (length only)
- Empty field in Dashboard = keep existing secret

## Files
- Restrict ACL on `secrets.protected.json` (current user R/W)
- No secrets in `Logs\`, `daily_digest*.txt`, `status_panel.txt`

## Network
- Telegram outbound HTTPS only (one-way)
- No inbound HTTP API (Bridge removed)

## Execution
- Tasks run as current user; prefer least privilege
- High-risk actions require Dashboard approval + optional TG notify

## Updates
- Thin `PiSpider.exe` only launches scripts; update `.ps1` without trusting random EXEs
