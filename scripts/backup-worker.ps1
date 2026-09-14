$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ConfigDir = Join-Path $Root 'config'
$ProjectFile = Join-Path $ConfigDir 'projects.json'
$LogFile = Join-Path $Root 'logs\backup.log'
$PidFile = Join-Path $ConfigDir 'backup-worker.pid'

function Log($Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
    Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -Encoding UTF8
}
function Load-Projects {
    if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) { return @() }
    try { return @((Get-Content -LiteralPath $ProjectFile -Raw | ConvertFrom-Json)) } catch { return @() }
}
function Backup-Project($p) {
    if (-not $p.AutoBackup) { return }
    if (-not (Test-Path -LiteralPath $p.Path -PathType Container)) { Log "SKIP $($p.Name): project path missing"; return }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Log 'ERROR: git not found'; return }
    Push-Location -LiteralPath $p.Path
    try {
        $inside = (& git rev-parse --is-inside-work-tree 2>$null).Trim()
        if ($inside -ne 'true') { & git init | Out-Null }
        $remote = (& git remote get-url origin 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($remote) -and -not [string]::IsNullOrWhiteSpace($p.Remote)) { & git remote add origin $p.Remote | Out-Null }
        elseif (-not [string]::IsNullOrWhiteSpace($p.Remote) -and $remote -ne $p.Remote) { & git remote set-url origin $p.Remote | Out-Null }
        $branch = if ([string]::IsNullOrWhiteSpace($p.Branch)) { 'main' } else { $p.Branch }
        $current = (& git branch --show-current 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($current)) { & git checkout -B $branch | Out-Null }
        elseif ($current -ne $branch) { & git checkout -B $branch | Out-Null }

        # Do not stage common secret/credential files.
        & git add -A | Out-Null
        @('.env','.env.*','*.pem','*.key','*.p12','*.pfx','*credentials*.json','*secret*.json') | ForEach-Object { & git reset -- $_ 2>$null | Out-Null }
        & git diff --cached --quiet
        if ($LASTEXITCODE -ne 0) {
            & git commit -m ('AI Tunnel auto-backup ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-Null
            if ($LASTEXITCODE -eq 0) { Log "COMMIT $($p.Name)" }
        }
        $remoteNow = (& git remote get-url origin 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($remoteNow)) {
            & git push -u origin $branch 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Log "PUSH OK $($p.Name) -> $branch" } else { Log "PUSH FAILED $($p.Name) -> $branch" }
        }
    } catch { Log "ERROR $($p.Name): $($_.Exception.Message)" }
    finally { Pop-Location }
}

try {
    Set-Content -LiteralPath $PidFile -Value ([string]$PID) -Encoding ASCII
    while ($true) {
        foreach ($project in @(Load-Projects)) { Backup-Project $project }
        $minutes = 15
        $projects = @(Load-Projects) | Where-Object { $_.AutoBackup -eq $true -and $_.BackupIntervalMinutes -gt 0 }
        if ($projects.Count -gt 0) { $minutes = [int](($projects | Measure-Object BackupIntervalMinutes -Minimum).Minimum) }
        if ($minutes -lt 1) { $minutes = 1 }
        Start-Sleep -Seconds ($minutes * 60)
    }
}
finally { Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue }
