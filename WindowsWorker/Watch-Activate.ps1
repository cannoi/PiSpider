#Requires -Version 5.1
# One-time helper on Windows: wait for SoloHost terms-accept, then start LiveWorker.
$root = $PSScriptRoot
$live = Join-Path $root 'Data\live'
New-Item -ItemType Directory -Path $live -Force | Out-Null
Write-Host "[WATCH] Waiting for SoloHost I AGREE  ($live)"
while ($true) {
    $flag = Join-Path $live 'ACTIVATE_NOW.json'
    $start = Join-Path $root 'START_NOW.flag'
    $busy = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*LiveWorker.ps1*' }
    if ((Test-Path $flag) -or (Test-Path $start)) {
        if (-not $busy) {
            Write-Host "[WATCH] Terms accepted — starting LiveWorker"
            Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
                -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $root 'LiveWorker.ps1')) `
                -WorkingDirectory $root -WindowStyle Hidden
        }
    }
    Start-Sleep -Seconds 8
}
