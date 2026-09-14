param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
if($errors -and $errors.Count -gt 0){
    Write-Host 'TUI syntax check failed:' -ForegroundColor Red
    foreach($e in $errors){
        $line = 0
        try { $line = [int]$e.Extent.StartLineNumber } catch {}
        Write-Host ('  line ' + $line + ': ' + $e.Message) -ForegroundColor Red
    }
    exit 2
}
exit 0
