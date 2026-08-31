# ============================================================
# Actions/CleanTemp.ps1 - TEMP + recycle + safe docker prune (Risk: LOW)
# ============================================================
function Invoke-CleanTemp {
    Write-SpiderLog "ACTION: CLEAN_TEMP" 'ACTION'
    $isAdmin = Test-IsAdmin
    $count = 0
    $errors = 0

    try {
        Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if (Assert-NotProtectedTarget -Path $_.FullName) {
                try {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $count++
                } catch { $errors++ }
            }
        }
    } catch {}

    if ($isAdmin) {
        $wt = Join-Path $env:SystemRoot 'Temp'
        try {
            Get-ChildItem -Path $wt -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $count++
                } catch { $errors++ }
            }
        } catch {}
        try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    }

    # Safe docker prune (unused only)
    try {
        cmd /c "docker volume prune -f" >$null 2>&1
        cmd /c "docker image prune -f" >$null 2>&1
    } catch {}

    $disk = Get-DiskSnapshot
    return [pscustomobject]@{
        Action        = 'CLEAN_TEMP'
        Risk          = 'LOW'
        ItemsRemoved  = $count
        Errors        = $errors
        FreeGB        = $disk.FreeGB
        Success       = $true
    }
}
