#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$WorkerRoot)
$ErrorActionPreference='SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Is-Admin {
  $id=[Security.Principal.WindowsIdentity]::GetCurrent(); $p=New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Elevate the GUI once; all background Worker processes inherit the elevated token.
if(-not (Is-Admin)) {
  $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $arg='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -WorkerRoot "'+$WorkerRoot+'"'
  Start-Process $ps -Verb RunAs -ArgumentList $arg -WindowStyle Hidden | Out-Null
  exit 0
}

$script:Root=(Resolve-Path -LiteralPath $WorkerRoot).Path
$script:Live=Join-Path $script:Root 'Data\live'
if(-not (Test-Path $script:Live)){New-Item -ItemType Directory -Path $script:Live -Force | Out-Null}
$script:Worker=Join-Path $script:Root 'LiveWorker.ps1'
$script:MutexName='Global\PiSpider-WorkerDashboard'
try{$script:GuiMutex=New-Object System.Threading.Mutex($false,$script:MutexName);if(-not $script:GuiMutex.WaitOne(0,$false)){exit 0}}catch{}

function Read-Json($name){
  try{$p=Join-Path $script:Live $name;if(Test-Path $p){return (Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json)}}catch{};return $null
}
function Write-Json($name,$obj){try{$p=Join-Path $script:Live $name;$obj|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $p -Encoding UTF8}catch{}}
function Worker-Running {
  try{$m=[Threading.Mutex]::OpenExisting('Global\PiSpider-WindowsWorker');$m.Dispose();return $true}catch{return $false}
}
function Start-WorkerHidden {
  if(Worker-Running){return}
  $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $env:PINODE_SPIDER_GUI='1'
  $a='-NoProfile -ExecutionPolicy Bypass -File "'+$script:Worker+'"'
  Start-Process $ps -ArgumentList $a -WorkingDirectory $script:Root -WindowStyle Hidden -PassThru | Out-Null
}

$form=New-Object System.Windows.Forms.Form
$form.Text='PiSpider Windows Worker'
$form.StartPosition='CenterScreen';$form.Size=New-Object Drawing.Size(980,700);$form.MinimumSize=New-Object Drawing.Size(900,620)
$form.BackColor=[Drawing.Color]::FromArgb(20,24,31);$form.ForeColor=[Drawing.Color]::White

$header=New-Object Windows.Forms.Panel;$header.Dock='Top';$header.Height=76;$header.BackColor=[Drawing.Color]::FromArgb(28,34,43);$form.Controls.Add($header)
$title=New-Object Windows.Forms.Label;$title.Text='PiSpider Windows Worker';$title.Font=New-Object Drawing.Font('Segoe UI',20,[Drawing.FontStyle]::Bold);$title.Location=New-Object Drawing.Point(20,12);$title.AutoSize=$true;$header.Controls.Add($title)
$state=New-Object Windows.Forms.Label;$state.Text='● AUTO: STARTING';$state.Font=New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold);$state.Location=New-Object Drawing.Point(650,20);$state.AutoSize=$true;$state.ForeColor=[Drawing.Color]::LimeGreen;$header.Controls.Add($state)

$info=New-Object Windows.Forms.Panel;$info.Dock='Top';$info.Height=95;$info.Padding=New-Object Windows.Forms.Padding(14);$form.Controls.Add($info)
$cards=@();foreach($t in @('WORKER','ACTIVITY','CURRENT','LAST RESULT')){$l=New-Object Windows.Forms.Label;$l.Text=$t+'`r`n—';$l.Font=New-Object Drawing.Font('Segoe UI',10);$l.AutoSize=$false;$l.TextAlign='MiddleLeft';$l.Padding=New-Object Windows.Forms.Padding(10);$l.BorderStyle='FixedSingle';$l.Size=New-Object Drawing.Size(220,70);$l.Location=New-Object Drawing.Point((14+($cards.Count*235)),12);$info.Controls.Add($l);$cards+=$l}

$tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill';$form.Controls.Add($tabs)
$tabNow=New-Object Windows.Forms.TabPage;$tabNow.Text='Live';$tabNow.BackColor=$form.BackColor;$tabs.TabPages.Add($tabNow)
$tabQueue=New-Object Windows.Forms.TabPage;$tabQueue.Text='Commands';$tabQueue.BackColor=$form.BackColor;$tabs.TabPages.Add($tabQueue)
$tabSet=New-Object Windows.Forms.TabPage;$tabSet.Text='Settings';$tabSet.BackColor=$form.BackColor;$tabs.TabPages.Add($tabSet)

$grid=New-Object Windows.Forms.ListView;$grid.Dock='Fill';$grid.View='Details';$grid.FullRowSelect=$true;$grid.GridLines=$true;$grid.BackColor=[Drawing.Color]::FromArgb(24,29,37);$grid.ForeColor=[Drawing.Color]::White
[void]$grid.Columns.Add('TIME',155);[void]$grid.Columns.Add('PROCESS / COMMAND',190);[void]$grid.Columns.Add('STATE',100);[void]$grid.Columns.Add('RESULT / ERROR',450);$tabNow.Controls.Add($grid)

