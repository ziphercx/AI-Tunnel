# 🚇 POOH HUB AI-Tunnel V4.2

> **Fast • Lightweight • Secure • MCP Backend**
>
> AI Tunnel สำหรับเชื่อม AI เข้ากับ Workspace, Files, Windows, Network และ Developer Tools ผ่าน MCP อย่างเป็นระบบ

---

## ✨ V4.2 มีอะไรเพิ่มจาก V1?

| V1 | V4.2 |
|---|---|
| เครื่องมือพื้นฐาน | **124 MCP Tools** |
| File operations จำกัด | Workspace + File Tools ครบขึ้น |
| System tools น้อย | Windows / System / Network Tools |
| Developer support พื้นฐาน | Node / npm / Python / Git / Project Detection |
| ไม่มีระบบ Approval ครบ | **Approval & Safety Gate** |
| รองรับ Windows จำกัด | Windows executable `.cmd/.bat` รองรับดีขึ้น |
| ทดสอบแยกส่วน | **MCP Self-Test** |
| Workspace ตายตัว | รองรับ `WORKSPACE_PATH` |
| Tool กระจาย | **Single MCP Registry** |
| Export เอง | **Public/Git Export System** |

---

## 🧩 Tool Categories

### 📁 Workspace & Files
- `workspace_info`
- `files_list`
- `files_exists`
- `files_stat`
- `files_read_text`
- `files_hash`
- `files_find`
- `files_search_text`
- `files_tree`
- `files_compare`
- `workspace_usage`

### 🌿 Git
- `git_status`
- `git_diff`
- `git_log`
- `git_branches`
- `git_remotes`
- `git_current_branch`
- `git_repo_root`

### 🖥️ Windows & System
- `windows_list_windows`
- `windows_active_window`
- `windows_session_info`
- `windows_shell_folders`
- `system_info`
- `system_cpu`
- `system_memory`
- `system_temp_dir`
- `system_home_dir`
- `system_processes`
- `system_drives`

### 🌐 Network
- Network interfaces
- Hostname
- DNS lookup
- Reverse DNS
- TCP probe
- Network connections

### 🛠️ Developer Tools
- Node.js / npm
- Python / py
- Git
- Project detection
- Package scripts
- Lockfiles
- Project discovery
- Toolchain detection
- Version detection

### 📦 Archive & WSL
- ZIP inspection
- WSL distro detection
- WSL status
- WSL version
- WSL path

### 🧵 Stitch
- Project discovery
- Screen discovery
- Job status
- Job results
- Job listing

---

## 🔐 Approval System

คำสั่งที่อาจสร้างผลกระทบต่อระบบ เช่น **สร้าง / แก้ไข / ลบไฟล์ หรือการเปลี่ยนแปลงที่สำคัญ** จะผ่าน Approval ก่อนดำเนินการ

แนวคิดหลัก:

```text
AI Request
    ↓
MCP Registry
    ↓
Policy / Approval Check
    ↓
Tool Execution
    ↓
Structured Result
```

ช่วยลดการทำงานผิดพลาดและทำให้การใช้งาน Tool มีขอบเขตชัดเจน

---

## 🚀 วิธีติดตั้งและใช้งาน

### 1. เข้าโฟลเดอร์

```bat
cd /d "C:\Users\POOHHUB\Desktop\000\AI\GPT-Project\Tunnel-V4.2"
```

### 2. เริ่ม Tunnel

```bat
run.bat
```

### 3. ทดสอบ Backend

```bat
node ".\scripts\mcp-self-test.mjs"
```

ถ้าทำงานถูกต้องจะได้:

```text
============================================================
POOH HUB MCP BACKEND SELF-TEST
============================================================

Registry/Backend : PASS
...

RESULT: PASS (0 failures)
```

---

## 🤖 ใช้งานผ่าน AI / MCP

