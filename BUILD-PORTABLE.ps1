param(
  [string]$Output = '',
  [switch]$IncludeNestedProjects
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
if(!$Output){$Output=Join-Path $Root 'dist\POOH-HUB-AI-Tunnel-V1.2-Portable.zip'}
$Output=[IO.Path]::GetFullPath($Output)
$Dist=Join-Path $Root 'dist\_stage'
if(Test-Path $Dist){Remove-Item $Dist -Recurse -Force}
New-Item -ItemType Directory -Force -Path $Dist | Out-Null

# Core project only. Generated credentials, runtime logs and machine-local
# profiles are deliberately excluded from the distributable package.
$include=@('config','scripts','tunnel','workspace','run.bat','setup.bat','.gitignore','README.md','SUMMARY.md','git-backup.bat','git-backup.ps1')
if($IncludeNestedProjects){$include+='GITHUB-PUBLIC';$include+='mcp-demo-files'}
foreach($item in $include){
  $src=Join-Path $Root $item
  if(!(Test-Path $src)){continue}
  $dst=Join-Path $Dist $item
  if((Get-Item $src).PSIsContainer){Copy-Item $src $dst -Recurse -Force}else{Copy-Item $src $dst -Force}
}

# Sanitize settings.json so the distributor's username/project path never
# leaks into the portable package.
$portableSettings=Join-Path $Dist 'config\settings.json'
if(Test-Path $portableSettings){
  $cfg=Get-Content $portableSettings -Raw | ConvertFrom-Json
  $cfg.workspace='../workspace'
  $cfg.version='1.2'
  $cfg.network.healthHost='127.0.0.1'
  $cfg.network.healthPort=18021
  $cfg | ConvertTo-Json -Depth 20 | Set-Content $portableSettings -Encoding UTF8
}

# Remove machine-local/generated content even if it exists in a copied folder.
$remove=@(
  (Join-Path $Dist 'tunnel\.env'),
  (Join-Path $Dist 'tunnel\gptwork.yaml'),
  (Join-Path $Dist 'config\.env'),
  (Join-Path $Dist 'config\projects.json'),
  (Join-Path $Dist 'config\providers.json'),
  (Join-Path $Dist 'runtime'),
  (Join-Path $Dist 'logs'),
  (Join-Path $Dist 'node_modules')
)
foreach($p in $remove){if(Test-Path $p){Remove-Item $p -Recurse -Force}}

# Refuse to package obvious private keys/secrets anywhere in the stage.
$secretFiles=Get-ChildItem $Dist -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -match '(^\.env$|\.env\.|credentials|secret|\.pem$|\.key$|\.p12$|\.pfx$)'
}
if($secretFiles){
  $names=($secretFiles | ForEach-Object FullName) -join "`n"
  throw "Refusing to package possible secret files:`n$names"
}

$parent=Split-Path -Parent $Output
New-Item -ItemType Directory -Force -Path $parent | Out-Null
if(Test-Path $Output){Remove-Item $Output -Force}
Compress-Archive -Path (Join-Path $Dist '*') -DestinationPath $Output -CompressionLevel Optimal
Remove-Item $Dist -Recurse -Force
Write-Host "[OK] Portable package created: $Output" -ForegroundColor Green
Write-Host '[OK] Credentials, generated tunnel profile, logs and local project state were excluded.' -ForegroundColor Cyan
