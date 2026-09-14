$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ConfigDir = Join-Path $Root 'config'
$ProjectFile = Join-Path $ConfigDir 'projects.json'

function Load-Projects {
    if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $ProjectFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { return @() }
        return @($data)
    } catch { return @() }
}

function Save-Projects($Projects) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    @($Projects) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ProjectFile -Encoding UTF8
}

function Select-Folder($InitialPath, $Description) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $InitialPath -PathType Container) { $dialog.SelectedPath = $InitialPath }
    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return [IO.Path]::GetFullPath($dialog.SelectedPath)
        }
    } finally { $dialog.Dispose() }
    return $null
}

function Add-ProjectProfile {
    $workspace = Join-Path $Root 'workspace'
    $path = Select-Folder $workspace 'Select a project folder to connect to a GitHub repository'
    if (-not $path) { return }
    $name = Read-Host 'Project name'
    if ([string]::IsNullOrWhiteSpace($name)) { $name = Split-Path $path -Leaf }
    $remote = Read-Host 'GitHub repository URL (HTTPS or SSH)'
    if ([string]::IsNullOrWhiteSpace($remote)) { return }
    $branch = Read-Host 'Branch [main]'
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }

    $projects = @(Load-Projects)
    $existing = $projects | Where-Object { $_.Path -ieq $path } | Select-Object -First 1
    if ($existing) {
        $existing.Name = $name
        $existing.Remote = $remote
        $existing.Branch = $branch
        $existing.AutoBackup = $true
    } else {
        $projects += [pscustomobject]@{
            Name = $name
            Path = $path
            Remote = $remote
            Branch = $branch
            AutoBackup = $true
            BackupIntervalMinutes = 15
        }
    }
    Save-Projects $projects
    Write-Host ''
    Write-Host "[SAVED] $name" -ForegroundColor Green
    Write-Host "        $path" -ForegroundColor Gray
    Write-Host "        $remote ($branch)" -ForegroundColor Gray
}

function Toggle-ProjectBackup {
    $projects = @(Load-Projects)
    if ($projects.Count -eq 0) { Write-Host 'No project profiles configured.' -ForegroundColor Yellow; return }
    for ($i=0; $i -lt $projects.Count; $i++) {
        $state = if ($projects[$i].AutoBackup) { 'ON' } else { 'OFF' }
        Write-Host ("[{0}] {1}  [{2}]" -f ($i+1), $projects[$i].Name, $state)
    }
    $choice = Read-Host 'Select project'
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $projects.Count) { return }
    $projects[$index-1].AutoBackup = -not [bool]$projects[$index-1].AutoBackup
    Save-Projects $projects
    Write-Host ("Auto backup is now {0}." -f $(if($projects[$index-1].AutoBackup){'ON'}else{'OFF'})) -ForegroundColor Green
}

function Remove-ProjectProfile {
    $projects = @(Load-Projects)
    if ($projects.Count -eq 0) { Write-Host 'No project profiles configured.' -ForegroundColor Yellow; return }
    for ($i=0; $i -lt $projects.Count; $i++) { Write-Host ("[{0}] {1} - {2}" -f ($i+1), $projects[$i].Name, $projects[$i].Path) }
    $choice = Read-Host 'Select project to remove'
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $projects.Count) { return }
    $name = $projects[$index-1].Name
    $projects = @($projects | Where-Object { $_ -ne $projects[$index-1] })
    Save-Projects $projects
    Write-Host "Removed profile: $name" -ForegroundColor Green
}

while ($true) {
    Clear-Host
    Write-Host ''
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |              PROJECT + GITHUB MANAGER                  |' -ForegroundColor Cyan
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  [1] Add / update project profile' -ForegroundColor White
    Write-Host '  [2] Toggle auto backup' -ForegroundColor White
    Write-Host '  [3] List project profiles' -ForegroundColor White
    Write-Host '  [4] Activate project for AI' -ForegroundColor White
    Write-Host '  [5] Remove project profile' -ForegroundColor White
    Write-Host '  [6] Back' -ForegroundColor White
    Write-Host ''
    $choice = Read-Host '  Select'
    switch ($choice) {
        '1' { Add-ProjectProfile; Read-Host 'Press Enter' | Out-Null }
        '2' { Toggle-ProjectBackup; Read-Host 'Press Enter' | Out-Null }
        '3' {
            $projects = @(Load-Projects)
            if ($projects.Count -eq 0) { Write-Host 'No project profiles configured.' -ForegroundColor Yellow }
            foreach ($p in $projects) {
                Write-Host ''
                Write-Host "  $($p.Name)" -ForegroundColor Cyan
                Write-Host "    Path       : $($p.Path)" -ForegroundColor Gray
                Write-Host "    GitHub     : $($p.Remote)" -ForegroundColor Gray
                Write-Host "    Branch     : $($p.Branch)" -ForegroundColor Gray
                Write-Host "    Auto backup: $(if($p.AutoBackup){'ON'}else{'OFF'})" -ForegroundColor $(if($p.AutoBackup){'Green'}else{'Yellow'})
            }
            Read-Host 'Press Enter' | Out-Null
        }
        '4' {
            $projects = @(Load-Projects)
            if ($projects.Count -eq 0) { Write-Host 'No project profiles configured.' -ForegroundColor Yellow; Read-Host 'Press Enter' | Out-Null; continue }
            for ($i=0; $i -lt $projects.Count; $i++) { Write-Host ("[{0}] {1} - {2}" -f ($i+1), $projects[$i].Name, $projects[$i].Path) }
            $choice = Read-Host 'Select active project'
            $index = 0
            if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $projects.Count) {
                $envFile = Join-Path $ConfigDir '.env'
                $lines = @(); if (Test-Path -LiteralPath $envFile) { $lines = @(Get-Content -LiteralPath $envFile) }
                $target = [IO.Path]::GetFullPath($projects[$index-1].Path)
                $found = $false
                $out = foreach ($line in $lines) {
                    if ($line -match '^\s*ACTIVE_PROJECT_PATH=') { $found = $true; 'ACTIVE_PROJECT_PATH=' + $target } else { $line }
                }
                if (-not $found) { $out += 'ACTIVE_PROJECT_PATH=' + $target }
                $out | Set-Content -LiteralPath $envFile -Encoding UTF8
                Write-Host "[ACTIVE] $($projects[$index-1].Name)" -ForegroundColor Green
            }
            Read-Host 'Press Enter' | Out-Null
        }
        '5' { Remove-ProjectProfile; Read-Host 'Press Enter' | Out-Null }
        '6' { return }
    }
}
