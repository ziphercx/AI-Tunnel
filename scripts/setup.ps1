param([switch]$Quiet)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Config=Join-Path $Root 'config'
$Tunnel=Join-Path $Root 'tunnel'
$EnvFile=Join-Path $Tunnel '.env'
$Settings=Join-Path $Config 'settings.json'
$Profile=Join-Path $Tunnel 'gptwork.yaml'
$LogDir=Join-Path $Root 'runtime\logs'
$ErrorLog=Join-Path $LogDir 'errors.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
trap {
  try { Add-Content -LiteralPath $ErrorLog -Value ("Time: $((Get-Date).ToString('o'))`r`nSource: setup.ps1`r`nMessage: $($_.Exception.Message)`r`nStack: $($_.ScriptStackTrace)`r`n------------------------------------------------------------") -Encoding UTF8 } catch {}
  Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
  if(!$Quiet){Read-Host 'Press Enter to continue'|Out-Null}
  exit 1
}
# The canonical V4 client binary lives in this project's tunnel\ folder.
# Keep setup self-contained so a fresh V1.2 checkout does not depend on
# a sibling legacy folder that may not exist.
$V4=$Root
New-Item -ItemType Directory -Force -Path $Config,$Tunnel,(Join-Path $Root 'workspace'),(Join-Path $Root 'runtime')|Out-Null

function ReadEnv(){
  $h=@{}
  if(Test-Path $EnvFile){foreach($l in Get-Content $EnvFile){if($l -match '^\s*([^#=]+)=(.*)$'){$h[$matches[1].Trim()]=$matches[2].Trim().Trim('"')}}}
  $h
}
function Secret($label){$s=Read-Host $label -AsSecureString;$p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}}
function Value($label,$default=''){if($default){$label="$label [$default]"};$v=Read-Host $label;if([string]::IsNullOrWhiteSpace($v)){$default}else{$v.Trim()}}
function Folder($initial){Add-Type -AssemblyName System.Windows.Forms;$d=New-Object System.Windows.Forms.FolderBrowserDialog;$d.Description='Select the workspace/project folder for AI access';$d.ShowNewFolderButton=$true;if(Test-Path $initial){$d.SelectedPath=$initial};try{if($d.ShowDialog()-eq 'OK'){return [IO.Path]::GetFullPath($d.SelectedPath)}}finally{$d.Dispose()};$null}

$old=ReadEnv
$tunnelId=Value 'Tunnel ID' ([string]$old['TUNNEL_ID'])
if(!$tunnelId){throw 'Tunnel ID is required.'}
$key=Secret 'Control Plane / GPT API key (hidden)'
if(!$key){$key=[string]$old['GPT_API_KEY']}
if(!$key){throw 'API key is required.'}
# The default workspace is deliberately stored as a project-relative path.
# This avoids embedding the distributor's Windows username in the package.
$defaultWs=Join-Path $Root 'workspace'
$ws=[string]$old['WORKSPACE_PATH']
if(!$ws -or $ws -match 'POOHHUB'){$ws=$defaultWs}
elseif(-not [IO.Path]::IsPathRooted($ws)){$ws=[IO.Path]::GetFullPath((Join-Path $Tunnel $ws))}
$pick=Folder $ws
if($pick){$ws=$pick}
$ws=[IO.Path]::GetFullPath($ws)
New-Item -ItemType Directory -Force -Path $ws|Out-Null

# Keep the default workspace portable. Absolute paths are retained only when
# the user intentionally selected a custom workspace outside this project.
$workspaceValue=if($ws -eq [IO.Path]::GetFullPath($defaultWs)){'../workspace'}else{$ws}
@("TUNNEL_ID=$tunnelId","CONTROL_PLANE_API_KEY=$key","GPT_API_KEY=$key","WORKSPACE_PATH=$workspaceValue","AI_PROVIDER=$([string]$(if($old['AI_PROVIDER']){$old['AI_PROVIDER']}else{'openai'}))")|Set-Content $EnvFile -Encoding UTF8

@"
config_version: 1

control_plane:
  base_url: "https://api.openai.com"
  tunnel_id: "$tunnelId"
  api_key: "env:CONTROL_PLANE_API_KEY"

health:
  listen_addr: "127.0.0.1:18021"

admin_ui:
  open_browser: false

log:
  level: info
  format: json

mcp:
  commands:
    - channel: main
      command: 'node "../scripts/stitch-mcp.mjs"'
"@|Set-Content $Profile -Encoding UTF8

if(!(Test-Path (Join-Path $Tunnel 'tunnel-client.exe'))){
  $src=Join-Path $V4 'tunnel\tunnel-client.exe'
  if(Test-Path $src){Copy-Item $src (Join-Path $Tunnel 'tunnel-client.exe') -Force;Write-Host '[OK] Copied tunnel-client.exe from V4.' -ForegroundColor Green}
  else{Write-Host '[WARN] tunnel-client.exe is missing. Add the correct client binary to tunnel\.' -ForegroundColor Yellow}
}

if(!(Test-Path $Settings)){
  '{"workspace":"../workspace","network":{"healthHost":"127.0.0.1","healthPort":18021},"aiProviders":{"active":"openai","supported":["openai"],"controlPlaneUrl":"https://api.openai.com"}}' | Set-Content $Settings -Encoding UTF8
}
$s=Get-Content $Settings -Raw|ConvertFrom-Json
if(-not $s.PSObject.Properties['network']){$s|Add-Member NoteProperty network ([pscustomobject]@{healthHost='127.0.0.1';healthPort=18021})}
if(-not $s.network.PSObject.Properties['healthHost']){$s.network|Add-Member NoteProperty healthHost '127.0.0.1'}
if(-not $s.network.PSObject.Properties['healthPort']){$s.network|Add-Member NoteProperty healthPort 18021}
# Migrate the legacy V4 health port so setup/profile/manager stay consistent.
if([int]$s.network.healthPort -eq 18020){$s.network.healthPort=18021}
if(-not $s.PSObject.Properties['aiProviders']){$s|Add-Member NoteProperty aiProviders ([pscustomobject]@{active='openai';supported=@('openai');controlPlaneUrl='https://api.openai.com'})}
if(-not $s.aiProviders.PSObject.Properties['controlPlaneUrl']){$s.aiProviders|Add-Member NoteProperty controlPlaneUrl 'https://api.openai.com'}
$s.workspace=$workspaceValue
$port=[int]$s.network.healthPort
$base=[string]$s.aiProviders.controlPlaneUrl
@"
config_version: 1

control_plane:
  base_url: "$base"
  tunnel_id: "$tunnelId"
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
      command: 'node "../scripts/stitch-mcp.mjs"'
"@|Set-Content $Profile -Encoding UTF8
$s|ConvertTo-Json -Depth 20|Set-Content $Settings -Encoding UTF8
# Keep the manager and profile on one canonical health port.
Write-Host '';Write-Host '[OK] POOH HUB AI-Tunnel V1.2 setup complete.' -ForegroundColor Green;Write-Host "Workspace: $workspaceValue" -ForegroundColor Gray
Write-Host '[PORTABLE] Default paths are project-relative; no POOHHUB-specific path is stored.' -ForegroundColor Cyan
if(!$Quiet){Read-Host 'Press Enter to continue'|Out-Null}
