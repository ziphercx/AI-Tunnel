$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ConfigDir = Join-Path $Root 'config'
$SecretDir = Join-Path $ConfigDir 'secrets'
$ProviderFile = Join-Path $ConfigDir 'providers.json'
$InstructionDir = Join-Path $Root 'ai-instructions'
$EnvFile = Join-Path $ConfigDir '.env'

New-Item -ItemType Directory -Force -Path $ConfigDir,$SecretDir,$InstructionDir | Out-Null

function Load-Providers {
    if (-not (Test-Path -LiteralPath $ProviderFile)) { return @() }
    try {
        $v = Get-Content -LiteralPath $ProviderFile -Raw | ConvertFrom-Json
        if ($null -eq $v) { return @() }
        return @($v)
    } catch { return @() }
}
function Save-Providers($Items) { @($Items) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ProviderFile -Encoding UTF8 }
function Get-KeyPath($Id) { Join-Path $SecretDir ($Id + '.key') }
function Get-ActiveId {
    if (Test-Path -LiteralPath $EnvFile) {
        foreach ($line in Get-Content $EnvFile) { if ($line -match '^AI_PROVIDER=(.*)$') { return $matches[1].Trim() } }
    }
    return 'openai'
}
function Set-ActiveId($Id) {
    $lines = @(); if (Test-Path $EnvFile) { $lines = @(Get-Content $EnvFile) }
    $found=$false
    $out = foreach($line in $lines) { if($line -match '^AI_PROVIDER='){ $found=$true; 'AI_PROVIDER='+$Id } else {$line} }
    if(-not $found){$out += 'AI_PROVIDER='+$Id}
    $out | Set-Content -LiteralPath $EnvFile -Encoding UTF8
}
function Get-ProviderDefs {
    return @(
        [pscustomobject]@{ Id='openai'; Name='OpenAI / GPT'; Env='OPENAI_API_KEY'; KeyLabel='OpenAI API key'; Endpoint='https://api.openai.com/v1'; Protocol='openai-compatible' },
        [pscustomobject]@{ Id='anthropic'; Name='Anthropic / Claude'; Env='ANTHROPIC_API_KEY'; KeyLabel='Anthropic API key'; Endpoint='https://api.anthropic.com'; Protocol='anthropic' },
        [pscustomobject]@{ Id='gemini'; Name='Google / Gemini'; Env='GEMINI_API_KEY'; KeyLabel='Google AI API key'; Endpoint='https://generativelanguage.googleapis.com'; Protocol='google-generative-ai' },
        [pscustomobject]@{ Id='xai'; Name='xAI / Grok'; Env='XAI_API_KEY'; KeyLabel='xAI API key'; Endpoint='https://api.x.ai/v1'; Protocol='openai-compatible' },
        [pscustomobject]@{ Id='deepseek'; Name='DeepSeek'; Env='DEEPSEEK_API_KEY'; KeyLabel='DeepSeek API key'; Endpoint='https://api.deepseek.com/v1'; Protocol='openai-compatible' },
        [pscustomobject]@{ Id='mistral'; Name='Mistral AI'; Env='MISTRAL_API_KEY'; KeyLabel='Mistral API key'; Endpoint='https://api.mistral.ai/v1'; Protocol='openai-compatible' },
        [pscustomobject]@{ Id='groq'; Name='Groq'; Env='GROQ_API_KEY'; KeyLabel='Groq API key'; Endpoint='https://api.groq.com/openai/v1'; Protocol='openai-compatible' },
        [pscustomobject]@{ Id='openrouter'; Name='OpenRouter'; Env='OPENROUTER_API_KEY'; KeyLabel='OpenRouter API key'; Endpoint='https://openrouter.ai/api/v1'; Protocol='openai-compatible' }
    )
}
function Read-Secret($Label) {
    $s=Read-Host $Label -AsSecureString
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
}
function Write-Instruction($Provider) {
    $name=$Provider.Name
    $extra = switch($Provider.Id) {
        'openai' { 'Use the MCP tools exposed by the connected client when available. Do not assume tool access if the client does not expose it.' }
        'anthropic' { 'Use Claude MCP/tool connections supported by the Claude client or API integration. The tunnel itself does not impersonate an Anthropic client.' }
        'gemini' { 'Gemini may require an MCP-capable client or supported integration. An API key alone does not automatically grant Gemini access to this local tunnel.' }
        default { 'Use the MCP integration supported by your client.' }
    }
    $text=@"
# AI Tunnel Instructions - $name

You are an AI connected to a user-controlled AI Tunnel.

The tunnel exposes an explicitly selected workspace through an MCP filesystem server.
It is a scoped tool connection, not unrestricted computer control.

## Connection
Provider: $name
Workspace: <ACTIVE_WORKSPACE>

$extra

## Rules
1. Operate only inside the workspace directories exposed by MCP.
2. Never attempt to access files outside the allowed workspace.
3. Never request, reveal, print, copy, or commit API keys, passwords, tokens, cookies, private keys, or other secrets.
4. Do not execute arbitrary shell commands. Only use tools explicitly exposed by the MCP/client integration.
5. Ask for confirmation before destructive or irreversible changes.
6. Inspect relevant files before editing them.
7. Make the smallest safe change that solves the request.
8. Verify important changes after editing.
9. Never claim a tool or connection is available unless the client actually exposes it.
10. Respect the AI Tunnel capability policy and the user's active project.

## Filesystem workflow
- Start by listing the relevant directory.
- Read the target file before changing it.
- Edit only the necessary files.
- Re-read or validate the result when practical.
- Report exactly what changed.

## If MCP is unavailable
Do not pretend that the tunnel is connected. Explain that this AI/client needs an MCP-capable connection or integration to use the local tunnel.

## Project safety
The user may have multiple projects. The active project selected by the AI Tunnel is the intended target. Do not silently switch projects.
"@
    $path=Join-Path $InstructionDir ($Provider.Id+'.md')
    $text | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}