$cmdBox=New-Object Windows.Forms.TextBox;$cmdBox.Multiline=$true;$cmdBox.Dock='Fill';$cmdBox.ReadOnly=$true;$cmdBox.ScrollBars='Vertical';$cmdBox.BackColor=[Drawing.Color]::FromArgb(24,29,37);$cmdBox.ForeColor=[Drawing.Color]::White;$cmdBox.Font=New-Object Drawing.Font('Consolas',10);$tabQueue.Controls.Add($cmdBox)

$setPanel=New-Object Windows.Forms.FlowLayoutPanel;$setPanel.Dock='Top';$setPanel.Height=180;$setPanel.Padding=New-Object Windows.Forms.Padding(15);$setPanel.FlowDirection='TopDown';$tabSet.Controls.Add($setPanel)
$pathLabel=New-Object Windows.Forms.Label;$pathLabel.Text='Worker: '+$script:Worker;$pathLabel.AutoSize=$true;$setPanel.Controls.Add($pathLabel)
$buttons=@(
  @('Restart Worker','restart'),@('Open Worker Folder','folder'),@('Open Live Data','live'),@('Open Config','config'),@('Test SoloHost','test')
)
foreach($b in $buttons){$bt=New-Object Windows.Forms.Button;$bt.Text=$b[0];$bt.Tag=$b[1];$bt.Width=240;$bt.Height=34;$setPanel.Controls.Add($bt);$bt.Add_Click({
  switch($this.Tag){
   'restart'{try{Get-Process powershell -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $null}|Out-Null}catch{};Start-WorkerHidden}
   'folder'{Start-Process explorer.exe -ArgumentList ('"'+$script:Root+'"')}
   'live'{Start-Process explorer.exe -ArgumentList ('"'+$script:Live+'"')}
   'config'{Start-Process notepad.exe -ArgumentList ('"'+(Join-Path $script:Root 'Config.json')+'"')}
   'test'{try{Invoke-RestMethod 'http://127.0.0.1:18770/api/worker-check' -TimeoutSec 3|Out-Null;[Windows.Forms.MessageBox]::Show('SoloHost responded.','PiSpider')}catch{[Windows.Forms.MessageBox]::Show('SoloHost did not respond on 18770.','PiSpider')}}
  }
})}

$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000
$script:lastCmdId='';$script:lastResultAt='';$script:startedAt=Get-Date
$timer.Add_Tick({
  if(-not (Worker-Running)){Start-WorkerHidden}
  $hb=Read-Json 'heartbeat.json';$cmd=Read-Json 'command.json';$last=Read-Json 'command.last.json';$res=Read-Json 'result.json';$prog=Read-Json 'worker_progress.json';$auto=Read-Json 'autonomous.json'
  $alive=$false;if($hb -and $hb.At){try{$alive=((Get-Date)-([datetime]$hb.At)).TotalSeconds -lt 45}catch{}}
  $cards[0].Text='WORKER`r`n'+$(if($alive){'ONLINE'}else{'STARTING / OFFLINE'})
  $cards[1].Text='ACTIVITY`r`n'+$(if($hb.Busy){$hb.Note}else{'IDLE'})
  $cards[2].Text='CURRENT`r`n'+$(if($prog){$prog.Action+' — '+$prog.Phase}else{'Waiting for command'})
  $cards[3].Text='LAST RESULT`r`n'+$(if($res){$res.Status+' | '+$res.Action}else{'—'})
  if($auto -and $auto.Active){$state.Text='● AUTO: ON'}else{$state.Text='● AUTO: READY'}
  $grid.Items.Clear()
  if($prog){$it=$grid.Items.Add([string]$prog.At);[void]$it.SubItems.Add([string]$prog.Action);[void]$it.SubItems.Add([string]$prog.Phase);[void]$it.SubItems.Add([string]$prog.Detail)}
  if($res){$it=$grid.Items.Add([string]$res.At);[void]$it.SubItems.Add([string]$res.Action);[void]$it.SubItems.Add([string]$res.Status);[void]$it.SubItems.Add([string]$res.Summary)}
  if($cmd){$it=$grid.Items.Add([string]$cmd.CreatedAt);[void]$it.SubItems.Add([string]$cmd.Action);[void]$it.SubItems.Add('RECEIVED');[void]$it.SubItems.Add('From SoloHost: '+[string]$cmd.Id)}
  $txt=@('SoloHost command: '+$(if($cmd){$cmd.Action}else{$last.Action}), 'Command ID: '+$(if($cmd){$cmd.Id}else{$last.Id}), 'Worker: '+$(if($alive){'ONLINE'}else{'OFFLINE'}), 'Busy: '+$(if($hb){$hb.Busy}else{$false}), 'Progress: '+$(if($prog){$prog.Phase+' | '+$prog.Detail}else{'—'}), 'Last result: '+$(if($res){$res.Status+' | '+$res.Summary}else{'—'}))
  $cmdBox.Lines=$txt
})
$form.Add_Shown({Start-WorkerHidden;$timer.Start()})
$form.Add_FormClosing({$timer.Stop()})
[void]$form.ShowDialog()
