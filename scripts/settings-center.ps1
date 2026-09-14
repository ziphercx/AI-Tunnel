$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Config=Join-Path $Root 'config'
$SettingsFile=Join-Path $Config 'settings.json'
$TunnelDir=Join-Path $Root 'tunnel'
$EnvFile=Join-Path $TunnelDir '.env'
$Profile=Join-Path $TunnelDir 'gptwork.yaml'
$Utf8=New-Object System.Text.UTF8Encoding($false)

function Load(){if(!(Test-Path $SettingsFile)){throw 'settings.json not found'};Get-Content $SettingsFile -Raw|ConvertFrom-Json}
function Save($s){[IO.File]::WriteAllText($SettingsFile,($s|ConvertTo-Json -Depth 20),$Utf8)}
function SetProp($o,$name,$value){if($o.PSObject.Properties[$name]){$o.$name=$value}else{$o|Add-Member NoteProperty $name $value}}
function ReadEnv(){
  $h=@{};if(Test-Path $EnvFile){foreach($l in Get-Content $EnvFile){if($l -match '^\s*([^#=]+)=(.*)$'){$h[$matches[1].Trim()]=$matches[2].Trim().Trim('"')}}};$h
}
function SaveEnv($h){$lines=@();foreach($k in $h.Keys){$lines+=($k+'='+[string]$h[$k])};[IO.File]::WriteAllLines($EnvFile,$lines,$Utf8)}
function Ask($label,$default=''){$v=Read-Host ($label+' ['+$default+']');if([string]::IsNullOrWhiteSpace($v)){$default}else{$v.Trim()}}
function Secret($label,$default=''){$x=Read-Host $label -AsSecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($x);try{$v=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)};if($v){$v}else{$default}}
function Port($default){while($true){$v=Ask 'Health port' ([string]$default);$n=0;if([int]::TryParse($v,[ref]$n)-and $n-ge 1-and $n-le 65535){return $n};Write-Host 'Port must be 1-65535.' -ForegroundColor Red}}
function Pick($current){Add-Type -AssemblyName System.Windows.Forms;$d=New-Object System.Windows.Forms.FolderBrowserDialog;$d.Description='Select AI workspace';$d.ShowNewFolderButton=$true;if(Test-Path $current){$d.SelectedPath=$current};try{if($d.ShowDialog()-eq 'OK'){return [IO.Path]::GetFullPath($d.SelectedPath)}}finally{$d.Dispose()};$null}
function RestartIfRunning(){
  $m=Join-Path $PSScriptRoot 'manager.ps1';if(!(Test-Path $m)){return}
  try{$st=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $m status 2>$null|Out-String;if($st -match 'TUNNEL_STATUS=RUNNING'){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $m restart|Out-Host}}catch{Write-Host 'Saved. Restart manually if needed.' -ForegroundColor Yellow}
}
function UpdateProfile($s,$env){
  $id=[string]$env['TUNNEL_ID'];$base=[string]$s.aiProviders.controlPlaneUrl;if(!$base){$base='https://api.openai.com'};$port=[int]$s.network.healthPort
  $yaml=@"
config_version: 1

control_plane:
  base_url: "$base"
  tunnel_id: "$id"
  api_key: "env:CONTROL_PLANE_API_KEY"

health:
  listen_addr: "$($s.network.healthHost):$port"

admin_ui:
  open_browser: false

log:
  level: info
  format: json

mcp:
  commands:
    - channel: main
      command: 'node "../stitch-async-mcp/main-server.mjs"'
"@
  [IO.File]::WriteAllText($Profile,$yaml,$Utf8)
}
function Init($s){
  if(!$s.PSObject.Properties['network']){$s|Add-Member NoteProperty network ([pscustomobject]@{healthHost='127.0.0.1';healthPort=18020})}
  if(!$s.PSObject.Properties['scope']){$s|Add-Member NoteProperty scope ([pscustomobject]@{mode='workspace';allowedPaths=@();allowFullComputer=$false})}
  if(!$s.PSObject.Properties['permissions']){$s|Add-Member NoteProperty permissions ([pscustomobject]@{fileAccess='ask';terminalAccess='ask';destructiveActions='ask';sessionApproval=$false;alwaysAllow=$false})}
  if(!$s.PSObject.Properties['aiProviders']){$s|Add-Member NoteProperty aiProviders ([pscustomobject]@{active='openai';supported=@('openai');controlPlaneUrl='https://api.openai.com'})}
  if(!$s.aiProviders.PSObject.Properties['controlPlaneUrl']){$s.aiProviders|Add-Member NoteProperty controlPlaneUrl 'https://api.openai.com'}
  if(!$s.PSObject.Properties['features']){$s|Add-Member NoteProperty features ([pscustomobject]@{files=$true;terminal=$true;extended=$true;stitch=$true})}
  if(!$s.PSObject.Properties['terminal']){$s|Add-Member NoteProperty terminal ([pscustomobject]@{maxConcurrentJobs=4;maxRuntimeSeconds=1800;maxOutputBytes=5242880})}
  if(!$s.PSObject.Properties['gitBackup']){$s|Add-Member NoteProperty gitBackup ([pscustomobject]@{enabled=$false;intervalMinutes=15;requirePushApproval=$true})}
  return $s
}
function Menu($title,$items){
  $i=0
  while($true){
    Clear-Host;Write-Host '';Write-Host '  ================================================================' -ForegroundColor DarkCyan;Write-Host ('      '+$title) -ForegroundColor Cyan;Write-Host '  ================================================================' -ForegroundColor DarkCyan;Write-Host ''
    for($n=0;$n-lt$items.Count;$n++){$prefix=$(if($n-eq$i){'  > '}else{'    '});$color=$(if($n-eq$i){'Cyan'}else{'White'});Write-Host ($prefix+$items[$n]) -ForegroundColor $color}
    Write-Host '';Write-Host '  Up/Down = Select   Enter = Confirm   Esc = Back   Home/End = First/Last' -ForegroundColor DarkGray
    $k=[Console]::ReadKey($true)
    switch($k.Key){'UpArrow'{$i=($i-1+$items.Count)%$items.Count};'DownArrow'{$i=($i+1)%$items.Count};'Home'{$i=0};'End'{$i=$items.Count-1};'Enter'{return $i};'Escape'{return -1}}
  }
}
function Main {
  while($true){
    $s=Init (Load);Save $s;$env=ReadEnv
    $items=@(
      'Workspace / project folder',
      ('Health host + PORT  ['+$s.network.healthHost+':'+$s.network.healthPort+']'),
      ('Control Plane URL  ['+$s.aiProviders.controlPlaneUrl+']'),
      'Tunnel ID',
      'Control Plane API key (hidden)',
      ('AI provider  ['+$s.aiProviders.active+']'),
      'Scope / allowed paths',
      'Permissions / approvals',
      'Terminal limits',
      'Feature switches',
      'Git backup settings',
      'Regenerate tunnel profile',
      'Back'
    )
    $p=Menu 'TUNNEL V4.1-NEW SETTINGS CENTER' $items
    if($p-lt 0 -or $p-eq 12){return}
    switch($p){
      0{$x=Pick ([string]$s.workspace);if($x){$s.workspace=$x;Save $s;RestartIfRunning}}
      1{$s.network.healthHost=Ask 'Health host' ([string]$s.network.healthHost);$s.network.healthPort=Port ([int]$s.network.healthPort);Save $s;UpdateProfile $s $env;RestartIfRunning}
      2{$s.aiProviders.controlPlaneUrl=Ask 'Control Plane URL' ([string]$s.aiProviders.controlPlaneUrl);Save $s;UpdateProfile $s $env;RestartIfRunning}
      3{$env['TUNNEL_ID']=Ask 'Tunnel ID' ([string]$env['TUNNEL_ID']);SaveEnv $env;UpdateProfile $s $env;RestartIfRunning}
      4{$env['CONTROL_PLANE_API_KEY']=Secret 'Control Plane API key (hidden)' ([string]$env['CONTROL_PLANE_API_KEY']);$env['GPT_API_KEY']=$env['CONTROL_PLANE_API_KEY'];SaveEnv $env;RestartIfRunning}
      5{$s.aiProviders.active=Ask 'Provider' ([string]$s.aiProviders.active);Save $s}
      6{$s.scope.mode=Ask 'Scope (session/workspace/custom)' ([string]$s.scope.mode);if($s.scope.mode-eq'custom'){$a=@();while($true){$x=Read-Host 'Allowed path (blank ends)';if(!$x){break};$a+=[IO.Path]::GetFullPath($x)};$s.scope.allowedPaths=$a};$s.scope.allowFullComputer=$false;Save $s;RestartIfRunning}
      7{$s.permissions.fileAccess=Ask 'File access (ask/session/always)' ([string]$s.permissions.fileAccess);$s.permissions.terminalAccess=Ask 'Terminal access (ask/session/always)' ([string]$s.permissions.terminalAccess);$s.permissions.destructiveActions=Ask 'Destructive actions (ask/session/always)' ([string]$s.permissions.destructiveActions);$s.permissions.sessionApproval=($s.permissions.fileAccess-eq'session'-or$s.permissions.terminalAccess-eq'session');$s.permissions.alwaysAllow=($s.permissions.fileAccess-eq'always'-or$s.permissions.terminalAccess-eq'always');Save $s;RestartIfRunning}
      8{$n=0;$v=Ask 'Max concurrent jobs (1-32)' ([string]$s.terminal.maxConcurrentJobs);if([int]::TryParse($v,[ref]$n)){$s.terminal.maxConcurrentJobs=[Math]::Max(1,[Math]::Min(32,$n))};$v=Ask 'Max runtime seconds' ([string]$s.terminal.maxRuntimeSeconds);if([int]::TryParse($v,[ref]$n)){$s.terminal.maxRuntimeSeconds=[Math]::Max(60,$n)};$v=Ask 'Max output bytes' ([string]$s.terminal.maxOutputBytes);if([int]::TryParse($v,[ref]$n)){$s.terminal.maxOutputBytes=[Math]::Max(1024,$n)};Save $s;RestartIfRunning}
      9{$s.features.files=(Ask 'Files ON? (yes/no)' $(if($s.features.files){'yes'}else{'no'}))-match '(?i)^y';$s.features.terminal=(Ask 'Terminal ON? (yes/no)' $(if($s.features.terminal){'yes'}else{'no'}))-match '(?i)^y';$s.features.extended=(Ask 'Power tools ON? (yes/no)' $(if($s.features.extended){'yes'}else{'no'}))-match '(?i)^y';$s.features.stitch=(Ask 'Stitch ON? (yes/no)' $(if($s.features.stitch){'yes'}else{'no'}))-match '(?i)^y';Save $s;RestartIfRunning}
      10{$s.gitBackup.enabled=(Ask 'Git backup enabled? (yes/no)' $(if($s.gitBackup.enabled){'yes'}else{'no'}))-match '(?i)^y';$v=Ask 'Backup interval minutes' ([string]$s.gitBackup.intervalMinutes);$n=0;if([int]::TryParse($v,[ref]$n)){$s.gitBackup.intervalMinutes=[Math]::Max(1,$n)};$s.gitBackup.requirePushApproval=$true;Save $s}
      11{UpdateProfile $s $env}
    }
  }
}
Main
