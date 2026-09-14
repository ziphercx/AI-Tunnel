param(
    [Parameter(Position=0)]
    [string]$Action = "status",
    [string]$Feature = "",
    [string]$Id = "",
    [int]$Index = 0,
    [int]$ParentPid = 0,
    [string]$Log = "tunnel"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$ConfigDir = Join-Path $Root "config"
$SettingsFile = Join-Path $ConfigDir "settings.json"
$StitchKeyFile = Join-Path $ConfigDir "stitch-api-key.txt"
$TunnelDir = Join-Path $Root "tunnel"
$TunnelExe = Join-Path $TunnelDir "tunnel-client.exe"
$TunnelHost = Join-Path $ScriptDir "tunnel-host.ps1"
$NotifierScript = Join-Path $ScriptDir "notifier.ps1"
$TunnelProfile = Join-Path $TunnelDir "gptwork.yaml"
$TunnelEnv = Join-Path $TunnelDir ".env"
$ServerDir = $ScriptDir
$McpServer = Join-Path $ServerDir "stitch-mcp.mjs"
$ApprovalRunner = Join-Path $ServerDir "approval-runner.mjs"
$SelfTestFile = Join-Path $ServerDir "mcp-self-test.mjs"
$RuntimeDir = Join-Path $Root "runtime"
$LogsDir = Join-Path $RuntimeDir "logs"
$PidsDir = Join-Path $RuntimeDir "pids"
$ApprovalsDir = Join-Path $RuntimeDir "approvals"
$TerminalJobsDir = Join-Path $RuntimeDir "terminal-jobs"
$StitchJobsDir = Join-Path $RuntimeDir "stitch-jobs"
$TunnelPidFile = Join-Path $PidsDir "tunnel.pid"
$TunnelHostPidFile = Join-Path $PidsDir "tunnel-host.pid"
$WatchdogPidFile = Join-Path $PidsDir "watchdog.pid"
$UiPidFile = Join-Path $PidsDir "tui.pid"
$NotifierPidFile = Join-Path $PidsDir "notifier.pid"
$StdoutLog = Join-Path $LogsDir "tunnel.stdout.log"
$StderrLog = Join-Path $LogsDir "tunnel.stderr.log"
$SetupLog = Join-Path $LogsDir "setup.log"
$TunnelHostLog = Join-Path $LogsDir "tunnel-host.log"
$ActivityLog = Join-Path $LogsDir "activity.log"
$ErrorLog = Join-Path $LogsDir "errors.log"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-Exe([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    try { $cmd = Get-Command $Name -ErrorAction Stop; if ($cmd.Source) { return [string]$cmd.Source }; if ($cmd.Path) { return [string]$cmd.Path } } catch {}
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $candidates = @()
    $systemRoot = if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\\Windows' }
    $programFiles = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\\Program Files' }
    $local = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
    $app = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $env:USERPROFILE 'AppData\Roaming' }
    switch ($base.ToLowerInvariant()) {
        'powershell' { $candidates += Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
        'pwsh' { $candidates += Join-Path $programFiles 'PowerShell\7\pwsh.exe'; $candidates += Join-Path $local 'Microsoft\PowerShell\7\pwsh.exe' }
        'node' { $candidates += Join-Path $programFiles 'nodejs\node.exe' }
        'npm' { $candidates += Join-Path $programFiles 'nodejs\npm.cmd'; $candidates += Join-Path $app 'npm\npm.cmd' }
        'git' { $candidates += Join-Path $programFiles 'Git\cmd\git.exe'; $candidates += Join-Path $programFiles 'Git\bin\git.exe' }
        'python' { $candidates += Join-Path $local 'Programs\Python\Python313\python.exe'; $candidates += Join-Path $local 'Programs\Python\Python312\python.exe'; $candidates += Join-Path $local 'Programs\Python\Python311\python.exe' }
        'py' { $candidates += Join-Path $systemRoot 'py.exe' }
        'cmd' { $candidates += Join-Path $systemRoot 'System32\cmd.exe' }
        'wsl' { $candidates += Join-Path $systemRoot 'System32\wsl.exe' }
    }
    foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
    return $null
}

function Ensure-Dir([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "Path is empty" }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-SafeWorkingDirectory([string]$Path, [string]$Fallback = $Root) {
    foreach ($candidate in @($Path, $Fallback)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($candidate)
            if (Test-Path -LiteralPath $full -PathType Container) { return $full }
        } catch {}
    }
    try { return (Get-Location).Path } catch { return $env:TEMP }
}

function Invoke-FileRetry([scriptblock]$Operation, [int]$Attempts = 12) {
    for ($i = 0; $i -lt $Attempts; $i++) {
        try { return (& $Operation) } catch [System.IO.IOException] {
            if ($i -ge ($Attempts - 1)) { throw }
            Start-Sleep -Milliseconds (20 + ($i * 15))
        } catch [System.UnauthorizedAccessException] {
            if ($i -ge ($Attempts - 1)) { throw }
            Start-Sleep -Milliseconds (20 + ($i * 15))
        }
    }
}

function Read-TextShared([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $result = Invoke-FileRetry {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        try {
            $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $fs.Dispose() }
    }
    return $result
}

function Get-TailShared([string]$Path, [int]$Lines = 80, [int]$MaxBytes = 524288) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $result = Invoke-FileRetry {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        try {
            $take = [int][Math]::Min([int64]$MaxBytes, $fs.Length)
            $start = [Math]::Max([int64]0, $fs.Length - $take)
            [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
            $buffer = New-Object byte[] $take
            $read = $fs.Read($buffer, 0, $take)
            if ($read -le 0) { return @() }
            $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            $parts = @($text -split "`r?`n")
            if ($start -gt 0 -and $parts.Count -gt 0) { $parts = @($parts | Select-Object -Skip 1) }
            return @($parts | Select-Object -Last $Lines)
        } finally { $fs.Dispose() }
    }
    return $result
}

function Write-TextNoBom([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent) { Ensure-Dir $parent }
    Invoke-FileRetry { [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom) } | Out-Null
}

function Write-JsonNoBom([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 12
    $parent = Split-Path -Parent $Path
    if ($parent) { Ensure-Dir $parent }

    $name = [System.IO.Path]::GetFileName($Path)
    $tmp = Join-Path $parent (".{0}.{1}.{2}.tmp" -f $name, $PID, ([Guid]::NewGuid().ToString("N")))
    $backup = Join-Path $parent (".{0}.{1}.{2}.bak" -f $name, $PID, ([Guid]::NewGuid().ToString("N")))
    try {
        [System.IO.File]::WriteAllText($tmp, $json, $Utf8NoBom)
        Invoke-FileRetry {
            if (Test-Path -LiteralPath $Path) {
                [System.IO.File]::Replace($tmp, $Path, $backup, $true)
            } else {
                [System.IO.File]::Move($tmp, $Path)
            }
        } | Out-Null
    } finally {
        foreach ($f in @($tmp, $backup)) {
            if ($f -and (Test-Path -LiteralPath $f)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Read-Settings {
    if (-not (Test-Path -LiteralPath $SettingsFile)) { throw "Missing settings file: $SettingsFile" }
    $raw = Read-TextShared $SettingsFile
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "settings.json is empty or unreadable" }
    return ($raw | ConvertFrom-Json)
}

function Save-Settings($Settings) {
    Write-JsonNoBom $SettingsFile $Settings
}

function Normalize-Settings {
    $s = Read-Settings
    $changed = $false
    if (-not $s.PSObject.Properties["workspace"]) { $s | Add-Member NoteProperty workspace ""; $changed = $true }
    if (-not $s.PSObject.Properties["features"]) {
        $s | Add-Member NoteProperty features ([pscustomobject]@{ files = $true; terminal = $true; extended = $true; stitch = $true })
        $changed = $true
    }
    foreach ($name in @("files", "terminal", "extended", "stitch")) {
        if (-not $s.features.PSObject.Properties[$name]) { $s.features | Add-Member NoteProperty $name $true; $changed = $true }
    }
    if (-not $s.PSObject.Properties["network"]) {
        $s | Add-Member NoteProperty network ([pscustomobject]@{ healthHost = "127.0.0.1"; healthPort = 18021 })
        $changed = $true
    }
    if (-not $s.network.PSObject.Properties["healthHost"]) { $s.network | Add-Member NoteProperty healthHost "127.0.0.1"; $changed = $true }
    if (-not $s.network.PSObject.Properties["healthPort"]) { $s.network | Add-Member NoteProperty healthPort 18021; $changed = $true }
    try {
        if ([int]$s.network.healthPort -eq 18020) { $s.network.healthPort = 18021; $changed = $true }
    } catch {
        $s.network.healthPort = 18021
        $changed = $true
    }
    if (-not $s.PSObject.Properties["scope"]) {
        $s | Add-Member NoteProperty scope ([pscustomobject]@{ mode = "workspace"; allowedPaths = @(); allowFullComputer = $false })
        $changed = $true
    }
    if (-not $s.PSObject.Properties["permissions"]) {
        $s | Add-Member NoteProperty permissions ([pscustomobject]@{ fileAccess = "ask"; terminalAccess = "ask"; destructiveActions = "ask"; sessionApproval = $false; alwaysAllow = $false })
        $changed = $true
    }
    if (-not $s.PSObject.Properties["terminal"]) {
        $s | Add-Member NoteProperty terminal ([pscustomobject]@{
            mode = "workspace"; unknownExecutable = "approval"; shells = "approval"; destructive = "approval";
            maxConcurrentJobs = 4; maxRuntimeSeconds = 1800; maxOutputBytes = 5242880
        })
        $changed = $true
    }
    if (-not $s.PSObject.Properties["stitch"]) {
        $s | Add-Member NoteProperty stitch ([pscustomobject]@{ defaultOutputDir = ".gpt/stitch" })
        $changed = $true
    }
    # Workspace policy: every fresh install defaults to ./workspace relative
    # to this Tunnel root. Preserve a path only when the user has explicitly
    # selected a custom workspace. Migrate stale V4.1/V4.1-New defaults so a
    # copied settings file can never silently redirect this installation.
    $defaultWorkspace = Join-Path $Root "workspace"
    Ensure-Dir $defaultWorkspace
    $currentWorkspace = [string]$s.workspace
    $looksLikeLegacyDefault = $false
    if (-not [string]::IsNullOrWhiteSpace($currentWorkspace)) {
        try {
            $legacyFull = [System.IO.Path]::GetFullPath($currentWorkspace)
            if ($legacyFull -match '(?i)[\\/]Tunnel-V4\.1(?:-New)?[\\/]workspace$') { $looksLikeLegacyDefault = $true }
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($currentWorkspace) -or $looksLikeLegacyDefault) {
        $s.workspace = './workspace'
        $changed = $true
    } elseif (-not [System.IO.Path]::IsPathRooted($currentWorkspace)) {
        $resolvedWorkspace = [System.IO.Path]::GetFullPath((Join-Path $Root ([string]$s.workspace)))
        if (-not (Test-Path -LiteralPath $resolvedWorkspace -PathType Container)) { New-Item -ItemType Directory -Force -Path $resolvedWorkspace | Out-Null }
    } elseif (-not (Test-Path -LiteralPath ([string]$s.workspace) -PathType Container)) {
        New-Item -ItemType Directory -Force -Path ([string]$s.workspace) | Out-Null
    }
    if ($changed) { Save-Settings $s }
    return $s
}

function Get-PidFromFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $raw = Read-TextShared $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }
        return [int]$raw.Trim()
    } catch { return 0 }
}

function Test-PidAlive([int]$ProcessId) {
    if ($ProcessId -le 0) { return $false }
    try { Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Get-ProcessInfo([int]$ProcessId) {
    if ($ProcessId -le 0) { return $null }
    $info = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if (-not $info) { $info = Get-WmiObject Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue }
    return $info
}

function Test-ManagedTunnelPid([int]$ProcessId) {
    if ($ProcessId -le 0) { return $false }
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        $actualPath = $null
        try { $actualPath = [string]$proc.Path } catch {}
        if ([string]::IsNullOrWhiteSpace($actualPath)) {
            try { $actualPath = [string]$proc.MainModule.FileName } catch {}
        }
        if ([string]::IsNullOrWhiteSpace($actualPath)) { return $false }
        $actual = [System.IO.Path]::GetFullPath($actualPath)
        $expected = [System.IO.Path]::GetFullPath($TunnelExe)
        return [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-ManagedTunnelHostPid([int]$ProcessId) {
    if (-not (Test-PidAlive $ProcessId)) { return $false }
    $info = Get-ProcessInfo $ProcessId
    if (-not $info) { return $false }
    $line = [string]$info.CommandLine
    if ([string]::IsNullOrWhiteSpace($line)) { return $false }
    return $line.IndexOf($TunnelHost, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-TunnelPid {
    $id = Get-PidFromFile $TunnelPidFile
    if ($id -gt 0 -and (Test-ManagedTunnelPid $id)) { return $id }
    if (Test-Path -LiteralPath $TunnelPidFile) { Remove-Item -LiteralPath $TunnelPidFile -Force -ErrorAction SilentlyContinue }
    return 0
}

function Get-TunnelHostPid {
    $id = Get-PidFromFile $TunnelHostPidFile
    if ($id -gt 0 -and (Test-ManagedTunnelHostPid $id)) { return $id }
    if (Test-Path -LiteralPath $TunnelHostPidFile) { Remove-Item -LiteralPath $TunnelHostPidFile -Force -ErrorAction SilentlyContinue }
    return 0
}

function Get-HealthPort {
    $s = Normalize-Settings
    $port = 18021
    try { $port = [int]$s.network.healthPort } catch {}
    if ($port -lt 1 -or $port -gt 65535) { $port = 18021 }
    return $port
}

function Test-TunnelHealth {
    $client = $null
    try {
        $port = Get-HealthPort
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect("127.0.0.1", $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(250)) { return $false }
        $client.EndConnect($async)
        return $client.Connected
    } catch { return $false } finally { if ($client) { $client.Close() } }
}

function Ensure-Dependencies {
    $node = Resolve-Exe 'node.exe'
    if (-not $node) { throw "Node.js was not found. Checked PATH and standard Windows install locations." }

    # V1.2 uses a dependency-free Node compatibility MCP host. Older manager
    # logic expected a separate stitch-async-mcp npm project to exist and
    # attempted npm install from that directory. A fresh V1.2 checkout
    # does not need npm at startup, so never run npm install as a prerequisite.
    if (-not (Test-Path -LiteralPath $McpServer -PathType Leaf)) {
        throw "Missing MCP server entrypoint: $McpServer"
    }
}

function Get-HealthPortOwner {
    $port = Get-HealthPort
    try {
        $connections = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop)
        foreach ($c in $connections) {
            $ownerPid = [int]$c.OwningProcess
            if ($ownerPid -le 0) { continue }
            $proc = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
            $path = ""
            try { $path = [string]$proc.Path } catch {}
            if ([string]::IsNullOrWhiteSpace($path)) { try { $path = [string]$proc.MainModule.FileName } catch {} }
            [pscustomobject]@{ PID=$ownerPid; Name=[string]$proc.ProcessName; Path=$path }
        }
    } catch {}
}

function Clear-StaleManagedTunnel {
    $owners = @(Get-HealthPortOwner)
    foreach ($owner in $owners) {
        if ([string]::Equals([string]$owner.Path, [string]$TunnelExe, [System.StringComparison]::OrdinalIgnoreCase)) {
            try { & taskkill.exe /PID ([int]$owner.PID) /T /F 2>$null | Out-Null } catch {}
            Start-Sleep -Milliseconds 200
        }
    }
    foreach ($f in @($TunnelPidFile,$TunnelHostPidFile)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    return @(Get-HealthPortOwner)
}

function Start-Tunnel {
    Normalize-Settings | Out-Null

    # Process-path inspection can be denied by Windows even for a process that
    # owns our health port. Do not turn that harmless inspection failure into
    # a failed START after the tunnel is actually healthy.
    $existing = 0
    try { $existing = Get-TunnelPid } catch { $existing = 0 }
    if ($existing -gt 0) { return $existing }

    if (Test-TunnelHealth) {
        $remaining = @(Clear-StaleManagedTunnel)
        if (Test-TunnelHealth) {
            $ownerText = ""
            if ($remaining.Count -gt 0) { $ownerText = (($remaining | ForEach-Object { "$($_.Name) PID $($_.PID)" }) -join ", ") }
            if ([string]::IsNullOrWhiteSpace($ownerText)) { $ownerText = "unknown process" }
            throw ("Port {0} is already in use by {1}. Stop that process or choose another port in Settings." -f (Get-HealthPort), $ownerText)
        }
    }
    if (-not (Test-Path -LiteralPath $TunnelExe)) { throw "Missing tunnel-client.exe: $TunnelExe" }
    if (-not (Test-Path -LiteralPath $TunnelHost)) { throw "Missing tunnel host: $TunnelHost" }
    if (-not (Test-Path -LiteralPath $TunnelProfile)) { throw "Missing tunnel profile: $TunnelProfile" }
    if (-not (Test-Path -LiteralPath $TunnelEnv)) { throw "Missing OpenAI tunnel key file: $TunnelEnv" }
    Ensure-Dependencies

    Ensure-Dir $LogsDir
    foreach ($f in @($StdoutLog, $StderrLog, $TunnelHostLog)) {
        try { Write-TextNoBom $f "" } catch {}
    }
    foreach ($f in @($TunnelPidFile, $TunnelHostPidFile)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }

    $env:AI_MCP_CONFIG = $SettingsFile
    $env:AI_MCP_RUNTIME = $RuntimeDir
    $env:STITCH_API_KEY_FILE = $StitchKeyFile

    $powershell = Resolve-Exe 'powershell.exe'
    if (-not $powershell) { throw "Windows PowerShell was not found." }
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$TunnelHost`""
    $hostProcess = Start-Process -FilePath $powershell -ArgumentList $argLine -WindowStyle Hidden -PassThru
    Write-TextNoBom $TunnelHostPidFile ([string]$hostProcess.Id)

    $deadline = (Get-Date).AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 100
        if (-not (Test-PidAlive $hostProcess.Id)) {
            throw "Tunnel host exited during startup. Check runtime\logs\tunnel-host.log and tunnel.stderr.log"
        }
        $id = 0
        try { $id = Get-TunnelPid } catch { $id = 0 }
        if ($id -gt 0 -and (Test-TunnelHealth)) { return $id }

        # Fallback: health is authoritative for startup readiness. If Windows
        # blocks executable-path inspection, recover the PID from the process
        # listening on the configured health port instead of reporting a false
        # START ERROR while leaving a healthy tunnel running.
        if (Test-TunnelHealth) {
            $owners = @(Get-HealthPortOwner)
            $tunnelOwner = $owners | Where-Object { [string]$_.Name -ieq 'tunnel-client' } | Select-Object -First 1
            if ($tunnelOwner) {
                $id = [int]$tunnelOwner.PID
                if ($id -gt 0) {
                    try { Write-TextNoBom $TunnelPidFile ([string]$id) } catch {}
                    return $id
                }
            }
        }
    } while ((Get-Date) -lt $deadline)

    $id = 0
    try { $id = Get-TunnelPid } catch { $id = 0 }
    if ($id -gt 0) { return $id }

    if (Test-TunnelHealth) {
        $owners = @(Get-HealthPortOwner)
        $tunnelOwner = $owners | Where-Object { [string]$_.Name -ieq 'tunnel-client' } | Select-Object -First 1
        if ($tunnelOwner -and [int]$tunnelOwner.PID -gt 0) {
            $id = [int]$tunnelOwner.PID
            try { Write-TextNoBom $TunnelPidFile ([string]$id) } catch {}
            return $id
        }
    }

    throw "Tunnel did not become ready. Check runtime\logs\tunnel-host.log and tunnel.stderr.log"
}

function Mark-InterruptedJobs {
    $now = (Get-Date).ToUniversalTime().ToString("o")
    if (Test-Path -LiteralPath $TerminalJobsDir) {
        Get-ChildItem -LiteralPath $TerminalJobsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $job = (Read-TextShared $_.FullName) | ConvertFrom-Json
                if ($job.status -eq "starting" -or $job.status -eq "running" -or $job.status -eq "stopping") {
                    $job.status = "aborted"
                    $job.completedAt = $now
                    $job.error = [pscustomobject]@{ name = "StoppedByTUI"; message = "Stopped because the managed tunnel/TUI was shut down." }
                    Write-JsonNoBom $_.FullName $job
                }
            } catch {}
        }
    }
    if (Test-Path -LiteralPath $StitchJobsDir) {
        Get-ChildItem -LiteralPath $StitchJobsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $job = (Read-TextShared $_.FullName) | ConvertFrom-Json
                if ($job.status -eq "queued" -or $job.status -eq "running") {
                    $job.status = "failed"
                    $job.failedAt = $now
                    $job.error = [pscustomobject]@{ name = "StoppedByTUI"; message = "Stitch worker stopped because the managed tunnel/TUI was shut down." }
                    Write-JsonNoBom $_.FullName $job
                }
            } catch {}
        }
    }
}

function Stop-Tunnel {
    $hostId = Get-TunnelHostPid
    $childId = Get-TunnelPid

    if ($hostId -gt 0) {
        try { & taskkill.exe /PID $hostId /T /F 2>$null | Out-Null } catch {}
    } elseif ($childId -gt 0) {
        try { & taskkill.exe /PID $childId /T /F 2>$null | Out-Null } catch {}
    }
    Start-Sleep -Milliseconds 180
    Mark-InterruptedJobs
    foreach ($f in @($TunnelPidFile, $TunnelHostPidFile)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

function Restart-Tunnel {
    Stop-Tunnel
    Start-Sleep -Milliseconds 250
    return (Start-Tunnel)
}

function Get-PendingApprovals {
    Ensure-Dir $ApprovalsDir
    $now = Get-Date
    $items = @()
    Get-ChildItem -LiteralPath $ApprovalsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $obj = (Read-TextShared $_.FullName) | ConvertFrom-Json
            if ($obj.status -eq "pending" -and $obj.expiresAt) {
                if ([DateTime]::Parse([string]$obj.expiresAt).ToUniversalTime() -lt $now.ToUniversalTime()) {
                    $obj.status = "expired"
                    $obj.decidedAt = (Get-Date).ToUniversalTime().ToString("o")
                    Write-JsonNoBom $_.FullName $obj
                }
            }
            if ($obj.status -eq "pending") { $items += $obj }
        } catch {}
    }
    return @($items | Sort-Object createdAt)
}

function Get-ApprovalByIndex([int]$RequestedIndex) {
    $items = @(Get-PendingApprovals)
    if ($items.Count -eq 0) { return $null }
    if ($RequestedIndex -lt 0) { $RequestedIndex = 0 }
    $normalized = $RequestedIndex % $items.Count
    return $items[$normalized]
}

function Set-ApprovalDecision([string]$ApprovalId, [string]$Decision) {
    if ($ApprovalId -notmatch '^[0-9a-fA-F-]{36}$') { throw "Invalid approval id" }
    $file = Join-Path $ApprovalsDir ($ApprovalId + ".json")
    if (-not (Test-Path -LiteralPath $file)) { throw "Approval not found" }
    $obj = (Read-TextShared $file) | ConvertFrom-Json
    if ($obj.status -ne "pending") { throw "Approval is not pending (status: $($obj.status))" }
    $obj.status = $Decision
    $obj.decidedAt = (Get-Date).ToUniversalTime().ToString("o")
    Write-JsonNoBom $file $obj
    if ($Decision -eq "approved" -and (Test-Path -LiteralPath $ApprovalRunner)) {
        $node = Resolve-Exe 'node.exe'
        if ($node) {
            try {
                $args = '"' + $ApprovalRunner.Replace('"','') + '" ' + $ApprovalId
                $safeServerDir = Get-SafeWorkingDirectory $ServerDir
                Start-Process -FilePath $node -ArgumentList $args -WorkingDirectory $safeServerDir -WindowStyle Hidden | Out-Null
            } catch {
                # Keep status=approved so approval_execute can still run it if auto-execution could not start.
            }
        }
    }
}

function Get-RunningTerminalJobCount {
    if (-not (Test-Path -LiteralPath $TerminalJobsDir)) { return 0 }
    $count = 0
    Get-ChildItem -LiteralPath $TerminalJobsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $job = (Read-TextShared $_.FullName) | ConvertFrom-Json
            if ($job.status -eq "starting" -or $job.status -eq "running" -or $job.status -eq "stopping") { $count++ }
        } catch {}
    }
    return $count
}

function Render-StatusEnv {
    $s = Normalize-Settings
    $pidValue = Get-TunnelPid
    $tunnelState = "STOPPED"
    if ($pidValue -gt 0) { $tunnelState = "RUNNING" }
    $health = "OFFLINE"
    if ($pidValue -gt 0 -and (Test-TunnelHealth)) { $health = "ONLINE" }
    $keyState = "MISSING"
    if ((Test-Path -LiteralPath $StitchKeyFile) -and -not [string]::IsNullOrWhiteSpace((Read-TextShared $StitchKeyFile))) { $keyState = "READY" }
    "TUNNEL_STATUS=$tunnelState"
    "HEALTH=$health"
    "TUNNEL_PID=$pidValue"
    $filesState = if ($s.features.files) { "ON" } else { "OFF" }
    $terminalState = if ($s.features.terminal) { "ON" } else { "OFF" }
    $extendedState = if ($s.features.extended) { "ON" } else { "OFF" }
    $stitchState = if ($s.features.stitch) { "ON" } else { "OFF" }
    "FILES=$filesState"
    "TERMINAL=$terminalState"
    "POWER=$extendedState"
    "STITCH=$stitchState"
    "WORKSPACE=$($s.workspace)"
    "PENDING=$(@(Get-PendingApprovals).Count)"
    "RUNNING_JOBS=$(Get-RunningTerminalJobCount)"
    "STITCH_KEY=$keyState"
}

function Toggle-Feature([string]$Name) {
    if ($Name -notin @("files", "terminal", "extended", "stitch")) { throw "Unknown feature: $Name" }
    $s = Normalize-Settings
    $current = [bool]$s.features.$Name
    $s.features.$Name = -not $current
    Save-Settings $s
    if ((Get-TunnelPid) -gt 0) { Restart-Tunnel | Out-Null }
    return (-not $current)
}

function Pick-Workspace {
    $s = Normalize-Settings
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the single project folder ChatGPT can access"
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath ([string]$s.workspace)) { $dialog.SelectedPath = [string]$s.workspace }
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        $newPath = [System.IO.Path]::GetFullPath($dialog.SelectedPath)
        if (-not (Test-Path -LiteralPath $newPath -PathType Container)) { throw "Selected path is not a directory" }
        $wasRunning = (Get-TunnelPid) -gt 0
        $s.workspace = $newPath
        Save-Settings $s
        if ($wasRunning) { Restart-Tunnel | Out-Null }
        "CHANGED=1"
        "WORKSPACE=$newPath"
    } else {
        "CHANGED=0"
    }
}

function Set-StitchKey {
    $secure = Read-Host "Enter Stitch API key (input hidden)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    if ([string]::IsNullOrWhiteSpace($plain)) { throw "Key cannot be empty" }
    Write-TextNoBom $StitchKeyFile ($plain.Trim() + "`r`n")
    if ((Get-TunnelPid) -gt 0) { Restart-Tunnel | Out-Null }
}

function Tail-Log([string]$Which) {
    switch ($Which.ToLowerInvariant()) {
        "tunnel" {
            "--- tunnel stdout ---"
            if (Test-Path -LiteralPath $StdoutLog) { Get-TailShared $StdoutLog 70 }
            ""
            "--- tunnel stderr ---"
            if (Test-Path -LiteralPath $StderrLog) { Get-TailShared $StderrLog 70 }
            ""
            "--- tunnel host ---"
            if (Test-Path -LiteralPath $TunnelHostLog) { Get-TailShared $TunnelHostLog 30 }
        }
        "activity" {
            if (-not (Test-Path -LiteralPath $ActivityLog)) { "No MCP activity yet."; return }
            foreach ($line in @(Get-TailShared $ActivityLog 120)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $e = $line | ConvertFrom-Json
                    $t = ([DateTime]::Parse([string]$e.time)).ToLocalTime().ToString("HH:mm:ss")
                    $detail = ([string]$e.summary -replace '[\r\n\t]+',' ').Trim()
                    if ($detail.Length -gt 100) { $detail = $detail.Substring(0,97) + "..." }
                    if ([string]$e.phase -eq "ERROR" -and $e.error) { $detail += " | " + ([string]$e.error) }
                    "[$t] $($e.phase) $($e.tool) $detail"
                } catch { $line }
            }
        }
        "setup" {
            if (Test-Path -LiteralPath $SetupLog) { Get-TailShared $SetupLog 120 }
        }
        "job" {
            $job = Get-ChildItem -LiteralPath $TerminalJobsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $job) { "No terminal jobs yet."; return }
            $obj = (Read-TextShared $job.FullName) | ConvertFrom-Json
            "Job: $($obj.id) [$($obj.status)]"
            "Command: $($obj.displayCommand)"
            "CWD: $($obj.cwd)"
            ""
            "--- stdout ---"
            if (Test-Path -LiteralPath $obj.stdoutFile) { Get-TailShared ([string]$obj.stdoutFile) 80 }
            ""
            "--- stderr ---"
            if (Test-Path -LiteralPath $obj.stderrFile) { Get-TailShared ([string]$obj.stderrFile) 80 }
        }
        default { throw "Unknown log: $Which" }
    }
}


function Get-LatestTerminalJob {
    if (-not (Test-Path -LiteralPath $TerminalJobsDir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $TerminalJobsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($file in $files) {
        try { return ((Read-TextShared $file.FullName) | ConvertFrom-Json) } catch {}
    }
    return $null
}

function Get-LatestStitchJob {
    if (-not (Test-Path -LiteralPath $StitchJobsDir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $StitchJobsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($file in $files) {
        try { return ((Read-TextShared $file.FullName) | ConvertFrom-Json) } catch {}
    }
    return $null
}

function Compact([string]$Text, [int]$Width) {
    if ($null -eq $Text) { return "" }
    $v = ($Text -replace '[\r\n\t]+',' ').Trim()
    if ($v.Length -gt $Width) { return $v.Substring(0, [Math]::Max(1,$Width-3)) + "..." }
    return $v
}

function Get-ApprovalSeconds($Item) {
    if (-not $Item -or -not $Item.expiresAt) { return 0 }
    try {
        return [Math]::Max(0,[int][Math]::Ceiling((([DateTime]::Parse([string]$Item.expiresAt)).ToUniversalTime()-(Get-Date).ToUniversalTime()).TotalSeconds))
    } catch { return 0 }
}

function Pad-Line([string]$Text, [int]$Width = 104) {
    $v = Compact $Text $Width
    return $v.PadRight($Width)
}


function Get-UiState {
    $s = Normalize-Settings
    $pidValue = Get-TunnelPid
    $running = $pidValue -gt 0
    $health = $false
    if ($running) { $health = Test-TunnelHealth }
    $keyReady = (Test-Path -LiteralPath $StitchKeyFile) -and -not [string]::IsNullOrWhiteSpace((Read-TextShared $StitchKeyFile))
    $pending = @(Get-PendingApprovals | Select-Object -First 20 | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.id
            kind = [string]$_.kind
            risk = [string]$_.risk
            title = [string]$_.title
            summary = [string]$_.summary
            createdAt = [string]$_.createdAt
            expiresAt = [string]$_.expiresAt
        }
    })

    $events = @()
    if (Test-Path -LiteralPath $ActivityLog) {
        foreach ($line in @(Get-TailShared $ActivityLog 80)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $e = $line | ConvertFrom-Json
                $events += [pscustomobject]@{
                    time = [string]$e.time
                    phase = [string]$e.phase
                    tool = [string]$e.tool
                    summary = [string]$e.summary
                    error = [string]$e.error
                }
            } catch {}
        }
    }
    $events = @($events | Select-Object -Last 30)

    $term = Get-LatestTerminalJob
    $st = Get-LatestStitchJob
    $workType = "idle"
    $workStatus = "idle"
    $workText = "Waiting for GPT requests"
    if ($term -and ([string]$term.status -in @("starting","running","stopping"))) {
        $workType = "terminal"
        $workStatus = [string]$term.status
        $workText = [string]$term.displayCommand
    } elseif ($st -and ([string]$st.status -in @("queued","running"))) {
        $workType = "stitch"
        $workStatus = [string]$st.status
        $project = ""
        try { $project = [string]$st.input.projectId } catch {}
        $workText = "project=" + $project
    }

    [pscustomobject]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        tunnel = [pscustomobject]@{
            running = $running
            online = [bool]$health
            pid = $pidValue
        }
        features = [pscustomobject]@{
            files = [bool]$s.features.files
            terminal = [bool]$s.features.terminal
            extended = [bool]$s.features.extended
            stitch = [bool]$s.features.stitch
        }
        workspace = [string]$s.workspace
        runningJobs = (Get-RunningTerminalJobCount)
        stitchKeyReady = [bool]$keyReady
        pending = $pending
        work = [pscustomobject]@{
            type = $workType
            status = $workStatus
            text = $workText
        }
        events = $events
    } | ConvertTo-Json -Depth 8 -Compress
}

function Render-Dashboard {
    $s = Normalize-Settings
    $pidValue = Get-TunnelPid
    $running = $pidValue -gt 0
    $health = Test-TunnelHealth
    $tunnelText = if ($running) { "RUNNING" } else { "STOPPED" }
    $healthText = if ($health) { "ONLINE" } else { "OFFLINE" }
    $filesText = if ($s.features.files) { "ON" } else { "OFF" }
    $terminalText = if ($s.features.terminal) { "ON" } else { "OFF" }
    $extendedText = if ($s.features.extended) { "ON" } else { "OFF" }
    $stitchText = if ($s.features.stitch) { "ON" } else { "OFF" }
    $jobs = Get-RunningTerminalJobCount
    $pending = @(Get-PendingApprovals)
    $nowText = (Get-Date).ToString("HH:mm:ss")
    $workspace = Compact ([string]$s.workspace) 91

    $top = "+----------------------------------------------------------------------------------------------------------+"
    $divider = "+----------------------------------------------------------------------------------------------------------+"
    $top
    "|" + (Pad-Line ("  AI LOCAL WORKSPACE                                                      " + $nowText) 106) + "|"
    $divider
    "|" + (Pad-Line ("  Tunnel   " + $tunnelText + " / " + $healthText + "    PID " + $pidValue + "      Tools   Files " + $filesText + "   Terminal " + $terminalText + " (" + $jobs + ")   Power " + $extendedText + "   Stitch " + $stitchText) 106) + "|"
    "|" + (Pad-Line ("  Project  " + $workspace) 106) + "|"
    $divider

    $term = Get-LatestTerminalJob
    $st = Get-LatestStitchJob
    $work = "Idle - waiting for GPT requests"
    if ($term -and ([string]$term.status -in @("starting","running","stopping"))) {
        $work = "Terminal [" + [string]$term.status + "]  " + (Compact ([string]$term.displayCommand) 72)
    } elseif ($st -and ([string]$st.status -in @("queued","running"))) {
        $project = ""; try { $project = [string]$st.input.projectId } catch {}
        $work = "Stitch [" + [string]$st.status + "]  project=" + (Compact $project 68)
    }
    "|" + (Pad-Line "  CURRENT WORK" 106) + "|"
    "|" + (Pad-Line ("  " + $work) 106) + "|"
    $divider

    if ($pending.Count -gt 0) {
        $item = $pending[0]
        $sec = Get-ApprovalSeconds $item
        "|" + (Pad-Line "  APPROVAL REQUIRED" 106) + "|"
        "|" + (Pad-Line ("  [" + [string]$item.risk + "] " + (Compact ([string]$item.title) 66) + "    expires in " + $sec + "s") 106) + "|"
        "|" + (Pad-Line ("  " + (Compact ([string]$item.summary) 101)) 106) + "|"
        "|" + (Pad-Line ("  Press [A] now to review.  Pending queue: " + $pending.Count) 106) + "|"
    } else {
        "|" + (Pad-Line "  APPROVAL" 106) + "|"
        "|" + (Pad-Line "  No approval waiting." 106) + "|"
    }
    $divider
    "|" + (Pad-Line "  LIVE ACTIVITY" 106) + "|"
    $events = @()
    if (Test-Path -LiteralPath $ActivityLog) {
        foreach ($line in @(Get-TailShared $ActivityLog 40)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $events += ($line | ConvertFrom-Json) } catch {}
        }
    }
    $events = @($events | Select-Object -Last 6)
    if ($events.Count -eq 0) {
        "|" + (Pad-Line "  No MCP activity yet." 106) + "|"
        1..5 | ForEach-Object { "|" + (" " * 106) + "|" }
    } else {
        foreach ($e in $events) {
            $t = "--:--:--"; try { $t = ([DateTime]::Parse([string]$e.time)).ToLocalTime().ToString("HH:mm:ss") } catch {}
            $mark = switch ([string]$e.phase) { "START" { ">" } "OK" { "+" } "ERROR" { "!" } default { "-" } }
            $detail = Compact ([string]$e.summary) 65
            if ([string]$e.phase -eq "ERROR" -and $e.error) { $detail = Compact (($detail + " | " + [string]$e.error).Trim()) 65 }
            "|" + (Pad-Line ("  " + $t + "  " + $mark + "  " + (Compact ([string]$e.tool) 28).PadRight(28) + " " + $detail) 106) + "|"
        }
        $missing = 6 - $events.Count
        if ($missing -gt 0) { 1..$missing | ForEach-Object { "|" + (" " * 106) + "|" } }
    }
    $divider
    "|" + (Pad-Line "  [A] Approvals   [G] Tunnel   [R] Restart   [L] Logs   [S] Settings   [O] Open Project   [Q] Quit" 106) + "|"
    $msg = [string]$env:AI_TUI_MESSAGE
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "Ready" }
    "|" + (Pad-Line ("  " + (Compact $msg 96)) 106) + "|"
    $top
}


function Render-SettingsPage {
    $s = Normalize-Settings
    $filesText = if ($s.features.files) { "ON" } else { "OFF" }
    $terminalText = if ($s.features.terminal) { "ON" } else { "OFF" }
    $extendedText = if ($s.features.extended) { "ON" } else { "OFF" }
    $stitchText = if ($s.features.stitch) { "ON" } else { "OFF" }
    $keyText = "MISSING"
    if ((Test-Path -LiteralPath $StitchKeyFile) -and -not [string]::IsNullOrWhiteSpace((Read-TextShared $StitchKeyFile))) { $keyText = "READY" }
    $top = "+----------------------------------------------------------------------------------------------------------+"
    $top
    "|" + (Pad-Line "  SETTINGS" 106) + "|"
    $top
    "|" + (Pad-Line "  FEATURES" 106) + "|"
    "|" + (Pad-Line ("     [F] Files       " + $filesText) 106) + "|"
    "|" + (Pad-Line ("     [T] Terminal    " + $terminalText) 106) + "|"
    "|" + (Pad-Line ("     [X] Power tools " + $extendedText) 106) + "|"
    "|" + (Pad-Line ("     [C] Stitch      " + $stitchText) 106) + "|"
    "|" + (" " * 106) + "|"
    "|" + (Pad-Line "  PROJECT" 106) + "|"
    "|" + (Pad-Line "     [W] Change workspace" 106) + "|"
    "|" + (Pad-Line ("     " + (Compact ([string]$s.workspace) 98)) 106) + "|"
    "|" + (" " * 106) + "|"
    "|" + (Pad-Line "  SYSTEM" 106) + "|"
    "|" + (Pad-Line ("     [K] Set Stitch API key       " + $keyText) 106) + "|"
    "|" + (Pad-Line "     [D] Doctor / diagnostics" 106) + "|"
    "|" + (Pad-Line "     [E] Last error" 106) + "|"
    "|" + (Pad-Line "     [N] Restart Windows approval notifier" 106) + "|"
    $top
    "|" + (Pad-Line "  [B] Back" 106) + "|"
    $top
}

function Get-LatestWriteTicks([string]$Dir, [string]$Filter = "*.json") {
    if (-not (Test-Path -LiteralPath $Dir)) { return 0 }
    $f = Get-ChildItem -LiteralPath $Dir -Filter $Filter -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($f) { return $f.LastWriteTimeUtc.Ticks }
    return 0
}

function Get-DashboardSignature {
    $s = Normalize-Settings
    $pidValue = Get-TunnelPid
    $health = if (Test-TunnelHealth) { 1 } else { 0 }
    $pending = @(Get-PendingApprovals)
    $countdown = 0
    if ($pending.Count -gt 0) { $countdown = Get-ApprovalSeconds $pending[0] }
    $activityTicks = 0; if (Test-Path -LiteralPath $ActivityLog) { $activityTicks = (Get-Item -LiteralPath $ActivityLog).LastWriteTimeUtc.Ticks }
    $jobTicks = [Math]::Max((Get-LatestWriteTicks $TerminalJobsDir),(Get-LatestWriteTicks $StitchJobsDir))
    $raw = "$pidValue|$health|$($s.features.files)|$($s.features.terminal)|$($s.features.extended)|$($s.features.stitch)|$($s.workspace)|$($pending.Count)|$countdown|$activityTicks|$jobTicks"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","")
    } finally { $sha.Dispose() }
}

function Render-Approval([int]$RequestedIndex) {
    $items = @(Get-PendingApprovals)
    $item = Get-ApprovalByIndex $RequestedIndex
    if (-not $item) { "NONE=1"; "No pending approvals."; return }
    $seconds = Get-ApprovalSeconds $item
    "Approval $((($RequestedIndex % $items.Count) + 1)) / $($items.Count)"
    "ID:       $($item.id)"
    "Risk:     $($item.risk)"
    "Type:     $($item.kind)"
    "Title:    $($item.title)"
    "Expires:  ${seconds}s remaining"
    ""
    "Request:"
    [string]$item.summary
}

function Test-ManagedNotifierPid([int]$ProcessId) {
    if (-not (Test-PidAlive $ProcessId)) { return $false }
    $info = Get-ProcessInfo $ProcessId
    if (-not $info) { return $false }
    $line = [string]$info.CommandLine
    if ([string]::IsNullOrWhiteSpace($line)) { return $false }
    return $line.IndexOf($NotifierScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Start-Notifier {
    if (-not (Test-Path -LiteralPath $NotifierScript)) { return }
    $current = Get-ProcessInfo $PID
    if (-not $current) { return }
    $cmdPid = [int]$current.ParentProcessId
    if ($cmdPid -le 0) { return }
    $existing = Get-PidFromFile $NotifierPidFile
    if ($existing -gt 0 -and (Test-ManagedNotifierPid $existing)) { return }
    $argLine = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$NotifierScript`" -ParentPid $cmdPid -ApprovalsDir `"$ApprovalsDir`""
    $powershell = Resolve-Exe 'powershell.exe'
    if (-not $powershell) { throw "Windows PowerShell was not found." }
    $p = Start-Process -FilePath $powershell -ArgumentList $argLine -WindowStyle Hidden -PassThru
    Write-TextNoBom $NotifierPidFile ([string]$p.Id)
}

function Stop-Notifier {
    $id = Get-PidFromFile $NotifierPidFile
    if ($id -gt 0 -and (Test-ManagedNotifierPid $id)) {
        try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch {}
    }
    if (Test-Path -LiteralPath $NotifierPidFile) { Remove-Item -LiteralPath $NotifierPidFile -Force -ErrorAction SilentlyContinue }
}

function Doctor {
    $s = Normalize-Settings
    function Mark($ok, $label, $detail) {
        if ($ok) { "[OK]   $label - $detail" } else { "[FAIL] $label - $detail" }
    }
    $nodePath = Resolve-Exe 'node.exe'
    $npmPath = Resolve-Exe 'npm.cmd'
    $psPath = Resolve-Exe 'powershell.exe'
    $gitPath = Resolve-Exe 'git.exe'
    $pythonPath = Resolve-Exe 'python.exe'
    Mark ([bool]$nodePath) "Node.js" $nodePath
    Mark ([bool]$npmPath) "npm" $npmPath
    Mark ([bool]$psPath) "PowerShell" $psPath
    Mark ([bool]$gitPath) "Git" $gitPath
    Mark ([bool]$pythonPath) "Python" $pythonPath
    Mark (Test-Path -LiteralPath $TunnelExe) "Tunnel client" $TunnelExe
    Mark (Test-Path -LiteralPath $TunnelProfile) "Tunnel profile" $TunnelProfile
    Mark (Test-Path -LiteralPath $TunnelEnv) "OpenAI key" $TunnelEnv
    Mark (Test-Path -LiteralPath ([string]$s.workspace) -PathType Container) "Workspace" ([string]$s.workspace)
    $keyReady = (Test-Path -LiteralPath $StitchKeyFile) -and -not [string]::IsNullOrWhiteSpace((Read-TextShared $StitchKeyFile))
    Mark $keyReady "Stitch key" $StitchKeyFile
    $hostPidValue = Get-TunnelHostPid
    Mark ($hostPidValue -gt 0) "Tunnel host" ("PID " + $hostPidValue)
    $pidValue = Get-TunnelPid
    Mark ($pidValue -gt 0) "Tunnel process" ("PID " + $pidValue)
    Mark (Test-TunnelHealth) "Tunnel health" (([string]$s.network.healthHost) + ":" + ([string](Get-HealthPort)))
    if ($nodePath -and (Test-Path -LiteralPath $SelfTestFile)) {
        try {
            $selfOut = (& $nodePath $SelfTestFile 2>&1 | Out-String).Trim()
            $selfOk = ($LASTEXITCODE -eq 0 -and $selfOut -match 'RESULT:\s*PASS')
            Mark $selfOk "MCP self-test" (Compact $selfOut 72)
        } catch { Mark $false "MCP self-test" $_.Exception.Message }
    } else {
        Mark $false "MCP self-test" "Node or self-test.mjs missing"
    }
    ""
    "Files=$($s.features.files) Terminal=$($s.features.terminal) Power=$($s.features.extended) Stitch=$($s.features.stitch)"
}

function Test-ManagedWatchdogPid([int]$ProcessId) {
    if (-not (Test-PidAlive $ProcessId)) { return $false }
    $info = Get-ProcessInfo $ProcessId
    if (-not $info) { return $false }
    $line = [string]$info.CommandLine
    if ([string]::IsNullOrWhiteSpace($line)) { return $false }
    return $line.IndexOf($PSCommandPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $line -match '(?i)\bwatch\b'
}

function Start-Watchdog {
    $current = Get-ProcessInfo $PID
    if (-not $current) { throw "Could not identify the TUI parent process" }
    $cmdPid = [int]$current.ParentProcessId
    if ($cmdPid -le 0) { throw "Could not identify the TUI cmd.exe PID" }

    $existingUi = Get-PidFromFile $UiPidFile
    if ($existingUi -gt 0 -and (Test-PidAlive $existingUi) -and $existingUi -ne $cmdPid) {
        throw "Another AI Local Workspace TUI is already running (PID $existingUi). Close it before opening a second controller."
    }

    $existingWatchdog = Get-PidFromFile $WatchdogPidFile
    if ($existingWatchdog -gt 0 -and (Test-ManagedWatchdogPid $existingWatchdog) -and $existingUi -eq $cmdPid) {
        return
    }
    if ($existingWatchdog -gt 0 -and (Test-ManagedWatchdogPid $existingWatchdog)) {
        try { Stop-Process -Id $existingWatchdog -Force -ErrorAction SilentlyContinue } catch {}
    }

    Write-TextNoBom $UiPidFile ([string]$cmdPid)
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" watch -ParentPid $cmdPid"
    $powershell = Resolve-Exe 'powershell.exe'
    if (-not $powershell) { throw "Windows PowerShell was not found." }
    $p = Start-Process -FilePath $powershell -ArgumentList $argLine -WindowStyle Hidden -PassThru
    Write-TextNoBom $WatchdogPidFile ([string]$p.Id)
}

function Stop-Watchdog {
    Stop-Notifier
    $id = Get-PidFromFile $WatchdogPidFile
    if ($id -gt 0 -and (Test-ManagedWatchdogPid $id)) {
        try { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue } catch {}
    }
    foreach ($f in @($WatchdogPidFile, $UiPidFile)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

function Watch-Parent([int]$ProcessId) {
    if ($ProcessId -le 0) { return }
    while (Test-PidAlive $ProcessId) { Start-Sleep -Seconds 2 }
    try { Stop-Tunnel } catch {}
    try { Stop-Notifier } catch {}
    foreach ($f in @($UiPidFile, $WatchdogPidFile, $NotifierPidFile)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}

try {
    Ensure-Dir $ConfigDir
    Ensure-Dir $RuntimeDir
    Ensure-Dir $LogsDir
    Ensure-Dir $PidsDir
    Ensure-Dir $ApprovalsDir
    Ensure-Dir $TerminalJobsDir
    Ensure-Dir $StitchJobsDir

    switch ($Action.ToLowerInvariant()) {
        "init" { Normalize-Settings | Out-Null; exit 0 }
        "start" { $id = Start-Tunnel; "PID=$id"; exit 0 }
        "stop" { Stop-Tunnel; exit 0 }
        "restart" { $id = Restart-Tunnel; "PID=$id"; exit 0 }
        "status" { Render-StatusEnv; exit 0 }
        "toggle" { $state = Toggle-Feature $Feature; "STATE=$state"; exit 0 }
        "pick-workspace" { Pick-Workspace; exit 0 }
        "set-stitch-key" { Set-StitchKey; exit 0 }
        "open-workspace" { $s = Normalize-Settings; $explorer = Resolve-Exe 'explorer.exe'; if (-not $explorer) { throw "Windows Explorer was not found." }; $arg = '"' + ([string]$s.workspace).Replace('"','') + '"'; Start-Process -FilePath $explorer -ArgumentList $arg | Out-Null; exit 0 }
        "approval-count" { "COUNT=$(@(Get-PendingApprovals).Count)"; exit 0 }
        "approval-render" { Render-Approval $Index; exit 0 }
        "dashboard-render" { Render-Dashboard; exit 0 }
        "ui-state" { Get-UiState; exit 0 }
        "settings-render" { Render-SettingsPage; exit 0 }
        "dashboard-sig" { Get-DashboardSignature; exit 0 }
        "approval-id" { $item = Get-ApprovalByIndex $Index; if ($item) { [string]$item.id }; exit 0 }
        "approve" { Set-ApprovalDecision $Id "approved"; exit 0 }
        "deny" { Set-ApprovalDecision $Id "denied"; exit 0 }
        "tail" { Tail-Log $Log; exit 0 }
        "doctor" { Doctor; exit 0 }
        "watchdog-start" { Start-Watchdog; exit 0 }
        "watchdog-stop" { Stop-Watchdog; exit 0 }
        "notifier-start" { Start-Notifier; exit 0 }
        "notifier-stop" { Stop-Notifier; exit 0 }
        "watch" { Watch-Parent $ParentPid; exit 0 }
        default { throw "Unknown action: $Action" }
    }
} catch {
    $line = 0
    try { $line = [int]$_.InvocationInfo.ScriptLineNumber } catch {}
    $where = if ($line -gt 0) { "manager.ps1:$line" } else { "manager.ps1" }
    $details = @(
        "Time: $((Get-Date).ToString('o'))",
        "Action: $Action",
        "Location: $where",
        "Message: $($_.Exception.Message)",
        "Type: $($_.Exception.GetType().FullName)",
        "Stack: $($_.ScriptStackTrace)"
    ) -join "`r`n"
    try { Add-Content -LiteralPath $ErrorLog -Value ($details + "`r`n------------------------------------------------------------") -Encoding UTF8 } catch {}
    [Console]::Error.WriteLine("$where - $($_.Exception.Message)")
    exit 1
}
