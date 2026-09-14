$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$TunnelDir = Join-Path $Root "tunnel"
$TunnelExe = Join-Path $TunnelDir "tunnel-client.exe"
$RuntimeDir = Join-Path $Root "runtime"
$LogsDir = Join-Path $RuntimeDir "logs"
$PidsDir = Join-Path $RuntimeDir "pids"
$TunnelPidFile = Join-Path $PidsDir "tunnel.pid"
$StdoutLog = Join-Path $LogsDir "tunnel.stdout.log"
$StderrLog = Join-Path $LogsDir "tunnel.stderr.log"
$HostLog = Join-Path $LogsDir "tunnel-host.log"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TunnelEnvFile = Join-Path $TunnelDir ".env"
$WorkspaceDefault = Join-Path $Root "workspace"

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Append-LineShared([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent) { Ensure-Dir $parent }
    $line = if ($null -eq $Text) { "" } else { [string]$Text }
    $bytes = $Utf8NoBom.GetBytes($line + [Environment]::NewLine)
    $attempt = 0
    while ($true) {
        try {
            $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Dispose() }
            return
        } catch [System.IO.IOException] {
            $attempt++
            if ($attempt -ge 12) { return }
            Start-Sleep -Milliseconds 25
        }
    }
}

function Write-Pid([int]$ProcessId) {
    $text = [string]$ProcessId
    [System.IO.File]::WriteAllText($TunnelPidFile, $text, $Utf8NoBom)
}

Ensure-Dir $LogsDir
Ensure-Dir $PidsDir

function Load-DotEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing tunnel environment file: $Path" }
    foreach ($rawLine in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $line = [string]$rawLine
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $line = $line.Trim()
        if ($line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -le 0) { continue }
        $name = $line.Substring(0,$eq).Trim()
        $value = $line.Substring($eq+1).Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1,$value.Length-2)
        }
        if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
            [System.Environment]::SetEnvironmentVariable($name,$value,'Process')
        }
    }
}

$child = $null
try {
    if (-not (Test-Path -LiteralPath $TunnelExe)) { throw "Missing tunnel-client.exe: $TunnelExe" }
    Load-DotEnv $TunnelEnvFile

    # Normalize the workspace once at the host boundary. Relative .env values
    # are resolved from the project root, never from an arbitrary caller CWD.
    $configuredWorkspace = [string]$env:WORKSPACE_PATH
    if ([string]::IsNullOrWhiteSpace($configuredWorkspace)) { $configuredWorkspace = './workspace' }

    # Migrate the old V4.1/V4.1-New default automatically. A genuinely
    # custom WORKSPACE_PATH remains untouched so the user can override the
    # default when desired.
    $legacyWorkspace = $false
    if (-not [string]::IsNullOrWhiteSpace($configuredWorkspace)) {
        try {
            if ([System.IO.Path]::IsPathRooted($configuredWorkspace)) {
                $legacyCandidatePath = $configuredWorkspace
            } else {
                $legacyCandidatePath = Join-Path $Root $configuredWorkspace
            }
            $candidateLegacy = [System.IO.Path]::GetFullPath($legacyCandidatePath)
            if ($candidateLegacy -match '(?i)[\\/]Tunnel-V4\.1(?:-New)?[\\/]workspace$') { $legacyWorkspace = $true }
        } catch {}
    }
    if ($legacyWorkspace) { $configuredWorkspace = './workspace' }

    if (-not [System.IO.Path]::IsPathRooted($configuredWorkspace)) {
        $configuredWorkspace = [System.IO.Path]::GetFullPath((Join-Path $Root $configuredWorkspace))
    } else {
        $configuredWorkspace = [System.IO.Path]::GetFullPath($configuredWorkspace)
    }
    if (-not (Test-Path -LiteralPath $configuredWorkspace -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $configuredWorkspace | Out-Null
    }
    $env:WORKSPACE_PATH = $configuredWorkspace

    # Repair PATH for child processes even when this PowerShell process was
    # launched from a client that supplied a reduced/incomplete environment.
    $systemRoot = if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }
    $pathParts = @(
        $env:Path,
        (Join-Path $systemRoot 'System32'),
        $systemRoot,
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'nodejs' } else { 'C:\Program Files\nodejs' }),
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Git\cmd' } else { 'C:\Program Files\Git\cmd' }),
        $(if ($env:APPDATA) { Join-Path $env:APPDATA 'npm' } else { '' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }
    $env:Path = ($pathParts | Select-Object -Unique) -join ';'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $TunnelExe
    # gptwork.yaml already resolves control_plane.api_key from the
    # CONTROL_PLANE_API_KEY process environment variable. Do NOT pass
    # --control-plane.api-key file:.env here: .env is an env-file, not
    # a single API-key file, and that override makes tunnel-client reject
    # the key as malformed.
    $psi.Arguments = 'run --profile-file "gptwork.yaml"'
    $psi.WorkingDirectory = $TunnelDir
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['WORKSPACE_PATH'] = $env:WORKSPACE_PATH
    $psi.EnvironmentVariables['Path'] = $env:Path
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $psi
    if (-not $child.Start()) { throw "Could not start tunnel-client.exe" }
    Write-Pid $child.Id
    Append-LineShared $HostLog ("[{0}] tunnel-host started child PID {1}" -f (Get-Date).ToString("o"), $child.Id)

    # Read both redirected streams asynchronously.  The host owns the pipes,
    # but it opens/closes the log files for every line with FileShare.ReadWrite,
    # so the TUI can inspect logs at any time without Windows file-lock errors.
    $outDone = $false
    $errDone = $false
    $outTask = $child.StandardOutput.ReadLineAsync()
    $errTask = $child.StandardError.ReadLineAsync()

    while (-not ($child.HasExited -and $outDone -and $errDone)) {
        if (-not $outDone -and $outTask.IsCompleted) {
            $line = $outTask.GetAwaiter().GetResult()
            if ($null -eq $line) { $outDone = $true } else {
                Append-LineShared $StdoutLog $line
                $outTask = $child.StandardOutput.ReadLineAsync()
            }
        }
        if (-not $errDone -and $errTask.IsCompleted) {
            $line = $errTask.GetAwaiter().GetResult()
            if ($null -eq $line) { $errDone = $true } else {
                Append-LineShared $StderrLog $line
                $errTask = $child.StandardError.ReadLineAsync()
            }
        }
        Start-Sleep -Milliseconds 15
    }

    $child.WaitForExit()
    Append-LineShared $HostLog ("[{0}] tunnel child exited with code {1}" -f (Get-Date).ToString("o"), $child.ExitCode)
    exit $child.ExitCode
} catch {
    Append-LineShared $HostLog ("[{0}] HOST ERROR: {1}" -f (Get-Date).ToString("o"), $_.Exception.Message)
    exit 1
} finally {
    if ($child) {
        try {
            if (-not $child.HasExited) { & taskkill.exe /PID $child.Id /T /F 2>$null | Out-Null }
        } catch {}
        try { $child.Dispose() } catch {}
    }
    try {
        if (Test-Path -LiteralPath $TunnelPidFile) { Remove-Item -LiteralPath $TunnelPidFile -Force -ErrorAction SilentlyContinue }
    } catch {}
}
