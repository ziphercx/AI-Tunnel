# POOH HUB AI-Tunnel V1.2

> A lightweight MCP tunnel/backend that gives AI clients a controlled set of workspace, system, developer, network, Git, archive, and automation tools.

[![Version](https://img.shields.io/badge/version-V1.2-blue)](#)
[![MCP](https://img.shields.io/badge/MCP-enabled-purple)](#)
[![Tools](https://img.shields.io/badge/tools-124-success)](#features)

## What is AI-Tunnel?

AI-Tunnel is a local MCP backend designed to let compatible AI clients interact with a computer through a controlled tool registry.

Instead of giving an AI unrestricted access to the machine, AI-Tunnel exposes specific tools with defined behavior and an approval layer for operations that can modify data or system state.

## What changed from V1?

V1.2 expands the original concept into a much broader MCP backend:

- **124 registered tools** in one MCP registry
- Workspace and file management
- File search, comparison, hashing, tree and usage information
- Git status, diff, log, branches, remotes and repository information
- Terminal and Windows session tools
- System, CPU, memory and environment information
- Network interface, DNS and TCP diagnostic tools
- Node.js, npm, Python, Git and project detection tools
- Archive/ZIP inspection
- WSL detection and status tools
- Stitch project and job tools
- Approval handling for higher-impact operations
- Configurable workspace through `WORKSPACE_PATH`
- Windows executable compatibility for commands such as `npm.cmd`
- Built-in MCP backend self-test

## Features

| Area | Examples |
|---|---|
| Workspace | List, read, search, compare and inspect files |
| Git | Status, diff, log, branches, remotes |
| Terminal | Run and inspect terminal jobs |
| Windows | Windows/session/shell information |
| System | CPU, memory, paths, temporary directory |
| Network | Interfaces, hostname, DNS, TCP probe |
| Developer | Toolchains, versions, projects, lockfiles |
| Archive | ZIP inspection |
| WSL | Distribution and WSL status |
| Stitch | Projects, screens and jobs |
| Security | Approval and controlled tool execution |

## Quick Start

### 1. Start AI-Tunnel

On Windows, run:

```bat
run.bat
```

### 2. Check the backend

```bat
node ".\scripts\mcp-self-test.mjs"
```

A successful installation should report:

```text
RESULT: PASS (0 failures)
```

### 3. Connect your MCP-compatible AI client

Configure the client to use the AI-Tunnel MCP server according to the client's MCP configuration format.

Once connected, the available tools are advertised from the single registry.

## Using the tools

For example, an AI client can request read-only information such as:

```text
@v1 เรียก workspace_info
```

```text
@v1 เรียก files_list
```

```text
@v1 เรียก system_info
```

```text
@v1 เรียก dev_versions
```

The exact command depends on the AI client or integration being used.

## Workspace

AI-Tunnel uses a workspace directory as the normal boundary for file-related operations.

By default:

```text
./workspace
```

A different workspace can be selected with:

```text
WORKSPACE_PATH=PATH_TO_WORKSPACE
```

Relative paths are resolved from the AI-Tunnel project directory.

## Approval & Safety

AI-Tunnel separates read-only operations from operations that can change data or system state.

Higher-impact operations can require approval before execution. This helps prevent an AI client from silently making unwanted changes.

The exact approval behavior depends on the tool being called and the configured policy.

> **Important:** Never place passwords, API keys, tokens, private certificates, or other secrets in the repository or README.

## Project Structure

A typical installation contains components similar to:

```text
AI-Tunnel/
├─ scripts/
│  ├─ stitch-mcp.mjs
│  ├─ mcp-self-test.mjs
│  ├─ platform-resolver.mjs
│  └─ ...
├─ workspace/
├─ run.bat
├─ README.md
└─ ...
```

Generated files, local configuration, secrets, and runtime data should not be committed to a public repository.

## Requirements

Typical requirements for running the backend include:

- Windows or another supported environment
- Node.js
- npm
- An MCP-compatible AI client
- Optional tools such as Git, Python, or WSL when their corresponding features are needed

The exact requirements depend on which tools you intend to use.

## Testing

Run the built-in backend test:

```bat
node ".\scripts\mcp-self-test.mjs"
```

The self-test checks the registry, workspace handling, core tools, platform integrations, and supported environment states.

A tool reporting a structured state such as "not a Git repository" or "no WSL distribution installed" does not necessarily mean the backend is broken; some tools can validly report that the requested capability is unavailable in the current environment.

## Public Repository Safety

Before publishing AI-Tunnel, keep machine-specific information out of the repository.

Do **not** publish:

- Local usernames or personal directory paths
- API keys or access tokens
- Passwords
- Private certificates or keys
- Local runtime logs
- Local workspace contents
- Machine-specific configuration
- Temporary files

Use placeholders in documentation instead:

```text
C:\Path\To\AI-Tunnel
```

instead of a real personal computer path.

## Exporting a Public Version

If the project includes the public export script, run:

```bat
EXPORT-TUNNEL-VERSION.bat
```

The export should contain the source needed for distribution while excluding local/runtime data and sensitive configuration.

Always review the generated directory before pushing it to a public repository.

## V1 → V4.2 at a glance

| | V1 | V4.2 |
|---|---:|---:|
| MCP tool registry | Basic | 124 tools |
| Workspace tools | ✓ | Expanded |
| File tools | Basic | Expanded |
| Git tools | Limited | Expanded |
| System tools | Limited | Expanded |
| Network diagnostics | Limited | ✓ |
| Developer tools | Basic | Expanded |
| WSL tools | — | ✓ |
| Archive tools | — | ✓ |
| Stitch tools | — | ✓ |
| Approval system | Basic | Expanded |
| Backend self-test | ✓ | ✓ |

## Troubleshooting

### `npm` cannot be found

Make sure Node.js is installed and available to the environment. AI-Tunnel includes executable resolution for common Windows installations.

### Git reports that the directory is not a repository

This is a valid Git state. Run the Git tools inside a Git repository if repository information is required.

### WSL is unavailable

WSL-related tools can report an unavailable/empty environment when WSL or a Linux distribution is not installed.

### ZIP file does not exist

`archive_list_zip` requires a real ZIP file as its input. An invalid or missing path is an input error, not an indication that the MCP backend itself failed.

## Development

The project is intended to keep tool registration centralized so that clients receive one consistent MCP tool surface.

When adding a new tool:

1. Add the implementation to the appropriate backend/registry location.
2. Keep its input and output behavior predictable.
3. Respect workspace and approval boundaries.
4. Add or update self-tests where appropriate.
5. Run the backend self-test before publishing a release.

## License

See the repository's `LICENSE` file if one is provided.

## Status

**AI-Tunnel V1.2**

- MCP Registry: **124 tools**
- Backend self-test: **PASS**
- Intended workspace: `./workspace`
- Public documentation: **machine-independent**

---

Built for controlled, practical AI-to-computer interaction through MCP.