ตัวอย่าง:

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
@v1 เรียก system_memory
```

```text
@v1 เรียก network_interfaces
```

จากนั้น AI จะเรียก Tool ที่อยู่ใน **Single MCP Registry** และคืนผลลัพธ์แบบ Structured Result

---

## 📂 Workspace

ค่าเริ่มต้นคือ:

```text
./workspace
```

หรือ:

```text
C:\Users\POOHHUB\Desktop\000\AI\GPT-Project\Tunnel-V4.2\workspace
```

สามารถกำหนด Workspace เองด้วย:

```text
WORKSPACE_PATH
```

ตัวอย่าง:

```bat
set WORKSPACE_PATH=C:\MyWorkspace
```

---

## 🧪 Testing

คำสั่งหลักสำหรับตรวจสอบ Backend:

```bat
node ".\scripts\mcp-self-test.mjs"
```

สถานะปัจจุบัน:

```text
MCP Registry : 124 implemented tools
Backend      : PASS
Self-test    : 0 failures
Workspace    : ./workspace
```

> หมายเหตุ: `PASS` ของ Self-Test หมายถึง Backend และชุดทดสอบที่กำหนดทำงานถูกต้อง ไม่ได้หมายความว่า Tool ทุกตัวถูกทดสอบกับทุก Input ที่เป็นไปได้

---

## 📤 Public Export

สำหรับเตรียมโปรเจกต์เพื่อเผยแพร่ GitHub ใช้:

```bat
C:\Users\POOHHUB\Desktop\000\AI\GPT-Project\EXPORT-TUNNEL-VERSION.bat
```

ผลลัพธ์:

```text
PUBLIC\Tunnel-V4.2
```

ระบบ Export จะคัดลอก Source ที่จำเป็น และตัดข้อมูลส่วนตัว/Runtime/Secrets เช่น:

- `.env`
- `node_modules`
- `workspace`
- `runtime`
- `logs`
- `.git`
- credentials / secrets
- private keys / certificates
- temporary files

---

## 🏗️ Architecture

```text
                    ┌──────────────────┐
                    │       AI         │
                    │      @v1         │
                    └────────┬─────────┘
                             │ MCP
                             ▼
                 ┌──────────────────────┐
                 │   AI-Tunnel V4.2     │
                 │   Single Registry    │
                 │      124 Tools       │
                 └──────────┬───────────┘
                            │
             ┌──────────────┼──────────────┐
             ▼              ▼              ▼
        Workspace        Windows        Developer
          Files           System          Tools
             │              │              │
             └──────────────┼──────────────┘
                            ▼
                   Structured Results
```

---

## 📁 Project Structure

```text
Tunnel-V4.2/
├─ scripts/
│  ├─ stitch-mcp.mjs
│  ├─ mcp-self-test.mjs
│  ├─ platform-resolver.mjs
│  ├─ manager.ps1
│  ├─ tunnel-host.ps1
│  └─ tui.ps1
│
├─ workspace/
├─ run.bat
├─ README.md
└─ ...
```

---

## 🛡️ Design Principles

- ⚡ Fast & Lightweight
- 🔒 Approval-first for high-impact operations
- 🧩 Single MCP Registry
- 🪟 Windows-first compatibility
- 📦 Structured tool results
- 🧪 Built-in self-test
- 🧹 Public export without local secrets
- 🎯 Workspace-scoped file operations

---

## 🆚 V1 → V4.2 สรุปสั้น ๆ

**V1:** MCP/Tunnel พื้นฐานสำหรับเชื่อม AI กับเครื่อง

**V4.2:** ขยายเป็น Backend เต็มระบบสำหรับ AI โดยรวม **124 Tools + Workspace + Files + Git + Windows + System + Network + Developer + WSL + Stitch + Approval + Self-Test** ไว้ใน Registry เดียว

---

## 📌 Version

```text
POOH HUB AI-Tunnel V4.2
MCP Registry : 124 implemented tools
Backend      : PASS
Self-test    : 0 failures
Workspace    : ./workspace
Platform     : Windows
```

---

<p align="center">
  <b>POOH HUB AI-Tunnel V4.2</b><br>
  Fast • Lightweight • Secure • MCP
</p>
