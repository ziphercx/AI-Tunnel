$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Header($text) {
  Clear-Host
  Write-Host ('=' * 68) -ForegroundColor DarkCyan
  Write-Host ('                 ' + $text) -ForegroundColor Cyan
  Write-Host ('=' * 68) -ForegroundColor DarkCyan
}
function Ask-Yes($text) {
  $x = Read-Host "$text [Y/n]"
  return ([string]::IsNullOrWhiteSpace($x) -or $x -match '^(y|yes)$')
}

Header 'AI TUNNEL - GIT BACKUP'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'Git was not found in PATH. Install Git for Windows first.'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '.')).Path
$workspace = Join-Path $root 'workspace'
if (-not (Test-Path $workspace)) { New-Item -ItemType Directory -Path $workspace -Force | Out-Null }

Write-Host "Workspace: $workspace" -ForegroundColor Gray
Write-Host 'Only projects inside the AI-Tunnel workspace can be selected.' -ForegroundColor Yellow
Write-Host ''

$dlg = New-Object System.Windows.Forms.FolderBrowserDialog
$dlg.Description = 'Select a project inside AI-Tunnel\workspace'
$dlg.ShowNewFolderButton = $true
$dlg.SelectedPath = $workspace

if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
  Write-Host 'Cancelled.'
  exit 0
}

$project = (Resolve-Path -LiteralPath $dlg.SelectedPath).Path
$workspaceFull = (Resolve-Path -LiteralPath $workspace).Path

if ($project -ne $workspaceFull -and -not $project.StartsWith($workspaceFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Security check failed: selected folder is outside the workspace.'
}

if ($project -eq $workspaceFull) {
  throw 'Select a project folder inside workspace, not workspace itself.'
}

Set-Location -LiteralPath $project
Write-Host "Selected project: $project" -ForegroundColor Green
Write-Host 'The project is used in place. Nothing is moved or copied.' -ForegroundColor Gray

$isRepo = (& git rev-parse --is-inside-work-tree 2>$null)
if ($isRepo -ne 'true') {
  if (-not (Ask-Yes 'This folder is not a Git repository. Create one here?')) { exit 0 }
  & git init
  if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
}

$remote = (& git remote get-url origin 2>$null)
if ([string]::IsNullOrWhiteSpace($remote)) {
  Write-Host ''
  Write-Host 'No Git remote is configured.' -ForegroundColor Yellow
  $remote = Read-Host 'Git remote URL (HTTPS or SSH)'
  if ([string]::IsNullOrWhiteSpace($remote)) { throw 'Remote URL is required.' }
  & git remote add origin $remote
  if ($LASTEXITCODE -ne 0) { throw 'git remote add failed.' }
} else {
  Write-Host "Remote: $remote" -ForegroundColor Gray
}

$branch = (& git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
  $branch = 'main'
  & git checkout -B $branch
}

Write-Host "Branch: $branch" -ForegroundColor Gray
Write-Host ''
Write-Host '--- Git status ---' -ForegroundColor Cyan
& git status --short

if (-not (Ask-Yes 'Stage changes, commit, and push this project?')) { exit 0 }

# Prevent common secrets from being staged by default.
$blocked = @(
  '.env', '.env.local', '.env.production', '.env.development',
  '*.pem', '*.key', '*.p12', '*.pfx',
  '*credentials*.json', '*secret*.json'
)

foreach ($pattern in $blocked) {
  & git reset -- $pattern 2>$null
}

& git add -A
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }

# Unstage common secret files even if they were previously tracked.
foreach ($pattern in $blocked) {
  & git reset -- $pattern 2>$null
}

& git diff --cached --quiet
$hasChanges = ($LASTEXITCODE -ne 0)
if ($hasChanges) {
  $message = Read-Host 'Commit message [AI Tunnel backup]'
  if ([string]::IsNullOrWhiteSpace($message)) { $message = 'AI Tunnel backup' }
  & git commit -m $message
  if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
} else {
  Write-Host 'No changes to commit.' -ForegroundColor Yellow
}

& git push -u origin $branch
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Push failed. Authenticate Git normally and run again.' -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host 'SUCCESS: Project backup completed.' -ForegroundColor Green
Write-Host "Repository: $remote" -ForegroundColor Gray
Write-Host "Branch:     $branch" -ForegroundColor Gray
