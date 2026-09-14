param(
    [Parameter(Mandatory=$true)][int]$ParentPid,
    [Parameter(Mandatory=$true)][string]$ApprovalsDir
)

$ErrorActionPreference = "SilentlyContinue"

function Test-ParentAlive([int]$Id) {
    if ($Id -le 0) { return $false }
    try { Get-Process -Id $Id -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Read-JsonShared([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            try {
                $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
                try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $fs.Dispose() }
            if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
            return ($raw | ConvertFrom-Json)
        } catch { Start-Sleep -Milliseconds 60 }
    }
    return $null
}

$notify = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Warning
    $notify.Text = "AI Local Workspace"
    $notify.Visible = $true

    $seen = @{}
    while (Test-ParentAlive $ParentPid) {
        if (Test-Path -LiteralPath $ApprovalsDir) {
            $files = @(Get-ChildItem -LiteralPath $ApprovalsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
            foreach ($file in $files) {
                $item = Read-JsonShared $file.FullName
                if (-not $item -or [string]$item.status -ne "pending") { continue }
                $id = [string]$item.id
                if ([string]::IsNullOrWhiteSpace($id) -or $seen.ContainsKey($id)) { continue }
                $seen[$id] = $true

                $seconds = 0
                try {
                    $seconds = [Math]::Max(0, [int][Math]::Ceiling((([DateTime]::Parse([string]$item.expiresAt)).ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalSeconds))
                } catch {}
                $title = [string]$item.title
                if ([string]::IsNullOrWhiteSpace($title)) { $title = "Action needs approval" }
                if ($title.Length -gt 55) { $title = $title.Substring(0, 52) + "..." }
                $summary = ([string]$item.summary -replace '[\r\n]+', ' ').Trim()
                if ($summary.Length -gt 120) { $summary = $summary.Substring(0, 117) + "..." }
                $body = "$title`n$summary`nClick Approvals or press A - expires in ${seconds}s"
                try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
                $notify.ShowBalloonTip(8000, "AI Local Workspace - Approval required", $body, [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        }
        Start-Sleep -Seconds 1
    }
} finally {
    if ($notify) {
        $notify.Visible = $false
        $notify.Dispose()
    }
}
