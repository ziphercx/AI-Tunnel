param(
    [string]$Action = 'ui'
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Runtime=Join-Path $Root 'runtime'
$Logs=Join-Path $Runtime 'logs'
$Exports=Join-Path $Runtime 'exports'
$Settings=Join-Path $Root 'config\settings.json'
New-Item -ItemType Directory -Force -Path $Logs,$Exports | Out-Null

function Write-ErrorLog([string]$Source,[string]$Message,[string]$Details='') {
    $line = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] ERROR [$Source] $Message"
    if($Details){$line += "`r`n$Details"}
    Add-Content -LiteralPath (Join-Path $Logs 'errors.log') -Value $line -Encoding UTF8
}
function Tail([string]$Path,[int]$Lines=160){
    if(!(Test-Path $Path)){return @("[missing] $Path")}
    return @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue)
}
function Get-LogFiles {
    if(!(Test-Path $Logs)){return @()}
    @(Get-ChildItem -LiteralPath $Logs -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}
function Build-Bundle {
    New-Item -ItemType Directory -Force -Path $Exports | Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $out=Join-Path $Exports "Tunnel-V4.1-New-log-$stamp.txt"
    $sb=New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('============================================================')
    [void]$sb.AppendLine('Tunnel V4.1-New Diagnostic Log Bundle')
    [void]$sb.AppendLine("Created: $((Get-Date).ToString('o'))")
    [void]$sb.AppendLine("Machine: $env:COMPUTERNAME")
    [void]$sb.AppendLine("PowerShell: $($PSVersionTable.PSVersion)")
    [void]$sb.AppendLine('============================================================')
    if(Test-Path $Settings){
        try {
            $s=Get-Content $Settings -Raw | ConvertFrom-Json
            [void]$sb.AppendLine("Workspace: $($s.workspace)")
            [void]$sb.AppendLine("Health: $($s.network.healthHost):$($s.network.healthPort)")
            [void]$sb.AppendLine("Scope: $($s.scope.mode)")
            [void]$sb.AppendLine("Provider: $($s.aiProviders.active)")
        } catch { [void]$sb.AppendLine('Settings: unable to parse') }
    }
    foreach($f in Get-LogFiles){
        [void]$sb.AppendLine("`r`n===== $($f.Name) =====")
        try { [void]$sb.AppendLine((Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop)) } catch { [void]$sb.AppendLine("[read error] $($_.Exception.Message)") }
    }
    [IO.File]::WriteAllText($out,$sb.ToString(),(New-Object System.Text.UTF8Encoding($false)))
    return $out
}
function Export-Dialog {
    Add-Type -AssemblyName System.Windows.Forms
    $d=New-Object System.Windows.Forms.SaveFileDialog
    $d.Title='Save Tunnel V4.1-New log bundle'
    $d.Filter='Log bundle (*.txt)|*.txt|All files (*.*)|*.*'
    $d.FileName="Tunnel-V4.1-New-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $d.InitialDirectory=$Exports
    if($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){return}
    $tmp=Build-Bundle
    Copy-Item -LiteralPath $tmp -Destination $d.FileName -Force
    Write-Host "[OK] Saved: $($d.FileName)" -ForegroundColor Green
}
function View-Log {
    while($true){
        Clear-Host
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host '                 TUNNEL V4.1-NEW LOG CENTER' -ForegroundColor Cyan
        Write-Host '============================================================'
        $files=@(Get-LogFiles)
        if(!$files){Write-Host 'No log files yet.' -ForegroundColor Yellow}else{
            for($i=0;$i -lt $files.Count;$i++){
                Write-Host ("[{0}] {1}  {2:N1} KB  {3}" -f ($i+1),$files[$i].Name,($files[$i].Length/1KB),$files[$i].LastWriteTime)
            }
        }
        Write-Host ''
        Write-Host '[V] View log   [E] Export ALL logs   [C] Clear logs   [B] Back'
        $c=Read-Host 'Select'
        if($c -eq 'B'){break}
        if($c -eq 'E'){Export-Dialog;Read-Host 'Press Enter'|Out-Null;continue}
        if($c -eq 'C'){
            $ok=Read-Host 'Type CLEAR to delete current logs'
            if($ok -eq 'CLEAR'){Get-LogFiles|Remove-Item -Force -ErrorAction SilentlyContinue;Write-Host 'Logs cleared.' -ForegroundColor Green}
            Read-Host 'Press Enter'|Out-Null;continue
        }
        if($c -eq 'V'){
            $n=[int](Read-Host 'Log number');if($n -ge 1 -and $n -le $files.Count){Clear-Host;Write-Host "===== $($files[$n-1].Name) =====" -ForegroundColor Cyan;Get-Content $files[$n-1].FullName -Tail 220;Read-Host 'Press Enter'|Out-Null}
        }
    }
}
try {
    switch($Action.ToLowerInvariant()){
        'export' { $p=Build-Bundle;Write-Output $p;exit 0 }
        'ui' { View-Log;exit 0 }
        default { throw "Unknown action: $Action" }
    }
} catch {
    Write-ErrorLog 'log-center' $_.Exception.Message ($_.ScriptStackTrace)
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
