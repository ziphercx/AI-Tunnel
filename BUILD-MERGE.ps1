param([switch]$NoPause)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Base=Split-Path -Parent $Root
$V4=Join-Path $Base 'Tunnel-V4'
$AI=Join-Path $Base 'AI-Tunnel'

function Ensure($p){ if($p){New-Item -ItemType Directory -Force -Path $p | Out-Null} }
function Copy-Tree($src,$dst){
  Ensure $dst
  Get-ChildItem -LiteralPath $src -Force -Recurse -File -ErrorAction Stop | ForEach-Object {
    $rel=$_.FullName.Substring($src.Length).TrimStart('\','/')
    if($rel -match '(^|\\|/)\.env$|(^|\\|/)\.env\.|(^|\\|/)node_modules($|\\|/)|(^|\\|/)\.git($|\\|/)|\.key$|\.pem$|\.p12$|\.pfx$|credentials.*\.json$|secret.*\.json$|stitch-api-key\.txt$'){ return }
    # Never let source projects overwrite the V1.2 control layer.
    if($rel -in @('BUILD-MERGE.ps1','BUILD-V5.bat','BUILD-V5.ps1','run.bat','run-legacy.bat','setup.bat','README.md','SUMMARY.md','README_TUI.txt','TOOL_CATALOG_V4.txt','V4_CHANGELOG.txt','VALIDATION_V4.txt','config\settings.json','config\capabilities.json','scripts\launcher.ps1','scripts\setup.ps1','scripts\settings-center.ps1','scripts\log-center.ps1')){ return }
    $target=Join-Path $dst $rel
    Ensure (Split-Path -Parent $target)
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  }
}

if(!(Test-Path $V4)){throw "Tunnel-V4 not found: $V4"}
if(!(Test-Path $AI)){throw "AI-Tunnel not found: $AI"}

Write-Host '=== POOH HUB AI-Tunnel V1.2 merge ===' -ForegroundColor Cyan
Write-Host '[1/4] Copying V4 core (secrets excluded)...'
Copy-Tree $V4 $Root

Write-Host '[2/4] Copying AI-Tunnel management layer...'
foreach($f in @('scripts\project-manager.ps1','scripts\ai-provider-manager.ps1','scripts\backup-worker.ps1','scripts\tunnel-worker.ps1','git-backup.ps1','git-backup.bat')){
  $s=Join-Path $AI $f
  if(Test-Path $s){
    $d=Join-Path $Root $f
    Ensure (Split-Path -Parent $d)
    Copy-Item -LiteralPath $s -Destination $d -Force
  }
}

Write-Host '[3/4] Preserving V1.2 policy/config files...'
$settings=Join-Path $Root 'config\settings.json'
Ensure (Split-Path -Parent $settings)
if(!(Test-Path $settings)){
@'
{
  "version": "1.2",
  "workspace": "",
  "scope": {"mode":"workspace","allowedPaths":[],"allowFullComputer":false},
  "permissions": {"fileAccess":"ask","terminalAccess":"ask","destructiveActions":"ask","sessionApproval":false,"alwaysAllow":false},
  "features": {"files":true,"terminal":true,"extended":true,"stitch":true},
  "terminal": {"mode":"workspace","unknownExecutable":"approval","shells":"approval","destructive":"approval","maxConcurrentJobs":4,"maxRuntimeSeconds":1800,"maxOutputBytes":5242880},
  "network": {"healthHost":"127.0.0.1","healthPort":18020},
  "stitch": {"defaultOutputDir":".gpt/stitch"},
  "gitBackup": {"enabled":false,"intervalMinutes":15,"excludeSecrets":true,"requirePushApproval":true},
  "aiProviders": {"active":"openai","controlPlaneUrl":"https://api.openai.com","supported":["openai","anthropic","gemini","xai","deepseek","mistral","groq","openrouter","custom"]}
}
'@ | Set-Content $settings -Encoding UTF8
} else {
  $s=Get-Content $settings -Raw|ConvertFrom-Json
  if(-not $s.PSObject.Properties['network']){$s|Add-Member NoteProperty network ([pscustomobject]@{healthHost='127.0.0.1';healthPort=18020})}
  if(-not $s.network.PSObject.Properties['healthHost']){$s.network|Add-Member NoteProperty healthHost '127.0.0.1'}
  if(-not $s.network.PSObject.Properties['healthPort']){$s.network|Add-Member NoteProperty healthPort 18020}
  if(-not $s.PSObject.Properties['aiProviders']){$s|Add-Member NoteProperty aiProviders ([pscustomobject]@{active='openai';controlPlaneUrl='https://api.openai.com';supported=@('openai')})}
  if(-not $s.aiProviders.PSObject.Properties['controlPlaneUrl']){$s.aiProviders|Add-Member NoteProperty controlPlaneUrl 'https://api.openai.com'}
  $s|ConvertTo-Json -Depth 20|Set-Content $settings -Encoding UTF8
}
Ensure (Join-Path $Root 'workspace')
Ensure (Join-Path $Root 'runtime')

# Verify the V1.2 control layer survived the merge.
$required=@('BUILD-MERGE.ps1','run.bat','setup.bat','README.md','SUMMARY.md','config\settings.json','config\capabilities.json','scripts\launcher.ps1','scripts\setup.ps1','scripts\settings-center.ps1','scripts\log-center.ps1')
$missing=$required|Where-Object{-not(Test-Path(Join-Path $Root $_))}
if($missing){throw "Required V1.2 files are missing: $($missing -join ', ')"}

Write-Host '[4/4] Merge complete.' -ForegroundColor Green
Write-Host "Root: $Root"
Write-Host 'Secrets were excluded.' -ForegroundColor Yellow
Write-Host 'Original Tunnel-V4 and AI-Tunnel folders were not modified.' -ForegroundColor DarkGray
if(-not $NoPause){Read-Host 'Press Enter'|Out-Null}
