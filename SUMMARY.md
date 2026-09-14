# POOH HUB AI-Tunnel V1.2 — Build Summary

## Goal

POOH HUB AI-Tunnel V1.2 is the active standalone project that combines the Tunnel core with the AI-Tunnel control/management layer without modifying the original source projects.

## Included design

- Tunnel core MCP modules are imported by `BUILD-MERGE.ps1`.
- AI-Tunnel project manager, provider manager, backup worker and tunnel worker are imported by the same build step.
- V1.2 AI-Tunnel-style CMD control center is provided by `scripts/launcher.ps1`.
- Workspace is the default security boundary.
- File access, terminal access and destructive operations default to `ask`.
- Full-computer access is disabled by default.
- Optional capability categories are disabled by default.
- GitHub authentication is delegated to normal Git/Git Credential Manager/GitHub CLI/PAT workflows; credentials are not placed in project configuration.
- Automatic backup excludes common secret files.
- `.env`, keys, certificates, secret JSON files, `.git`, `node_modules` and runtime data are excluded from merge/copy operations.

## Source projects

The build script reads from the original sibling source folders:

```text
..\Tunnel-V4
..\AI-Tunnel
```

It never writes to those folders.

## Build

Run:

```bat
BUILD-MERGE.ps1
```

or from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\BUILD-MERGE.ps1
```

The merge copies the V4 core and selected AI-Tunnel management files into this new project while excluding secrets.

## First setup

Run:

```bat
setup.bat
```

Enter:

1. Tunnel ID
2. Control Plane / GPT API key
3. Workspace folder

The key is typed hidden and stored only in the local `config\.env` created on this computer.

## Start

Run:

```bat
run.bat
```

Main control center:

```text
[1] Start V1.2 interactive TUI
[2] Project + GitHub Manager
[3] AI Provider Manager
[4] AI Capability Policy
[5] Setup / Workspace / Credentials
[6] V1.2 Doctor / Diagnostics
[7] View V1.2 logs
[8] Run merge/update from Tunnel core + AI-Tunnel
[0] Exit
```

## Git / GitHub backup

Use `[2] Project + GitHub Manager` to register a project, remote and branch.

For a project without Git, the backup worker can initialize Git. Git credentials should be handled by Git Credential Manager, GitHub CLI or the normal Git authentication flow.

Do not put a GitHub token into `projects.json`, `.env`, command arguments or the README.

## AI provider manager

Use `[3] AI Provider Manager` for provider selection/configuration. Provider secret files remain local and are excluded from Git.

Supported provider definitions include OpenAI, Anthropic, Gemini, xAI, DeepSeek, Mistral, Groq, OpenRouter and custom OpenAI-compatible providers.

Changing the provider does not magically create an MCP connection. The client must actually support that provider/integration.

## Permissions

Default policy:

```text
File access       ASK
Terminal access   ASK
Destructive       ASK
Always allow      OFF
Full computer     OFF
```

The V4 approval system is retained for risky terminal, delete, Git, Windows and WSL operations.

## Portability

Copy the complete POOH HUB AI-Tunnel V1.2 directory to another computer, then run `setup.bat` and configure that machine's credentials and workspace. Do not copy the generated `.env` or secret files.

## Important

The project is intentionally least-privilege by default. Do not enable unrestricted computer access simply to remove approval prompts. Use the workspace boundary and explicit approvals for safer automation.
