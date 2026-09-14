$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$remove=@(
  'BUILD-V5.bat',
  'BUILD-V5.ps1',
  'run-legacy.bat',
  'README_TUI.txt',
  'TOOL_CATALOG_V4.txt',
  'V4_CHANGELOG.txt',
  'VALIDATION_V4.txt',
  'config\.env'
)
foreach($rel in $remove){
  $path=Join-Path $Root $rel
  if(Test-Path -LiteralPath $path){
    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    Write-Host ('[DEL] '+$rel) -ForegroundColor Yellow
  }
}
Write-Host '[OK] Legacy/duplicate V1.2 migration files removed.' -ForegroundColor Green
Write-Host '[OK] The active UI is scripts\tui.ps1 (keyboard-first).' -ForegroundColor Cyan