function Configure-Key($Provider) {
    Write-Host "`n  Configure key: $($Provider.Name)" -ForegroundColor Cyan
    Write-Host '  The key is stored in a local secret file and is never displayed.' -ForegroundColor Gray
    $key=Read-Secret "  $($Provider.KeyLabel)"
    if([string]::IsNullOrWhiteSpace($key)){Write-Host '  Cancelled.' -ForegroundColor Yellow;return}
    $path=Get-KeyPath $Provider.Id
    $key | Set-Content -LiteralPath $path -Encoding UTF8 -NoNewline
    try { $acl=Get-Acl $path; $acl.SetAccessRuleProtection($true,$false); Set-Acl $path $acl } catch {}
    Write-Host '  [SAVED] API key stored locally.' -ForegroundColor Green
}
function Show-Providers {
    $configured=@(Load-Providers)
    $active=Get-ActiveId
    Write-Host ''
    foreach($p in Get-ProviderDefs){
        $secret=Test-Path (Get-KeyPath $p.Id)
        $mark=if($p.Id -eq $active){'ACTIVE'}else{'     '}
        $state=if($secret){'KEY SET'}else{'NO KEY'}
        Write-Host ("  {0}  {1,-24} {2}" -f $mark,$p.Name,$state) -ForegroundColor $(if($p.Id -eq $active){'Green'}else{'White'})
    }
    foreach($c in $configured){ if($c.Id -notin @('openai','anthropic','gemini')){Write-Host ("        {0,-24} CUSTOM" -f $c.Name) -ForegroundColor Gray} }
}
function Test-Provider($Provider) {
    $keyPath=Get-KeyPath $Provider.Id
    if(-not (Test-Path $keyPath)){Write-Host '  [FAIL] No API key configured.' -ForegroundColor Red;return}
    Write-Host "  [READY] $($Provider.Name) key is configured without exposing its value." -ForegroundColor Green
    Write-Host "  Endpoint: $($Provider.Endpoint)" -ForegroundColor Gray
    Write-Host '  Note: provider authentication is separate from MCP tool connectivity.' -ForegroundColor Yellow
}
function Add-Custom {
    $id=Read-Host '  Provider id (letters/numbers/hyphen)'
    if($id -notmatch '^[a-z0-9-]{2,32}$'){Write-Host '  Invalid id.' -ForegroundColor Red;return}
    $name=Read-Host '  Provider name'
    $endpoint=Read-Host '  API endpoint (optional)'
    $protocol=Read-Host '  Protocol [openai-compatible]';if(!$protocol){$protocol='openai-compatible'}
    $items=@(Load-Providers)|Where-Object {$_.Id -ne $id}
    $items += [pscustomobject]@{Id=$id;Name=$name;Endpoint=$endpoint;Protocol=$protocol;Env=($id.ToUpper().Replace('-','_')+'_API_KEY')}
    Save-Providers $items
    $custom=[pscustomobject]@{Id=$id;Name=$name;Endpoint=$endpoint;Protocol=$protocol;KeyLabel="$name API key"}
    Configure-Key $custom
    Write-Instruction $custom | Out-Null
}

