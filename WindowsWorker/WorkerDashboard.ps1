#Requires -Version 5.1
# Hidden console + simple Windows Worker dashboard
[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:SpiderRoot = $PSScriptRoot
if (-not $script:SpiderRoot) { $script:SpiderRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$env:PINODE_SPIDER_ROOT = $script:SpiderRoot
$busFile = Join-Path $script:SpiderRoot 'Engine\LiveBus.ps1'
if (Test-Path -LiteralPath $busFile) { . $busFile }

$script:WorkerProc = $null
$script:History = New-Object System.Collections.Generic.List[string]
$script:LastCmdId = ''
$script:LastResultAt = ''
$script:Mode = 'AUTO'

function Get-BusFolder {
    if (Get-Command Get-SpiderLiveBusDir -ErrorAction SilentlyContinue) {
        return Get-SpiderLiveBusDir
    }
    $d = Join-Path $script:SpiderRoot 'Data\live'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Read-BusFile([string]$Name) {
    $p = Join-Path (Get-BusFolder) $Name
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Add-Hist([string]$Line) {
    $script:History.Insert(0, ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Line))
    while ($script:History.Count -gt 40) { [void]$script:History.RemoveAt($script:History.Count - 1) }
}

function Test-WorkerAlive {
    if ($script:WorkerProc -and -not $script:WorkerProc.HasExited) { return $true }
    $hb = Read-BusFile 'heartbeat.json'
    if (-not $hb) { return $false }
    try {
        $t = [datetime]::Parse($hb.At)
        return ((Get-Date) - $t).TotalSeconds -lt 90
    } catch { return [bool]$hb.Alive }
}

function Start-HiddenWorker {
    if (Test-WorkerAlive) { Add-Hist 'Worker already running'; return }
    $live = Join-Path $script:SpiderRoot 'LiveWorker.ps1'
    $agent = Join-Path $script:SpiderRoot 'WindowsAgent.ps1'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $common = @{
        FilePath = $ps
        WorkingDirectory = $script:SpiderRoot
        WindowStyle = 'Hidden'
        PassThru = $true
    }
    if (Test-Path $agent) {
        Start-Process @common -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $agent) | Out-Null
    }
    if (Test-Path $live) {
        $script:WorkerProc = Start-Process @common -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $live)
        Add-Hist 'Started hidden LiveWorker'
    } else {
        Add-Hist 'ERROR LiveWorker.ps1 missing'
    }
}

function Stop-HiddenWorker {
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and ($_.CommandLine -like '*LiveWorker.ps1*' -or $_.CommandLine -like '*WindowsAgent.ps1*') } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {}
    $script:WorkerProc = $null
    Add-Hist 'Stopped Worker processes'
}

# --- UI ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'PiSpider Worker'
$form.Size = New-Object System.Drawing.Size(560, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimizeBox = $true
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

function Add-L([string]$Text, [int]$Y, [int]$H = 22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point(16, $Y)
    $l.Size = New-Object System.Drawing.Size(520, $H)
    $form.Controls.Add($l)
    return $l
}

$lblMode = Add-L 'Mode: AUTO' 12
$lblMode.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblAlive = Add-L 'Worker: starting...' 40
$lblCmd = Add-L 'SoloHost command: (none)' 66
$lblProg = Add-L 'Progress: idle' 88

$boxNow = New-Object System.Windows.Forms.TextBox
$boxNow.Multiline = $true
$boxNow.ReadOnly = $true
$boxNow.ScrollBars = 'Vertical'
$boxNow.Location = New-Object System.Drawing.Point(16, 118)
$boxNow.Size = New-Object System.Drawing.Size(512, 280)
$form.Controls.Add($boxNow)

$y = 410
function Add-Btn([string]$Text, [int]$X, [scriptblock]$Click) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $y)
    $b.Size = New-Object System.Drawing.Size(120, 32)
    $b.Add_Click($Click)
    $form.Controls.Add($b)
    return $b
}

[void](Add-Btn 'Start Worker' 16 { Start-HiddenWorker })
[void](Add-Btn 'Stop Worker' 144 { Stop-HiddenWorker })
[void](Add-Btn 'Open folder' 272 {
    Start-Process explorer.exe $script:SpiderRoot
})
[void](Add-Btn 'Open bus' 400 {
    Start-Process explorer.exe (Get-BusFolder)
})
$y = 450
[void](Add-Btn 'Mode AUTO' 16 { $script:Mode = 'AUTO'; Add-Hist 'Mode AUTO' })
[void](Add-Btn 'Mode ASSIST' 144 { $script:Mode = 'ASSIST'; Add-Hist 'Mode ASSIST' })
[void](Add-Btn 'Install schedule' 272 {
    $s = Join-Path $script:SpiderRoot 'Scheduler\Install_Watch_Task.ps1'
    if (Test-Path $s) {
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $s) -Verb RunAs
        Add-Hist 'Opened schedule installer'
    } else { Add-Hist 'Scheduler script missing' }
})
[void](Add-Btn 'Hide to tray' 400 {
    $form.WindowState = 'Minimized'
})

$lblHint = Add-L 'This window is the Worker. Command consoles stay hidden.' 492 40

function Refresh-Ui {
    $alive = Test-WorkerAlive
    $hb = Read-BusFile 'heartbeat.json'
    $cmd = Read-BusFile 'command.json'
    $res = Read-BusFile 'result.json'
    $last = Read-BusFile 'command.last.json'

    $lblMode.Text = "Mode: $($script:Mode)"
    $lblAlive.Text = if ($alive) { 'Worker: ON  (hidden)' } else { 'Worker: OFF' }
    if ($hb -and $hb.Note) { $lblAlive.Text += "  $($hb.Note)" }

    if ($cmd -and $cmd.Action) {
        $lblCmd.Text = "SoloHost command: $($cmd.Action)  id=$($cmd.Id)"
        $lblProg.Text = if ($alive -and $hb -and $hb.Busy) { 'Progress: running' } else { 'Progress: queued' }
        if ($cmd.Id -and $cmd.Id -ne $script:LastCmdId) {
            $script:LastCmdId = [string]$cmd.Id
            Add-Hist ("RECV $($cmd.Action)")
        }
    } else {
        $lblCmd.Text = 'SoloHost command: (none waiting)'
        $lblProg.Text = 'Progress: idle'
    }

    if ($res -and $res.At -and $res.At -ne $script:LastResultAt) {
        $script:LastResultAt = [string]$res.At
        Add-Hist ("DONE $($res.Action) $($res.Status) $($res.Summary)")
    }

    $now = @()
    $now += '=== NOW ==='
    $now += $(if ($alive) { 'Running AUTO poll for SoloHost commands' } else { 'Not running — press Start Worker' })
    if ($hb) { $now += "Heartbeat $($hb.At)" }
    $now += ''
    $now += '=== DONE ==='
    if ($res) { $now += "$($res.Action)  $($res.Status)  $($res.Summary)" } else { $now += '(no result yet)' }
    $now += ''
    $now += '=== NEXT ==='
    if ($cmd -and $cmd.Action) { $now += "Will run $($cmd.Action)" } else { $now += 'Wait for SoloHost SCAN / REPAIR / STATUS' }
    $now += ''
    $now += '=== LOG ==='
    $now += ($script:History -join [Environment]::NewLine)
    $boxNow.Text = $now -join [Environment]::NewLine
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Refresh-Ui })
$form.Add_Shown({
    Start-HiddenWorker
    Refresh-Ui
    $timer.Start()
})
$form.Add_FormClosing({
    $timer.Stop()
})

[void]$form.ShowDialog()
