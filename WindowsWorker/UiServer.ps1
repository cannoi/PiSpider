#Requires -Version 5.1
# Local dashboard stream for SoloHost (http://127.0.0.1:18771)
param([int]$Port = 18771)

$ErrorActionPreference = 'Continue'
$script:SpiderRoot = $PSScriptRoot
$env:PINODE_SPIDER_ROOT = $script:SpiderRoot
$busPs = Join-Path $script:SpiderRoot 'Engine\LiveBus.ps1'
if (Test-Path $busPs) { . $busPs }

function Get-BusDir {
    if (Get-Command Get-SpiderLiveBusDir -EA SilentlyContinue) { return Get-SpiderLiveBusDir }
    $d = Join-Path $script:SpiderRoot 'Data\live'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Read-Bus([string]$Name) {
    $p = Join-Path (Get-BusDir) $Name
    if (-not (Test-Path $p)) { return $null }
    try { return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-StatusObject {
    $hb = Read-Bus 'heartbeat.json'
    $cmd = Read-Bus 'command.json'
    $res = Read-Bus 'result.json'
    $alive = $false
    if ($hb -and $hb.At) {
        try { $alive = ((Get-Date) - [datetime]::Parse($hb.At)).TotalSeconds -lt 90 } catch { $alive = [bool]$hb.Alive }
    }
    [ordered]@{
        Mode = 'AUTO'
        WorkerAlive = $alive
        Heartbeat = $hb
        Command = $cmd
        Result = $res
        Bus = (Get-BusDir)
        At = (Get-Date).ToString('o')
    }
}

function Get-Html {
    $s = Get-StatusObject
    $now = if ($s.WorkerAlive) { 'Worker ON — AUTO poll' } else { 'Worker OFF' }
    $cmd = if ($s.Command -and $s.Command.Action) { [string]$s.Command.Action } else { '(none)' }
    $prog = if ($s.Heartbeat -and $s.Heartbeat.Busy) { 'running' } else { 'idle / queued' }
    $done = if ($s.Result) { "$($s.Result.Action) $($s.Result.Status) $($s.Result.Summary)" } else { '(no result yet)' }
    $err = if ($s.Result -and $s.Result.Status -eq 'FAIL') { [string]$s.Result.Summary } else { '' }
@"
<!doctype html><html><head><meta charset="utf-8"/><meta http-equiv="refresh" content="4"/>
<title>PiSpider Windows</title>
<style>
body{font-family:Segoe UI,sans-serif;background:#f4f5f7;margin:0;color:#222}
.w{max-width:720px;margin:0 auto;padding:16px}
.card{background:#fff;border:1px solid #ddd;border-radius:10px;padding:14px;margin:10px 0}
h1{margin:0 0 8px} .ok{color:#176b4d} .bad{color:#a33}
</style></head><body><div class="w">
<h1>PiSpider Windows</h1>
<p>Mode: <b>AUTO</b> — this page is the Windows app stream for SoloHost.</p>
<div class="card"><b>NOW</b><pre>$now
Command from SoloHost: $cmd
Progress: $prog</pre></div>
<div class="card"><b>DONE</b><pre>$done</pre></div>
<div class="card"><b>NEXT</b><pre>Wait for SCAN / STATUS / REPAIR from SoloHost.</pre></div>
$(if($err){"<div class='card bad'><b>ERROR</b><pre>$err</pre></div>"})
<p>Bus: $($s.Bus)</p>
</div></body></html>
"@
}

$prefix = "http://127.0.0.1:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
    Write-Error "Cannot bind $prefix : $($_.Exception.Message)"
    exit 1
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        if ($path -eq '/api/status') {
            $body = (Get-StatusObject | ConvertTo-Json -Depth 6)
            $buf = [Text.Encoding]::UTF8.GetBytes($body)
            $ctx.Response.ContentType = 'application/json; charset=utf-8'
        } else {
            $buf = [Text.Encoding]::UTF8.GetBytes((Get-Html))
            $ctx.Response.ContentType = 'text/html; charset=utf-8'
        }
        $ctx.Response.Headers.Add('Cache-Control','no-store')
        $ctx.Response.ContentLength64 = $buf.Length
        $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
        $ctx.Response.Close()
    } catch {}
}