while($true){
    Clear-Host
    Write-Host ''
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |                  AI PROVIDER SWITCHER                   |' -ForegroundColor Cyan
    Write-Host '  |              OpenAI / Claude / Gemini / Custom          |' -ForegroundColor DarkCyan
    Write-Host '  +----------------------------------------------------------+' -ForegroundColor DarkCyan
    $active=Get-ActiveId
    $activeDef=(Get-ProviderDefs|Where-Object Id -eq $active|Select-Object -First 1)
    $activeName=if($activeDef){$activeDef.Name}else{(@(Load-Providers)|Where-Object Id -eq $active|Select-Object -First 1).Name}
    if(!$activeName){$activeName=$active}
    Write-Host "  Current provider: $activeName" -ForegroundColor Green
    Write-Host ''
    Write-Host '  [1] Switch to OpenAI / GPT' -ForegroundColor White
    Write-Host '  [2] Switch to Anthropic / Claude' -ForegroundColor White
    Write-Host '  [3] Switch to Google / Gemini' -ForegroundColor White
    Write-Host '  [4] Switch to xAI / Grok' -ForegroundColor White
    Write-Host '  [5] Switch to DeepSeek' -ForegroundColor White
    Write-Host '  [6] Switch to Mistral AI' -ForegroundColor White
    Write-Host '  [7] Switch to Groq' -ForegroundColor White
    Write-Host '  [8] Switch to OpenRouter' -ForegroundColor White
    Write-Host '  [9] Add custom / OpenAI-compatible provider' -ForegroundColor White
    Write-Host '  [10] Configure API key' -ForegroundColor White
    Write-Host '  [11] Test provider configuration' -ForegroundColor White
    Write-Host '  [12] Generate AI instructions' -ForegroundColor White
    Write-Host '  [13] Show provider status' -ForegroundColor White
    Write-Host '  [14] Back' -ForegroundColor White
    Write-Host ''
    $c=Read-Host '  Select'
    switch($c){
      '1' {$id='openai';Set-ActiveId $id;Write-Host '  [ACTIVE] OpenAI / GPT' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '2' {$id='anthropic';Set-ActiveId $id;Write-Host '  [ACTIVE] Anthropic / Claude' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '3' {$id='gemini';Set-ActiveId $id;Write-Host '  [ACTIVE] Google / Gemini' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '4' {$id='xai';Set-ActiveId $id;Write-Host '  [ACTIVE] xAI / Grok' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '5' {$id='deepseek';Set-ActiveId $id;Write-Host '  [ACTIVE] DeepSeek' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '6' {$id='mistral';Set-ActiveId $id;Write-Host '  [ACTIVE] Mistral AI' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '7' {$id='groq';Set-ActiveId $id;Write-Host '  [ACTIVE] Groq' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '8' {$id='openrouter';Set-ActiveId $id;Write-Host '  [ACTIVE] OpenRouter' -ForegroundColor Green;Start-Sleep -Milliseconds 400}
      '9' {Add-Custom;Read-Host '  Press Enter'|Out-Null}
      '10' {
        $defs=@(Get-ProviderDefs);Show-Providers
        $n=Read-Host '  Provider [1-8] or custom id'
        $p=$null
        if($n -match '^[1-8]$'){$p=$defs[[int]$n-1]}else{$p=@(Load-Providers)|Where-Object Id -eq $n|Select-Object -First 1}
        if($p){if(-not $p.KeyLabel){$p|Add-Member NoteProperty KeyLabel "$($p.Name) API key"};Configure-Key $p}else{Write-Host '  Unknown provider.' -ForegroundColor Red}
        Read-Host '  Press Enter'|Out-Null
      }
      '11' {
        $id=Get-ActiveId;$p=(Get-ProviderDefs|Where-Object Id -eq $id|Select-Object -First 1);if(!$p){$p=@(Load-Providers)|Where-Object Id -eq $id|Select-Object -First 1};if($p){Test-Provider $p}else{Write-Host '  Unknown provider.' -ForegroundColor Red};Read-Host '  Press Enter'|Out-Null
      }
      '12' {
        foreach($p in Get-ProviderDefs){$path=Write-Instruction $p;Write-Host "  Generated $path" -ForegroundColor Green}
        foreach($p in @(Load-Providers)){if($p.Id -notin @('openai','anthropic','gemini')){$path=Write-Instruction $p;Write-Host "  Generated $path" -ForegroundColor Green}}
        Read-Host '  Press Enter'|Out-Null
      }
      '13' {Show-Providers;Read-Host '  Press Enter'|Out-Null}
      '14' { return }
      default { Write-Host '  Invalid selection.' -ForegroundColor Yellow; Start-Sleep -Milliseconds 500 }
    }
}
