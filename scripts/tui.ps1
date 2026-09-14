param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Manager=Join-Path $PSScriptRoot 'manager.ps1'
$LogDir=Join-Path $Root 'runtime\logs'
$ErrorLog=Join-Path $LogDir 'errors.log'
$script:Exit=$false
$script:Status='Ready'
$script:SessionOwned=$false
$script:StartedByUi=$false
$script:MenuIndex=0
$script:StartupWorker=$null

function Pause-Key([string]$Message='Press any key...') {
    Write-Host "`n  $Message" -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}
function Set-Status([string]$Text){$script:Status=$Text; $env:AI_TUI_MESSAGE=$Text}
function Invoke-Manager([string]$Action,[hashtable]$Params=@{}) {
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if(-not (Test-Path -LiteralPath $powershell -PathType Leaf)){$powershell='powershell.exe'}
    $a=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$Manager,$Action)
    if($null -ne $Params){foreach($k in @($Params.Keys)){ $a += "-$k"; $a += [string]$Params[$k] }}
    try {
        $out=& $powershell @a 2>&1 | Out-String
        $rc=$LASTEXITCODE
        $text=$out.Trim()
        if($rc -ne 0){
            New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
            Add-Content -LiteralPath $ErrorLog -Value ((Get-Date).ToString('o')+' | '+$Action+' | '+$text) -Encoding UTF8
        }
        return [pscustomobject]@{Code=$rc;Text=$text}
    } catch {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
        Add-Content -LiteralPath $ErrorLog -Value ((Get-Date).ToString('o')+' | '+$Action+' | '+$_.Exception.Message) -Encoding UTF8
        return [pscustomobject]@{Code=1;Text=$_.Exception.Message}
    }
}
function Get-State {
    $r=Invoke-Manager 'ui-state'
    if($r.Code -ne 0){return $null}
    try{return ($r.Text|ConvertFrom-Json)}catch{return $null}
}
function Get-Settings {
    try{return (Get-Content (Join-Path $Root 'config\settings.json') -Raw|ConvertFrom-Json)}catch{return $null}
}
function Header([string]$Title='POOH HUB AI-TUNNEL V1.2 CONTROL CENTER') {
    Clear-Host
    Write-Host ''
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ('      '+$Title) -ForegroundColor Cyan
    Write-Host '      V4 CORE + AI-TUNNEL MANAGEMENT' -ForegroundColor DarkCyan
    Write-Host '  ================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}
function Draw-Menu([string]$Title,$Items,[int]$Selected) {
    Header $Title
    for($i=0;$i -lt $Items.Count;$i++){
        $prefix=if($i -eq $Selected){'  > '}else{'    '}
        $color=if($i -eq $Selected){'Cyan'}else{'White'}
        Write-Host ($prefix+$Items[$i].Label) -ForegroundColor $color
    }
    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Up/Down Select   Enter Open   Esc Back   Home/End First/Last' -ForegroundColor DarkGray
    Write-Host ('  Status: '+$script:Status) -ForegroundColor Yellow
}
function Read-Menu($Items,[int]$Start=0) {
    if($Items.Count -eq 0){return -1}
    $i=[Math]::Max(0,[Math]::Min($Start,$Items.Count-1))
    while($true){
        Draw-Menu $script:PageTitle $Items $i
        $k=[Console]::ReadKey($true)
        switch($k.Key){
            'UpArrow' {$i=($i-1+$Items.Count)%$Items.Count}
            'DownArrow' {$i=($i+1)%$Items.Count}
            'Home' {$i=0}
            'End' {$i=$Items.Count-1}
            'Enter' {return $i}
            'Escape' {return -1}
        }
    }
}
function Show-Stats {
    while($true){
        $s=Get-State
        $cfg=Get-Settings
        Header 'LIVE TUNNEL STATS'
        if(-not $s){Write-Host '  State unavailable.' -ForegroundColor Red;Write-Host '  Check Logs / Doctor.';Start-Sleep -Seconds 1;return}
        $running=[bool]$s.tunnel.running
        $online=[bool]$s.tunnel.online
        $pidValue=[int]$s.tunnel.pid
        $port=0;try{$port=[int]$cfg.network.healthPort}catch{}
        $hostName='127.0.0.1';try{$hostName=[string]$cfg.network.healthHost}catch{}
        $tunnelStatus=if($running){'RUNNING'}else{'STOPPED'}
        $healthStatus=if($online){'ONLINE'}else{'OFFLINE'}
        Write-Host ('  Tunnel       : '+$tunnelStatus) -ForegroundColor $(if($running){'Green'}else{'Red'})
        Write-Host ('  Health       : '+$healthStatus) -ForegroundColor $(if($online){'Green'}else{'Red'})
        Write-Host ('  PID          : '+$pidValue)
        Write-Host ('  Health Port  : '+$hostName+':'+$port)
        Write-Host ('  Workspace    : '+[string]$s.workspace) -ForegroundColor Gray
        Write-Host ''
        Write-Host '  FEATURES' -ForegroundColor Cyan
        Write-Host ('    Files      : '+$(if($s.features.files){'ON'}else{'OFF'}))
        Write-Host ('    Terminal   : '+$(if($s.features.terminal){'ON'}else{'OFF'}))
        Write-Host ('    Power      : '+$(if($s.features.extended){'ON'}else{'OFF'}))
        Write-Host ('    Stitch     : '+$(if($s.features.stitch){'ON'}else{'OFF'}))
        Write-Host ''
        Write-Host '  ACTIVITY' -ForegroundColor Cyan
        Write-Host ('    Pending approvals : '+@($s.pending).Count)
        Write-Host ('    Running jobs      : '+[int]$s.runningJobs)
        Write-Host ('    Current work      : '+[string]$s.work.type+' / '+[string]$s.work.status)
        Write-Host ('    Work detail       : '+[string]$s.work.text) -ForegroundColor Gray
        Write-Host ''
        if($running -and $pidValue -gt 0){
            try{
                $p=Get-Process -Id $pidValue -ErrorAction Stop
                Write-Host '  PROCESS' -ForegroundColor Cyan
                Write-Host ('    Name       : '+$p.ProcessName)
                Write-Host ('    CPU time   : '+[Math]::Round($p.CPU,2)+' sec')
                Write-Host ('    Memory     : '+[Math]::Round($p.WorkingSet64/1MB,1)+' MB')
                Write-Host ('    Threads    : '+$p.Threads.Count)
            }catch{}
        }
        Write-Host ''
        Write-Host '  [R] Refresh   [S] Stop   [T] Restart   [A] Approvals   [L] Logs   [Esc] Back' -ForegroundColor DarkGray

        # Fast UI: do not poll or redraw automatically. A full-screen redraw every
        # few hundred milliseconds makes the console feel slow and causes flicker.
        # Refresh is explicit so navigation remains instant on low-end machines.
        $k=[Console]::ReadKey($true)
        switch($k.Key){
            'Escape' {return}
            'R' {continue}
            'S' {$r=Invoke-Manager 'stop';Set-Status $(if($r.Code -eq 0){'Tunnel stopped'}else{'Stop failed - see Logs'})}
            'T' {$r=Invoke-Manager 'restart';Set-Status $(if($r.Code -eq 0){'Tunnel restarted'}else{'Restart failed - see Logs'})}
            'A' {Show-Approvals}
            'L' {Show-Logs}
        }
    }
}
function Start-TunnelUI {
    # Never run manager.ps1 start synchronously on the UI thread.
    # Startup can take several seconds (dependency checks + tunnel health), so
    # launch it in a separate PowerShell process and keep the UI responsive.
    $startDir=Join-Path $Root 'runtime\start'
    New-Item -ItemType Directory -Force -Path $startDir|Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $stdout=Join-Path $startDir ("start-$stamp.out.log")
    $stderr=Join-Path $startDir ("start-$stamp.err.log")
    $argList=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$Manager,'start')
    try {
        $p=Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    } catch {
        Set-Status 'Could not launch start worker'
        Show-Text 'START ERROR' $_.Exception.Message
        return
    }

    $script:StartupWorker=$p
    $script:Status='Starting tunnel...'
    $startTime=Get-Date

    # IMPORTANT: do not Clear-Host/redraw the whole screen while waiting.
    # The previous implementation repainted the complete TUI every 120 ms,
    # which caused visible flashing/flicker and wasted CPU.  Draw once, then
    # update only the small status area in-place.
    Header 'STARTING TUNNEL'
    Write-Host '  Starting V1.2 CORE + AI-TUNNEL...' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  UI is responsive while the tunnel starts.' -ForegroundColor Green
    Write-Host ('  Worker PID : '+$p.Id)
    Write-Host ('  Started at : '+(Get-Date -Format 'HH:mm:ss'))
    Write-Host ''
    Write-Host '  Status     : STARTING' -ForegroundColor Yellow
    $statusLine=$Host.UI.RawUI.CursorPosition.Y-1
    Write-Host ''
    Write-Host '  [Esc] Cancel startup   [Enter] Keep waiting' -ForegroundColor DarkGray

    while(-not $p.HasExited){
        if([Console]::KeyAvailable){
            $k=[Console]::ReadKey($true)
            if($k.Key -eq 'Escape'){
                try{Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}catch{}
                Set-Status 'Start cancelled'
                return
            }
        }

        # Update only the existing status line. No Clear-Host = no flicker.
        try{
            $pos=$Host.UI.RawUI.CursorPosition
            $Host.UI.RawUI.CursorPosition=New-Object System.Management.Automation.Host.Coordinates(0,$statusLine)
            $elapsed=(Get-Date)-$startTime
            Write-Host ('  Status     : STARTING   '+$elapsed.ToString('hh\:mm\:ss')) -NoNewline
            $Host.UI.RawUI.CursorPosition=$pos
        }catch{}
        Start-Sleep -Milliseconds 250
    }

    # manager.ps1 exits 0 only after the tunnel passes its startup health check.
    if($p.ExitCode -eq 0){
        $script:StartedByUi=$true
        Set-Status 'Tunnel started'
        Start-Sleep -Milliseconds 150
        Show-Stats
        return
    }

    $out=''
    $err=''
    try{if(Test-Path $stdout){$out=Get-Content $stdout -Raw}}catch{}
    try{if(Test-Path $stderr){$err=Get-Content $stderr -Raw}}catch{}
    if($null -eq $out){$out=''}
    if($null -eq $err){$err=''}
    $outText=[string]$out
    $errText=[string]$err
    $text=(($outText.Trim())+"`r`n"+($errText.Trim())).Trim()
    if([string]::IsNullOrWhiteSpace($text)){$text='Tunnel startup failed. Check runtime\\logs\\tunnel-host.log and runtime\\logs\\tunnel.stderr.log'}
    Set-Status 'Start failed - see Logs'
    Show-Text 'START ERROR' $text
}
function Stop-TunnelUI {
    $r=Invoke-Manager 'stop'
    if($r.Code -eq 0){Set-Status 'Tunnel stopped'}else{Set-Status 'Stop failed - see Logs';Show-Text 'STOP ERROR' $r.Text}
}
function Restart-TunnelUI {
    $r=Invoke-Manager 'restart'
    if($r.Code -eq 0){$script:StartedByUi=$true;Set-Status 'Tunnel restarted';Show-Stats}else{Set-Status 'Restart failed - see Logs';Show-Text 'RESTART ERROR' $r.Text}
}
function Show-Approvals {
    while($true){
        $s=Get-State;$items=@();if($s){$items=@($s.pending)}
        if($items.Count -eq 0){Header 'APPROVAL CENTER';Write-Host '  No pending approvals.' -ForegroundColor Green;Pause-Key;return}
        $i=0
        while($i -lt $items.Count){
            $x=$items[$i]
            Header 'APPROVAL CENTER'
            Write-Host ('  Request '+($i+1)+' / '+$items.Count) -ForegroundColor Yellow
            Write-Host ('  Risk   : '+$x.risk)
            Write-Host ('  Type   : '+$x.kind)
            Write-Host ('  Title  : '+$x.title)
            Write-Host ('  Detail : '+$x.summary) -ForegroundColor Gray
            Write-Host ''
            Write-Host '  [A] Approve once   [D] Deny   [N] Next   [B/Esc] Back' -ForegroundColor DarkGray
            $k=[Console]::ReadKey($true)
            if($k.Key -eq 'Escape' -or $k.Key -eq 'B'){return}
            if($k.Key -eq 'N' -or $k.Key -eq 'RightArrow'){$i=($i+1)%$items.Count;continue}
            if($k.Key -eq 'LeftArrow'){$i=($i-1+$items.Count)%$items.Count;continue}
            if($k.Key -eq 'A' -or $k.Key -eq 'D'){
                $decision=if($k.Key -eq 'A'){'approve'}else{'deny'}
                $r=Invoke-Manager $decision @{Id=[string]$x.id}
                Set-Status $(if($r.Code -eq 0){if($decision -eq 'approve'){'Approved once'}else{'Denied'}}else{'Approval action failed'})
                $s=Get-State;$items=@($s.pending);if($items.Count -eq 0){Pause-Key 'Queue empty. Press any key...';return};if($i -ge $items.Count){$i=0}
            }
        }
    }
}
function Show-Settings {
    $items=@(
      [pscustomobject]@{Label='Full Settings Center';Action='full'},
      [pscustomobject]@{Label='Change Workspace';Action='workspace'},
      [pscustomobject]@{Label='Change Health PORT';Action='port'},
      [pscustomobject]@{Label='Feature Quick Toggle';Action='features'},
      [pscustomobject]@{Label='Back';Action='back'}
    )
    while($true){
        $script:PageTitle='SETTINGS'
        $p=Read-Menu $items 0
        if($p -lt 0 -or $p -eq 4){return}
        switch($items[$p].Action){
            'full'{
              $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';if(-not(Test-Path $ps)){$ps='powershell.exe'}
              & $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'settings-center.ps1');Set-Status 'Settings Center closed'
            }
            'workspace'{[void](Invoke-Manager 'pick-workspace');Set-Status 'Workspace updated'}
            'port'{Change-Port}
            'features'{Show-FeatureToggles}
        }
    }
}
function Show-FeatureToggles {
    while($true){
        $s=Get-Settings;if(-not $s){return}
        $items=@(
          [pscustomobject]@{Label=('Files       ['+$(if($s.features.files){'ON'}else{'OFF'})+']');Key='files'},
          [pscustomobject]@{Label=('Terminal    ['+$(if($s.features.terminal){'ON'}else{'OFF'})+']');Key='terminal'},
          [pscustomobject]@{Label=('Power tools ['+$(if($s.features.extended){'ON'}else{'OFF'})+']');Key='extended'},
          [pscustomobject]@{Label=('Stitch      ['+$(if($s.features.stitch){'ON'}else{'OFF'})+']');Key='stitch'},
          [pscustomobject]@{Label='Back';Key='back'}
        )
        $script:PageTitle='FEATURE TOGGLES'
        $p=Read-Menu $items 0
        if($p -lt 0 -or $p -eq 4){return}
        $r=Invoke-Manager 'toggle' @{Feature=[string]$items[$p].Key}
        Set-Status $(if($r.Code -eq 0){'Feature changed - restart tunnel if needed'}else{'Feature toggle failed'})
    }
}
function Change-Port {
    $settingsFile=Join-Path $Root 'config\settings.json'
    try{$s=Get-Content $settingsFile -Raw|ConvertFrom-Json}catch{Set-Status 'Cannot read settings';return}
    $current=0;try{$current=[int]$s.network.healthPort}catch{}
    Header 'CHANGE HEALTH PORT'
    Write-Host ('  Current port: '+$current) -ForegroundColor Cyan
    Write-Host '  Enter a port from 1 to 65535.' -ForegroundColor Gray
    $v=Read-Host '  New port'
    $n=0
    if(-not [int]::TryParse($v,[ref]$n)-or $n -lt 1-or $n -gt 65535){Set-Status 'Invalid port (1-65535)';Pause-Key;return}
    if($s.PSObject.Properties['network'] -eq $null){$s|Add-Member NoteProperty network ([pscustomobject]@{healthHost='127.0.0.1';healthPort=$n})}else{$s.network.healthPort=$n}
    $s|ConvertTo-Json -Depth 20|Set-Content $settingsFile -Encoding UTF8
    Set-Status ('Port saved: '+$n)
    Pause-Key 'Port saved. Restart tunnel to apply.'
}
function Show-Logs {
    $items=@(
      [pscustomobject]@{Label='View errors.log';Action='errors'},
      [pscustomobject]@{Label='View tunnel logs';Action='tunnel'},
      [pscustomobject]@{Label='View activity log';Action='activity'},
      [pscustomobject]@{Label='Export diagnostic bundle';Action='export'},
      [pscustomobject]@{Label='Open log folder';Action='open'},
      [pscustomobject]@{Label='Back';Action='back'}
    )
    while($true){
      $script:PageTitle='LOGS / ERROR CENTER'
      $p=Read-Menu $items 0
      if($p -lt 0 -or $p -eq 5){return}
      switch($items[$p].Action){
        'errors'{
          $errorText='No errors.log yet.'
          if(Test-Path -LiteralPath $ErrorLog){$errorText=Get-Content $ErrorLog -Tail 160|Out-String}
          Show-Text 'ERROR LOG' $errorText
        }
        'tunnel'{Show-Text 'TUNNEL LOGS' ((Invoke-Manager 'tail' @{Log='tunnel'}).Text)}
        'activity'{Show-Text 'ACTIVITY LOG' ((Invoke-Manager 'tail' @{Log='activity'}).Text)}
        'export'{Export-Logs}
        'open'{New-Item -ItemType Directory -Force -Path $LogDir|Out-Null;Start-Process explorer.exe -ArgumentList ('"'+$LogDir+'"')|Out-Null;Set-Status 'Log folder opened'}
      }
    }
}
function Export-Logs {
    $outDir=Join-Path $Root 'runtime\exports';New-Item -ItemType Directory -Force -Path $outDir|Out-Null
    $file=Join-Path $outDir ('POOH-HUB-AI-Tunnel-V1.2-log-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
    $parts=@('POOH HUB AI-Tunnel V1.2 diagnostic export','Generated: '+(Get-Date).ToString('o'),'Machine: '+$env:COMPUTERNAME,'')
    foreach($name in @('errors.log','tunnel.stdout.log','tunnel.stderr.log','tunnel-host.log','activity.log','setup.log')){
        $parts+=('--- '+$name+' ---');$p=Join-Path $LogDir $name;if(Test-Path $p){$parts+=@(Get-Content $p -Tail 200)}else{$parts+='(missing)'};$parts+=''
    }
    $parts|Set-Content $file -Encoding UTF8
    Set-Status ('Saved: '+$file);Pause-Key
}
function Show-Text([string]$Title,[string]$Text){
    $lines=@();if([string]::IsNullOrWhiteSpace($Text)){$lines=@('No output.')}else{$lines=@($Text -split "`r?`n")}
    $top=0
    while($true){
      Header $Title
      $height=[Math]::Max(5,([Console]::WindowHeight)-9)
      $end=[Math]::Min($lines.Count,$top+$height)
      for($i=$top;$i-lt$end;$i++){Write-Host ('  '+$lines[$i])}
      Write-Host ''
      Write-Host '  Up/Down scroll   Enter/Esc back   Home/End top/bottom' -ForegroundColor DarkGray
      $k=[Console]::ReadKey($true)
      if($k.Key -eq 'Escape' -or $k.Key -eq 'Enter'){return}
      if($k.Key -eq 'UpArrow'){$top=[Math]::Max(0,$top-1)}
      if($k.Key -eq 'DownArrow'){$top=[Math]::Min([Math]::Max(0,$lines.Count-$height),$top+1)}
      if($k.Key -eq 'Home'){$top=0}
      if($k.Key -eq 'End'){$top=[Math]::Max(0,$lines.Count-$height)}
    }
}
function Show-Doctor {Show-Text 'DOCTOR / DIAGNOSTICS' (Invoke-Manager 'doctor').Text}
function Open-Workspace {[void](Invoke-Manager 'open-workspace');Set-Status 'Workspace opened'}
function Show-Main {
    # Fast navigation: manager.ps1 is NOT called while moving with Up/Down.
    # State is refreshed only when entering/returning from an action.
    $s=Get-State
    while(-not $script:Exit){
        $running=$false;$online=$false;$pidValue=0;$pending=0;$jobs=0;$workspace='not configured'
        if($s){$running=[bool]$s.tunnel.running;$online=[bool]$s.tunnel.online;$pidValue=[int]$s.tunnel.pid;$pending=@($s.pending).Count;$jobs=[int]$s.runningJobs;$workspace=[string]$s.workspace}
        $items=@(
          [pscustomobject]@{Label='Live Stats / Monitor';Action='stats'},
          [pscustomobject]@{Label=$(if($running){'Start Tunnel (already running)'}else{'Start Tunnel'});Action='start'},
          [pscustomobject]@{Label=$(if($running){'Stop Tunnel'}else{'Stop Tunnel (already stopped)'});Action='stop'},
          [pscustomobject]@{Label='Restart Tunnel';Action='restart'},
          [pscustomobject]@{Label=('Approvals  ['+$pending+']');Action='approvals'},
          [pscustomobject]@{Label='Settings / Configuration';Action='settings'},
          [pscustomobject]@{Label='Logs / Error Center';Action='logs'},
          [pscustomobject]@{Label='Doctor / Diagnostics';Action='doctor'},
          [pscustomobject]@{Label='Open Workspace';Action='open'},
          [pscustomobject]@{Label='Exit';Action='exit'}
        )
        Header 'POOH HUB AI-TUNNEL V1.2 CONTROL CENTER'
        Write-Host ('  STATUS      : '+$(if($running){'RUNNING'}else{'STOPPED'})+' / '+$(if($online){'ONLINE'}else{'OFFLINE'})) -ForegroundColor $(if($online){'Green'}elseif($running){'Yellow'}else{'Red'})
        Write-Host ('  PID         : '+$pidValue)
        Write-Host ('  WORKSPACE   : '+$workspace) -ForegroundColor Gray
        Write-Host ('  JOBS        : '+$jobs+'     APPROVALS: '+$pending) -ForegroundColor Gray
        Write-Host ''
        for($i=0;$i-lt$items.Count;$i++){
            $prefix=if($i -eq $script:MenuIndex){'  > '}else{'    '};$color=if($i -eq $script:MenuIndex){'Cyan'}else{'White'}
            Write-Host ($prefix+$items[$i].Label) -ForegroundColor $color
        }
        Write-Host ''
        Write-Host '  Up/Down Select   Enter Open   Esc Quit   Home/End First/Last' -ForegroundColor DarkGray
        Write-Host ('  '+$script:Status) -ForegroundColor Yellow
        $k=[Console]::ReadKey($true)
        switch($k.Key){
          'UpArrow' {$script:MenuIndex=($script:MenuIndex-1+$items.Count)%$items.Count}
          'DownArrow' {$script:MenuIndex=($script:MenuIndex+1)%$items.Count}
          'Home' {$script:MenuIndex=0}
          'End' {$script:MenuIndex=$items.Count-1}
          'Escape' {$script:Exit=$true}
          'Enter' {
            switch($items[$script:MenuIndex].Action){
              'stats'{Show-Stats}
              'start'{if($running){Set-Status 'Tunnel is already running';Show-Stats}else{Start-TunnelUI}}
              'stop'{if($running){Stop-TunnelUI}else{Set-Status 'Tunnel is already stopped'}}
              'restart'{Restart-TunnelUI}
              'approvals'{Show-Approvals}
              'settings'{Show-Settings}
              'logs'{Show-Logs}
              'doctor'{Show-Doctor}
              'open'{Open-Workspace}
              'exit'{$script:Exit=$true}
            }
            # Refresh once after an action; arrow navigation stays local and instant.
            $s=Get-State
          }
        }
    }
}
try {
    New-Item -ItemType Directory -Force -Path $LogDir|Out-Null
    $r=Invoke-Manager 'init'
    if($r.Code -ne 0){throw $r.Text}
    Set-Status 'Ready - choose Start Tunnel'
    Show-Main
} catch {
    New-Item -ItemType Directory -Force -Path $LogDir|Out-Null
    Add-Content -LiteralPath $ErrorLog -Value ((Get-Date).ToString('o')+' | TUI | '+$_.Exception.Message+' | '+$_.ScriptStackTrace) -Encoding UTF8
    Header 'POOH HUB AI-TUNNEL V1.2 ERROR'
    Write-Host ('  '+$_.Exception.Message) -ForegroundColor Red
    Pause-Key
    exit 1
} finally {
    if($script:StartedByUi){try{[void](Invoke-Manager 'stop')}catch{}}
    try{[Console]::CursorVisible=$true}catch{}
}
exit 0
