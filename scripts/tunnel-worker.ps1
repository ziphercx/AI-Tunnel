$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ConfigDir = Join-Path $Root 'config'
$TunnelDir = Join-Path $Root 'tunnel'
$EnvFile = Join-Path $TunnelDir '.env'
$RuntimeConfig = Join-Path $TunnelDir 'gptwork.yaml'
$Exe = Join-Path $TunnelDir 'tunnel-client.exe'
$PidFile = Join-Path $Root 'runtime\pids\tunnel-worker.pid'
$LogDir = Join-Path $Root 'runtime\logs'
$StdOut = Join-Path $LogDir 'tunnel.stdout.log'
$StdErr = Join-Path $LogDir 'tunnel.stderr.log'

function Load-Env {
    $cfg = @{}
    if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) { return $cfg }
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        if ($line -match '^\s*([^#=]+)=(.*)$') {
            $cfg[$matches[1].Trim()] = $matches[2].Trim().Trim('"')
        }
    }
    return $cfg
}

$cfg = Load-Env
if ([string]::IsNullOrWhiteSpace($cfg['GPT_API_KEY'])) { throw 'GPT API Key is missing.' }
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw 'tunnel-client.exe is missing.' }
if (-not (Test-Path -LiteralPath $RuntimeConfig -PathType Leaf)) { throw 'Runtime configuration is missing.' }

New-Item -ItemType Directory -Force -Path $ConfigDir, $TunnelDir, (Split-Path -Parent $PidFile), $LogDir | Out-Null
$env:CONTROL_PLANE_API_KEY = $cfg['GPT_API_KEY']
if (-not [string]::IsNullOrWhiteSpace($cfg['WORKSPACE_PATH'])) { $env:WORKSPACE_PATH = $cfg['WORKSPACE_PATH'] }

$proc = $null
try {
    # Start tunnel-client completely hidden. It inherits no visible console window.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Exe
    # tunnel-client resolves the profile and its relative MCP command from
    # tunnel\, so always launch it from the directory containing the profile.
    $startInfo.WorkingDirectory = $TunnelDir
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.Arguments = 'run --profile-file "gptwork.yaml"'
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $startInfo
    $proc.EnableRaisingEvents = $false

    if (-not $proc.Start()) { throw 'Could not start tunnel-client.exe.' }
    Set-Content -LiteralPath $PidFile -Value ([string]$proc.Id) -Encoding ASCII

    # Drain stdout/stderr without creating another console window.
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdoutTask.Result | Set-Content -LiteralPath $StdOut -Encoding UTF8
    $stderrTask.Result | Set-Content -LiteralPath $StdErr -Encoding UTF8
    exit $proc.ExitCode
}
finally {
    Remove-Item Env:CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:WORKSPACE_PATH -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $PidFile) {
        $current = (Get-Content -LiteralPath $PidFile -Raw).Trim()
        if ($proc -and $current -eq [string]$proc.Id) {
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        }
    }
}
