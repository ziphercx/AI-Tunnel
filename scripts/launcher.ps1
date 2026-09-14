$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Tui=Join-Path $PSScriptRoot 'tui.ps1'
if(-not (Test-Path -LiteralPath $Tui)){Write-Host 'Missing scripts\tui.ps1' -ForegroundColor Red;exit 1}
# Compatibility launcher: the old V4 number/click menu is intentionally removed.
& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $Tui
exit $LASTEXITCODE
