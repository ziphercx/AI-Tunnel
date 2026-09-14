# POOH HUB AI-Tunnel V1.2 — Portable Control Center

AI Tunnel Client for Windows with a portable CMD control center.

## V1.2 architecture

The tunnel exposes a scoped MCP filesystem workspace. Optional automation capabilities are kept disabled by default and are policy-controlled rather than giving the AI unrestricted control of Windows.

### Core features

- Background `tunnel-client.exe` while the Control Center stays open.
- Default workspace is `POOH HUB AI-Tunnel V1.2\workspace`.
- A project can be selected as the active AI workspace at runtime.
- MCP filesystem access is scoped to the active workspace/project.
- Tunnel credentials are passed through `CONTROL_PLANE_API_KEY`, not command-line arguments.
- Tunnel output is stored in `logs\`.
- Local AI access test suite checks MCP, Node, workspace, health, process, Git and capability policy.

### Project + GitHub auto-backup

Option `[11] Project + GitHub Backup` provides:

1. Add/update a project profile.
2. Choose the local project folder.
3. Enter the GitHub repository URL.
4. Choose the branch.
5. Toggle auto-backup per project.
6. Activate one project for AI use.

When at least one project has auto-backup enabled, starting the tunnel also starts a hidden backup worker. The worker periodically commits changed files and pushes to the configured branch. Git authentication is intentionally delegated to normal Git/Windows credential handling; credentials are not stored in the AI Tunnel config.

Common secret files are never staged by the backup worker:

- `.env` / `.env.*`
- `*.pem`, `*.key`, `*.p12`, `*.pfx`
- `*credentials*.json`
- `*secret*.json`

Project profiles are stored locally in `config\projects.json` and are ignored by Git.

## AI capability policy

Option `[12] AI Capability Policy` controls optional categories:

- Windows actions
- Browser
- Database
- Email
- Docker
- GUI actions

All are **OFF by default**. The policy supports scoped allowlists such as allowed apps, browser domains, database connections, email recipients, containers and GUI actions.

This project deliberately does **not** enable unrestricted shell execution, unrestricted Windows control, arbitrary browser automation, arbitrary database writes, arbitrary email delivery, or unrestricted Docker/GUI control. Those would bypass the workspace security boundary. Each optional integration should be implemented as a separate, auditable MCP adapter with an explicit allowlist.

The current tunnel runtime still uses the filesystem MCP server as its core AI tool. Turning a policy flag ON does not by itself install or expose a new adapter.

## Structure

```text
AI-Tunnel\
├─ tunnel-client.exe
├─ run.bat
├─ setup.bat
├─ config\
│  ├─ .env
│  ├─ capabilities.json
│  ├─ projects.json              # local only, ignored by Git
│  ├─ gptwork.runtime.yaml
│  ├─ tunnel.pid
│  └─ backup-worker.pid
├─ logs\
│  ├─ tunnel.stdout.log
│  ├─ tunnel.stderr.log
│  └─ backup.log
├─ scripts\
│  ├─ launcher.ps1
│  ├─ setup.ps1
│  ├─ tunnel-worker.ps1
│  ├─ project-manager.ps1
│  └─ backup-worker.ps1
├─ workspace\
├─ git-backup.bat
└─ git-backup.ps1
```

## Control Center

- `[1]` Start Tunnel
- `[2]` Stop Tunnel
- `[3]` Restart Tunnel
- `[4]` Health Check
- `[5]` Settings
- `[6]` Open Workspace
- `[7]` View Logs
- `[8]` Diagnostics
- `[9]` AI Access Test Suite
- `[10]` Setup / Reconfigure
- `[11]` Project + GitHub Backup
- `[12]` AI Capability Policy
- `[0]` Exit

## First run on any Windows PC

1. Extract the portable package to any folder. Do **not** depend on `C:\Users\POOHHUB` or another fixed username/path.
2. Make sure `tunnel-client.exe` is present in `tunnel\`.
3. Make sure Node.js is installed and available as `node`/`npm` because the MCP bridge runs with Node.
4. Run `setup.bat`.
5. Enter **that user's own Tunnel ID** and Control Plane/GPT API key. Never distribute your personal `tunnel\.env` or generated `tunnel\gptwork.yaml`.
6. Keep the default workspace as `workspace\` for a portable installation, or intentionally choose another folder.
7. Run `run.bat` to open the Control Center.

## Building a safe package to give to other users

Run `BUILD-PORTABLE.bat` from the project root. It creates `dist\POOH-HUB-AI-Tunnel-V1.2-Portable.zip` and removes/blocks machine-local credentials, generated tunnel profiles, logs, runtime state and `node_modules` from the package.

The package is **portable by path**, but the tunnel account is intentionally **not shared**. Each user must run setup with their own Tunnel ID/API key. This prevents your credentials and tunnel identity from being handed to other users.

### Requirements

- Windows 10/11, preferably 64-bit.
- PowerShell 5.1+.
- Node.js available as `node` (required by the MCP bridge).
- A compatible `tunnel-client.exe` for the target Windows architecture.
- A valid Tunnel ID and Control Plane/API credential for the person using the package.

The application resolves its project root from the script location and uses project-relative paths for the default workspace, so moving the extracted folder to another drive, folder or Windows username does not break it.

## Security

- Never commit `config\.env`.
- Never put API keys directly in BAT arguments.
- Keep the active AI project limited to files the AI is intended to access.
- Use GitHub authentication through Git/Windows Credential Manager instead of saving tokens in project config.
- Review Git changes before enabling automatic push on important repositories.
- Optional capability categories are scoped and disabled by default.
