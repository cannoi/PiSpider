#Requires -Version 5.1
# Optional: call from Dashboard Save or Install schedule
function Invoke-SpiderSecurityHarden {
    $root = $script:SpiderRoot
    if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
    $sec = Join-Path $root 'Data\secrets.protected.json'
    if (Test-Path $sec) {
        try {
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            icacls.exe $sec /inheritance:r 2>$null | Out-Null
            icacls.exe $sec /grant:r "${user}:(R,W)" 2>$null | Out-Null
        } catch {}
    }
    # Scrub accidental tokens from recent logs (best-effort)
    $logDir = Join-Path $root 'Logs'
    if (Test-Path $logDir) {
        Get-ChildItem $logDir -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $c = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                if ($c -and $c -match '\d{8,12}:[A-Za-z0-9_-]{20,}') {
                    $c2 = [regex]::Replace($c, '\d{8,12}:[A-Za-z0-9_-]{20,}', '[REDACTED_BOT_TOKEN]')
                    if ($c2 -ne $c) { Set-Content $_.FullName $c2 -Encoding UTF8 }
                }
            } catch {}
        }
    }
    return $true
}
