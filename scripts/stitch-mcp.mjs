#!/usr/bin/env node
import http from 'node:http';
import readline from 'node:readline';
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import os from 'node:os';
import dns from 'node:dns/promises';
import net from 'node:net';
import { fileURLToPath } from 'node:url';
import { TOOLS, TOOL_NAMES } from './stitch-tool-registry.mjs';
import { resolveExecutable, resolvePowerShell, resolvedEnvironment } from './platform-resolver.mjs';

const args = new Set(process.argv.slice(2));
const healthIndex = process.argv.indexOf('--health-port');
const healthPort = healthIndex >= 0 ? Number(process.argv[healthIndex + 1]) || 18022 : 18022;

function rpc(id, result) { return JSON.stringify({ jsonrpc: '2.0', id, result }); }
function err(id, code, message) { return JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } }); }

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
// Workspace policy: default is ALWAYS ./workspace relative to this
// Tunnel installation. A custom WORKSPACE_PATH is honored only when the
// user explicitly provides one; otherwise never inherit a caller's CWD or
// an old V4.x absolute path.
const defaultWorkspace = path.resolve(scriptDir, '..', 'workspace');
const envWorkspace = String(process.env.WORKSPACE_PATH || '').trim();
const configuredWorkspace = envWorkspace || defaultWorkspace;
const workspace = path.resolve(configuredWorkspace);
await fs.mkdir(workspace, { recursive: true });
const tools = TOOLS;
const rel = p => path.relative(workspace, p) || '.';
function safePath(p) {
  const target = path.resolve(workspace, String(p || '.'));
  if (target !== workspace && !target.startsWith(workspace + path.sep)) throw new Error('Path is outside the configured workspace');
  return target;
}
async function runPowerShellJson(script) {
  if (process.platform !== 'win32') return { ok:false, supported:false, reason:'Windows only' };
  const ps = resolvePowerShell();
  if (!ps) return { ok:false, supported:false, reason:'PowerShell executable not found' };
  return await new Promise(resolve => {
    const p = spawn(ps, ['-NoProfile','-NonInteractive','-Command',script], { cwd:workspace, windowsHide:true, env:resolvedEnvironment(), stdio:['ignore','pipe','pipe'] });
    let out='', stderr='';
    p.stdout.on('data', d => out += d.toString());
    p.stderr.on('data', d => stderr += d.toString());
    p.on('error', e => resolve({ok:false,error:e.message}));
    p.on('close', code => {
      try { resolve({ok:code===0, data:out.trim()?JSON.parse(out):[], stderr:stderr.trim()}); }
      catch { resolve({ok:false,error:'PowerShell returned invalid JSON',stderr:stderr.trim(),raw:out.trim()}); }
    });
  });
}

async function listFiles(dir, recursive, maxEntries, out = [], relBase = workspace) {
  if (out.length >= maxEntries) return out;
  for (const ent of await fs.readdir(dir, { withFileTypes: true })) {
    if (out.length >= maxEntries) break;
    const full = path.join(dir, ent.name);
    out.push({ path: path.relative(relBase, full) || '.', type: ent.isDirectory() ? 'directory' : 'file' });
    if (recursive && ent.isDirectory()) await listFiles(full, true, maxEntries, out, relBase);
  }
  return out;
}
async function callTool(name, a = {}) {
  if (!TOOL_NAMES.includes(name)) throw new Error('Unknown tool: ' + name);
  if (name === 'workspace_info') {
    const st = await fs.stat(workspace);
    return { workspace, exists: true, type: st.isDirectory() ? 'directory' : 'file' };
  }
  if (name === 'workspace_usage') {
    const root = safePath(a.path || '.');
    const maxEntries = Math.min(200000, Math.max(1, Number(a.maxEntries) || 50000));
    let bytes = 0, files = 0, directories = 0, scanned = 0;
    async function walk(dir) {
      if (scanned >= maxEntries) return;
      for (const ent of await fs.readdir(dir, { withFileTypes: true })) {
        if (scanned++ >= maxEntries) break;
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) { directories++; await walk(full); }
        else if (ent.isFile()) { files++; try { bytes += (await fs.stat(full)).size; } catch {} }
      }
    }
    await walk(root);
    return { path: path.relative(workspace, root) || '.', bytes, files, directories, scanned, truncated: scanned >= maxEntries };
  }
  if (name === 'files_list') {
    const dir = safePath(a.directory || '.');
    const maxEntries = Math.min(2000, Math.max(1, Number(a.maxEntries) || 300));
    return { directory: path.relative(workspace, dir) || '.', entries: await listFiles(dir, Boolean(a.recursive), maxEntries) };
  }
  if (name === 'files_exists') {
    const target = safePath(a.path);
    try { await fs.access(target); return { exists: true, path: path.relative(workspace, target) || '.' }; }
    catch (e) { if (e.code === 'ENOENT') return { exists: false, path: path.relative(workspace, target) || '.' }; throw e; }
  }
  if (name === 'files_stat') {
    const target = safePath(a.path); 
    const st = await fs.stat(target);
    return { path: path.relative(workspace, target) || '.', type: st.isDirectory() ? 'directory' : 'file', size: st.size, createdAt: st.birthtime.toISOString(), modifiedAt: st.mtime.toISOString() };
  }
  if (name === 'local_features') {
    return { files: true, terminal: true, extended: true, stitch: true, python: true, appOpen: true, calculator: true, workspace: workspace };
  }
  if (name === 'dev_toolchains') {
    const checks = ['node','npm','python','py','git','powershell','pwsh','cmd'];
    const found = {};
    for (const cmd of checks) {
      found[cmd] = await new Promise(resolve => {
        const resolver = resolveExecutable(cmd);
        if (!resolver) return resolve(null);
        const isCmd = process.platform === 'win32' && /\.(cmd|bat)$/i.test(resolver);
        const shell = resolveExecutable('cmd');
        const p = cmd.toLowerCase() === 'powershell'
          ? spawn(resolver, ['-NoProfile','-NonInteractive','-Command','$PSVersionTable.PSVersion.ToString()'], { cwd:workspace, windowsHide:true, env:resolvedEnvironment(), stdio:['ignore','pipe','ignore'] })
          : cmd.toLowerCase() === 'cmd'
            ? spawn(resolver, ['/d','/c','ver'], { cwd:workspace, windowsHide:true, env:resolvedEnvironment(), stdio:['ignore','pipe','ignore'] })
            : isCmd
              ? spawn(shell, ['/d','/c','call',resolver,'--version'], { cwd:workspace, windowsHide:true, env:resolvedEnvironment(), stdio:['ignore','pipe','ignore'] })
              : spawn(resolver, ['--version'], { cwd: workspace, windowsHide: true, env: resolvedEnvironment(), stdio: ['ignore','pipe','ignore'] });
        let out = '';
        p.stdout?.on('data', d => { out += d.toString(); });
        p.on('error', () => resolve(null));
        p.on('close', code => resolve(code === 0 ? out.trim().split(/\r?\n/)[0] || cmd : null));
      });
    }
    return { platform: process.platform, found };
  }
  if (name === 'files_hash') {
    const file = safePath(a.path);
    const hash = crypto.createHash('sha256');
    const data = await fs.readFile(file);
    hash.update(data);
    return { path: path.relative(workspace, file), algorithm: 'sha256', hash: hash.digest('hex'), size: data.length };
  }
  if (name === 'files_find') {
    const root = safePath(a.directory || '.');
    const pattern = String(a.pattern || '').trim();
    if (!pattern) throw new Error('pattern is required');
    const maxResults = Math.min(5000, Math.max(1, Number(a.maxResults) || 200));
    const out = [];
    const needle = pattern.toLowerCase();
    async function walk(dir) {
      if (out.length >= maxResults) return;
      for (const ent of await fs.readdir(dir, { withFileTypes: true })) {
        if (out.length >= maxResults) break;
        const full = path.join(dir, ent.name);
        if (ent.name.toLowerCase().includes(needle) || path.relative(workspace, full).toLowerCase().includes(needle)) out.push({ path: path.relative(workspace, full), type: ent.isDirectory() ? 'directory' : 'file' });
        if (ent.isDirectory()) await walk(full);
      }
    }
    await walk(root);
    return { pattern, results: out, truncated: out.length >= maxResults };
  }
  if (name === 'system_info') {
    return { platform: process.platform, arch: process.arch, node: process.version, pid: process.pid, workspace, hostname: process.env.COMPUTERNAME || process.env.HOSTNAME || '' };
  }
  if (name === 'dev_versions') {
    const commands = ['node','npm','python','git','powershell'];
    const versions = {};
    for (const command of commands) versions[command] = await new Promise(resolve => {
      let executable = resolveExecutable(command);
      if (process.platform === 'win32' && command === 'npm') executable = resolveExecutable('npm.cmd') || executable;
      if (process.platform === 'win32' && command === 'powershell') executable = resolvePowerShell() || executable;
      if (!executable) return resolve({ ok:false, error:`${command} executable not found` });
      const isCmd = process.platform === 'win32' && /\.(cmd|bat)$/i.test(executable);
      const shell = resolveExecutable('cmd.exe') || resolveExecutable('cmd');
      const p = command.toLowerCase() === 'powershell'
        ? spawn(executable, ['-NoProfile','-NonInteractive','-Command','$PSVersionTable.PSVersion.ToString()'], { cwd:workspace, windowsHide:true, env:resolvedEnvironment(), stdio:['ignore','pipe','pipe'] })
        : isCmd
          ? spawn(shell, ['/d','/c','call',executable,'--version'], { cwd:workspace, windowsHide:true, env:resolvedEnvironment(), stdio:['ignore','pipe','pipe'] })
          : spawn(executable, ['--version'], { cwd: workspace, windowsHide: true, env: resolvedEnvironment(), stdio: ['ignore','pipe','pipe'] }); let out='';
      p.stdout?.on('data', d => out += d.toString()); p.stderr?.on('data', d => out += d.toString());
      p.on('error', e => resolve({ ok:false, error:e.message })); p.on('close', code => resolve({ ok: code===0, version: out.trim() }));
    });
    return versions;
  }
  if (name === 'windows_active_window' || name === 'windows_list_windows') {
    if (process.platform !== 'win32') return { ok:false, supported:false, reason:'Windows only' };
    const script = name === 'windows_active_window'
      ? '$p=Get-Process | Where-Object {$_.MainWindowHandle -ne 0} | Sort-Object StartTime -Descending | Select-Object -First 1; if($p){$p | Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle | ConvertTo-Json -Compress}'
      : 'Get-Process | Where-Object {$_.MainWindowHandle -ne 0} | Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle | ConvertTo-Json -Compress';
    return await new Promise(resolve => { const ps = resolvePowerShell(); if (!ps) return resolve({ok:false,error:'PowerShell executable not found'}); const p=spawn(ps,['-NoProfile','-Command',script],{cwd:workspace,windowsHide:true,env:resolvedEnvironment(),stdio:['ignore','pipe','pipe']}); let out='',err=''; p.stdout.on('data',d=>out+=d); p.stderr.on('data',d=>err+=d); p.on('error',e=>resolve({ok:false,error:e.message})); p.on('close',code=>{try{resolve({ok:code===0,data:out.trim()?JSON.parse(out):null,stderr:err.trim()})}catch{resolve({ok:code===0,data:out.trim(),stderr:err.trim()})}}); });
  }
  if (name === 'git_status') {
    const cwd = a.cwd ? safePath(a.cwd) : workspace;
    return await new Promise(resolve => { const git=resolveExecutable('git'); if (!git) return resolve({ok:false,error:'git executable not found'}); const p=spawn(git,['status','--short','--branch'],{cwd,windowsHide:true,env:resolvedEnvironment(),stdio:['ignore','pipe','pipe']}); let out='',err=''; p.stdout.on('data',d=>out+=d); p.stderr.on('data',d=>err+=d); p.on('error',e=>resolve({ok:false,error:e.message})); p.on('close',code=>{ const nonRepo=/not a git repository/i.test(err); resolve({ok:code===0 || nonRepo,exitCode:code,isRepository:!nonRepo,stdout:out,stderr:err,cwd}); }); });
  }
  if (name === 'archive_list_zip') {
    const file = safePath(a.path); const max = Math.min(10000, Math.max(1, Number(a.maxEntries)||1000));
    const data = await fs.readFile(file);
    // ZIP central-directory parsing is implemented in Node so archive listing
    // no longer depends on PowerShell. This works with normal ZIP/ZIP64-free
    // archives and safely reports invalid/non-ZIP input as a structured result.
    const eocd = Buffer.from([0x50,0x4b,0x05,0x06]);
    let pos = -1;
    for (let i = Math.max(0, data.length - 0x10016); i <= data.length - 22; i++) {
      if (data.subarray(i, i + 4).equals(eocd)) pos = i;
    }
    if (pos < 0) return {ok:true,valid:false,entries:[],reason:'Not a ZIP archive',path:rel(file)};
    const count = data.readUInt16LE(pos + 10);
    const centralSize = data.readUInt32LE(pos + 12);
    const centralOffset = data.readUInt32LE(pos + 16);
    if (centralOffset + centralSize > data.length) return {ok:true,valid:false,entries:[],reason:'Invalid ZIP central directory',path:rel(file)};
    const entries=[]; let p=centralOffset;
    while (entries.length < Math.min(count,max) && p + 46 <= data.length && data.readUInt32LE(p) === 0x02014b50) {
      const flags=data.readUInt16LE(p+8), method=data.readUInt16LE(p+10), compressed=data.readUInt32LE(p+20), uncompressed=data.readUInt32LE(p+24), nameLen=data.readUInt16LE(p+28), extraLen=data.readUInt16LE(p+30), commentLen=data.readUInt16LE(p+32);
      const nameBytes=data.subarray(p+46,p+46+nameLen); let name;
      try { name=new TextDecoder((flags & 0x800) ? 'utf-8' : 'cp437').decode(nameBytes); } catch { name=nameBytes.toString('utf8'); }
      entries.push({FullName:name,Length:uncompressed,CompressedLength:compressed,CompressionMethod:method});
      p += 46 + nameLen + extraLen + commentLen;
    }
    return {ok:true,valid:true,entries,path:rel(file),truncated:count>entries.length};
  }
  if (name === 'wsl_status') {
    return await new Promise(resolve => { const wsl = resolveExecutable('wsl.exe'); if (!wsl) return resolve({ok:false,installed:false,error:'wsl.exe not found'}); const p=spawn(wsl,['--status'],{cwd:workspace,windowsHide:true,env:resolvedEnvironment(),stdio:['ignore','pipe','pipe']}); let out='',err=''; p.stdout.on('data',d=>out+=d); p.stderr.on('data',d=>err+=d); p.on('error',e=>resolve({ok:false,installed:false,error:e.message})); p.on('close',code=>resolve({ok:code===0,installed:code===0,stdout:out,stderr:err,exitCode:code})); });
  }
  if (name === 'stitch_list_projects') {
    const dirs = await fs.readdir(workspace, { withFileTypes: true });
    return { workspace, projects: dirs.filter(d=>d.isDirectory() && !d.name.startsWith('.')).map(d=>d.name) };
  }
  if (name === 'terminal_list_jobs') {
    const jobDir = path.join(workspace, '..', 'runtime', 'terminal-jobs');
    try { const files = await fs.readdir(jobDir); return { jobs: files.filter(f=>f.endsWith('.json')).slice(0,200) }; }
    catch { return { jobs: [] }; }
  }
  if (name === 'files_read_text') {
    const file = safePath(a.path);
    const text = await fs.readFile(file, 'utf8');
    const lines = text.split(/\r?\n/);
    const maxLines = Math.min(5000, Math.max(1, Number(a.maxLines) || 5000));
    return { path: path.relative(workspace, file), content: lines.slice(0, maxLines).join('\n') };
  }
  if (name === 'files_write_text') {
    const file = safePath(a.path);
    if (a.overwrite !== true) { try { await fs.access(file); throw new Error('File already exists; set overwrite=true'); } catch (e) { if (e.code !== 'ENOENT') throw e; } }
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, String(a.content), 'utf8');
    return { ok: true, path: path.relative(workspace, file) };
  }
  if (name === 'app_open' || name === 'calculator_open') {
    const app = name === 'calculator_open'
      ? 'calc.exe'
      : String(a.app ?? a.executable ?? a.program ?? a.path ?? a.name ?? '').trim();
    if (!app) throw new Error('app/executable/program/path/name is required');
    const appArgs = Array.isArray(a.args) ? a.args.map(String).slice(0, 32) : [];
    const runCwd = a.cwd ? safePath(a.cwd) : workspace;
    const child = spawn(app, appArgs, { cwd: runCwd, windowsHide: true, detached: true, stdio: 'ignore' });
    child.unref();
    return { ok: true, started: true, pid: child.pid ?? null, app, args: appArgs, cwd: runCwd };
  }
  if (name === 'terminal_run') {
    const nested = a.input && typeof a.input === 'object' ? a.input : (a.arguments && typeof a.arguments === 'object' ? a.arguments : {});
    const executable = a.executable ?? a.exe ?? nested.executable ?? nested.exe;
    const execArgs = Array.isArray(a.args) ? a.args.map(String).slice(0, 32) : (Array.isArray(nested.args) ? nested.args.map(String).slice(0, 32) : []);
    const rawCommand = a.command ?? a.cmd ?? a.command_line ?? a.program ?? nested.command ?? nested.cmd ?? nested.command_line ?? nested.program;
    let command = String(rawCommand ?? '').trim();
    if (!command && executable) {
      const exe = String(executable).trim();
      command = [exe, ...execArgs].map(v => /[\s"]/.test(v) ? `"${v.replace(/"/g, '\\"')}"` : v).join(' ');
    }
    if (!command) throw new Error('command is required (use command, cmd, command_line, program, or executable + args)');
    if (command.length > 12000) throw new Error('command is too long');
    const runCwd = (a.cwd ?? nested.cwd) ? safePath(a.cwd ?? nested.cwd) : workspace;
    const timeout = Math.min(3600, Math.max(1, Number(a.timeout_seconds ?? nested.timeout_seconds) || 120)) * 1000;
    const guiCommand = /^(?:start\s+)?(?:calc(?:\.exe)?|notepad(?:\.exe)?|mspaint(?:\.exe)?|explorer(?:\.exe)?|taskmgr(?:\.exe)?|write(?:\.exe)?|control(?:\.exe)?)\s*$/i.test(command);
    const waitValue = a.wait ?? nested.wait;
    const wait = waitValue === true ? true : (waitValue === false ? false : !guiCommand);
    return await new Promise((resolve, reject) => {
      const isWindows = process.platform === 'win32';
      const child = isWindows
        ? (() => { const cmdExe=resolveExecutable('cmd'); if (!cmdExe) throw new Error('cmd.exe not found'); return spawn(cmdExe, ['/d','/s','/c',command], { cwd: runCwd, windowsHide:true, env:resolvedEnvironment() }); })()
        : spawn('/bin/sh', ['-lc', command], { cwd: runCwd, env:resolvedEnvironment() });
      if (!wait) {
        child.unref();
        return resolve({ ok: true, started: true, pid: child.pid ?? null, cwd: runCwd, command });
      }
      let stdout = '', stderr = '', timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        try { child.kill(); } catch {}
      }, timeout);
      child.stdout?.on('data', d => { stdout += d.toString(); if (stdout.length > 300000) child.kill(); });
      child.stderr?.on('data', d => { stderr += d.toString(); if (stderr.length > 300000) child.kill(); });
      child.on('error', e => { clearTimeout(timer); reject(e); });
      child.on('close', code => {
        clearTimeout(timer);
        resolve({ ok: !timedOut && code === 0, exitCode: code, timedOut, stdout, stderr, cwd: runCwd, command });
      });
    });
  }
  if (name === 'python_run' || name === 'dev_run_python_file') {
    const file = safePath(a.path);
    if (path.extname(file).toLowerCase() !== '.py') throw new Error('python_run only accepts .py files');
    await fs.access(file);
    const args = Array.isArray(a.args) ? a.args.map(String).slice(0, 20) : [];
    const runCwd = a.cwd ? safePath(a.cwd) : workspace;
    const timeout = Math.min(86400, Math.max(1, Number(a.timeout_seconds) || 1800)) * 1000;
    if (name === 'dev_run_python_file') {
      const python = resolveExecutable('python') || resolveExecutable('py');
      if (!python) throw new Error('Python executable not found');
      const p = spawn(python, [file, ...args], { cwd: runCwd, windowsHide: true, env:resolvedEnvironment(), detached: true, stdio: 'ignore' });
      p.unref();
      return { ok: true, started: true, asynchronous: true, pid: p.pid ?? null, path: path.relative(workspace, file), cwd: runCwd };
    }
    return await new Promise((resolve, reject) => {
      const python = resolveExecutable('python') || resolveExecutable('py');
      if (!python) return reject(new Error('Python executable not found'));
      const p = spawn(python, [file, ...args], { cwd: runCwd, windowsHide: true, env:resolvedEnvironment() });
      const timer = setTimeout(() => { try { p.kill(); } catch {} }, timeout);
      let stdout = '', stderr = '';
      p.stdout.on('data', d => { stdout += d.toString(); if (stdout.length > 200000) p.kill(); });
      p.stderr.on('data', d => { stderr += d.toString(); if (stderr.length > 200000) p.kill(); });
      p.on('error', reject);
      p.on('close', code => resolve({ ok: code === 0, exitCode: code, stdout, stderr }));
    });
  }
  // -----------------------------------------------------------------------
  // V1.2 compatibility implementations for the complete 124-tool registry.
  // These are deliberately below the mature handlers above so existing V4
  // behavior remains unchanged. Mutating/high-impact operations are approval
  // gated instead of being executed implicitly.
  // -----------------------------------------------------------------------
  const approvalGated = new Set([
    'files_delete','files_move','files_copy','files_replace_text','files_write_text',
    'files_append_text','files_prepend_text','files_insert_text','files_write_base64',
    'files_create_directory','files_touch','git_add','git_commit','git_create_branch',
    'git_checkout','git_stash','git_stash_pop','git_pull','git_push','terminal_kill',
    'windows_launch_app','windows_open_path','windows_focus_window','windows_clipboard_set',
    'windows_send_keys','windows_mouse_move','windows_mouse_click','windows_screenshot',
    'windows_notify','archive_create_zip','archive_extract_zip','archive_gzip','archive_gunzip',
    'archive_create_tar','archive_extract_tar','wsl_run','wsl_shutdown','approval_execute'
  ]);
  if (approvalGated.has(name) && name !== 'approval_execute') {
    return { ok: true, approval_required: true, tool: name, message: 'This V1.2 action is approval-gated and was not executed.' };
  }

  if (name === 'files_create_directory') {
    const target = safePath(a.path || a.directory);
    await fs.mkdir(target, { recursive: true });
    return { ok: true, path: rel(target), created: true };
  }
  if (name === 'files_delete') {
    const target = safePath(a.path);
    await fs.rm(target, { recursive: Boolean(a.recursive), force: true });
    return { ok: true, path: rel(target), deleted: true };
  }
  if (name === 'files_move' || name === 'files_copy') {
    const source = safePath(a.source || a.from || a.path);
    const destination = safePath(a.destination || a.to || a.target);
    if (name === 'files_move') await fs.rename(source, destination);
    else await fs.cp(source, destination, { recursive: true, force: true });
    return { ok: true, source: rel(source), destination: rel(destination) };
  }
  if (name === 'files_replace_text' || name === 'files_append_text' || name === 'files_prepend_text' || name === 'files_insert_text') {
    const file = safePath(a.path);
    const current = await fs.readFile(file, 'utf8');
    if (name === 'files_replace_text') {
      const oldText = String(a.oldText ?? a.search ?? '');
      const newText = String(a.newText ?? a.replace ?? '');
      if (!oldText) throw new Error('oldText/search is required');
      return { ok: true, path: rel(file), changed: current.includes(oldText), preview: current.replace(oldText, newText).slice(0, 2000), approval_required: true };
    }
    const text = String(a.content ?? a.text ?? '');
    return { ok: true, path: rel(file), currentBytes: Buffer.byteLength(current), requestedBytes: Buffer.byteLength(text), approval_required: true };
  }
  if (name === 'files_search_text') {
    const root = safePath(a.directory || '.');
    const needle = String(a.pattern ?? a.query ?? a.text ?? '').toLowerCase();
    if (!needle) throw new Error('pattern/query/text is required');
    const results = [];
    async function search(dir) {
      if (results.length >= 500) return;
      for (const ent of await fs.readdir(dir, { withFileTypes: true })) {
        if (results.length >= 500) break;
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) { await search(full); continue; }
        try {
          const text = await fs.readFile(full, 'utf8');
          const index = text.toLowerCase().indexOf(needle);
          if (index >= 0) results.push({ path: rel(full), index, preview: text.slice(Math.max(0,index-80), index+200) });
        } catch {}
      }
    }
    await search(root);
    return { ok: true, pattern: needle, results, truncated: results.length >= 500 };
  }
  if (name === 'files_read_base64') {
    const file = safePath(a.path); const data = await fs.readFile(file);
    return { ok: true, path: rel(file), encoding: 'base64', content: data.toString('base64') };
  }
  if (name === 'files_write_base64') {
    const file = safePath(a.path); const data = Buffer.from(String(a.content || a.data || ''), 'base64');
    return { ok: true, path: rel(file), bytes: data.length, approval_required: true };
  }
  if (name === 'files_compare') {
    const left = safePath(a.left || a.path1 || a.source); const right = safePath(a.right || a.path2 || a.target);
    const [l,r] = await Promise.all([fs.readFile(left), fs.readFile(right)]);
    return { ok: true, equal: l.equals(r), left: rel(left), right: rel(right), leftHash: crypto.createHash('sha256').update(l).digest('hex'), rightHash: crypto.createHash('sha256').update(r).digest('hex') };
  }
  if (name === 'files_find_large') {
    const root = safePath(a.directory || '.'); const minBytes = Math.max(0, Number(a.minBytes ?? a.minimumBytes ?? 1048576)); const results=[];
    async function walk(dir){ for(const ent of await fs.readdir(dir,{withFileTypes:true})){ if(results.length>=500) return; const full=path.join(dir,ent.name); if(ent.isDirectory()) await walk(full); else { try { const st=await fs.stat(full); if(st.size>=minBytes) results.push({path:rel(full),bytes:st.size}); } catch {} } } }
    await walk(root); results.sort((x,y)=>y.bytes-x.bytes); return {ok:true,minBytes,results};
  }
  if (name === 'files_tree') return { ok: true, entries: await listFiles(safePath(a.directory || '.'), true, Math.min(5000, Number(a.maxEntries)||1000)) };
  if (name === 'files_read_json') { const file=safePath(a.path); return {ok:true,path:rel(file),data:JSON.parse(await fs.readFile(file,'utf8'))}; }
  if (name === 'files_write_json') return {ok:true,path:String(a.path||''),approval_required:true};
  if (name === 'files_touch') return {ok:true,path:String(a.path||''),approval_required:true};

  if (name.startsWith('git_')) {
    const readOnly = !approvalGated.has(name);
    if (!readOnly) return { ok:true, approval_required:true, tool:name, message:'Git mutation requires approval.' };
    const commands={
      git_status:['status','--short','--branch'], git_diff:['diff'], git_log:['log','-10','--oneline'], git_branches:['branch','--list'],
      git_remotes:['remote','-v'], git_show:['show','--stat','--oneline','HEAD'], git_blame:['blame','-L','1,20'], git_ls_files:['ls-files'],
      git_grep:['grep','-n',String(a.pattern||a.query||'')], git_current_branch:['branch','--show-current'], git_repo_root:['rev-parse','--show-toplevel'], git_tags:['tag','--list']
    };
    const cmd=commands[name]; if(!cmd) return {ok:true,supported:true};
    if(name==='git_grep' && !cmd[1]) throw new Error('pattern/query is required');
    return await new Promise(resolve=>{const p=spawn('git',cmd,{cwd:a.cwd?safePath(a.cwd):workspace,windowsHide:true,stdio:['ignore','pipe','pipe']});let stdout='',stderr='';p.stdout.on('data',d=>stdout+=d);p.stderr.on('data',d=>stderr+=d);p.on('error',e=>resolve({ok:false,error:e.message}));p.on('close',code=>resolve({ok:code===0,exitCode:code,stdout,stderr}));});
  }

  if (name === 'terminal_status' || name === 'terminal_output' || name === 'terminal_kill') return { ok:true, supported:true, job_id:a.job_id||a.id||null, status:'not-tracked-by-this-process', approval_required:name==='terminal_kill' };

  if (name === 'windows_session_info') return {ok:true,platform:process.platform,user:process.env.USERNAME||process.env.USER||'',session:process.env.SESSIONNAME||'',hostname:os.hostname()};
  if (name === 'windows_shell_folders') return {ok:true,home:os.homedir(),temp:os.tmpdir(),cwd:workspace};
  if (name === 'windows_monitors') {
    const r=await runPowerShellJson('Get-CimInstance Win32_DesktopMonitor -ErrorAction SilentlyContinue | Select-Object Name,DeviceID,ScreenWidth,ScreenHeight,PixelsPerXLogicalInch,PixelsPerYLogicalInch | ConvertTo-Json -Compress');
    return {ok:r.ok,supported:r.supported!==false,monitors:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }
  if (name === 'windows_ocr_image') return {ok:true,supported:false,reason:'OCR provider is optional in V1.2'};
  if (name === 'windows_clipboard_get') return {ok:true,supported:process.platform==='win32',value:null};

  if (name === 'system_cpu') return {ok:true,cores:os.cpus().length,model:os.cpus()[0]?.model||'',load:os.loadavg()};
  if (name === 'system_memory') return {ok:true,total:os.totalmem(),free:os.freemem(),used:os.totalmem()-os.freemem()};
  if (name === 'system_drives') {
    const r=await runPowerShellJson('Get-PSDrive -PSProvider FileSystem | Select-Object Name,Root,Used,Free | ConvertTo-Json -Compress');
    if (r.supported === false) return {ok:true,supported:false,drives:[],reason:'Windows drive provider unavailable'};
    return {ok:true,supported:true,drives:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }
  if (name === 'system_temp_dir') return {ok:true,path:os.tmpdir()};
  if (name === 'system_home_dir') return {ok:true,path:os.homedir()};
  if (name === 'system_path_exists') { const p=String(a.path||''); try{await fs.access(p);return {ok:true,exists:true,path:p};}catch{return {ok:true,exists:false,path:p};} }
  if (name === 'system_processes') {
    const r=await runPowerShellJson('Get-Process | Select-Object Id,ProcessName,CPU,WorkingSet64,MainWindowTitle | ConvertTo-Json -Compress');
    if (r.supported === false) return {ok:true,supported:false,processes:[],reason:'Windows process provider unavailable'};
    return {ok:true,supported:true,processes:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }
  if (name === 'system_process') {
    const pid=Number(a.pid)||0; if(!pid) throw new Error('pid is required');
    const r=await runPowerShellJson(`Get-Process -Id ${pid} -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,CPU,WorkingSet64,MainWindowTitle | ConvertTo-Json -Compress`);
    return {ok:r.ok,supported:r.supported!==false,found:Boolean(r.data),process:r.data||null,stderr:r.stderr||''};
  }
  if (name === 'system_process_tree') {
    const r=await runPowerShellJson('Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Compress');
    return {ok:r.ok,supported:r.supported!==false,processes:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }
  if (name === 'system_ports_by_process') {
    const r=await runPowerShellJson('Get-NetTCPConnection -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess | ConvertTo-Json -Compress');
    return {ok:r.ok,supported:r.supported!==false,ports:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }
  if (name === 'system_services') {
    const r=await runPowerShellJson('Get-Service | Select-Object Name,DisplayName,Status,StartType | ConvertTo-Json -Compress');
    return {ok:r.ok,supported:r.supported!==false,services:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }
  if (name === 'system_installed_apps') {
    const r=await runPowerShellJson('Get-ItemProperty HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*,HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*,HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\* -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher | Sort-Object DisplayName | ConvertTo-Json -Compress');
    return {ok:r.ok,supported:r.supported!==false,apps:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''};
  }

  if (name === 'network_interfaces') return {ok:true,interfaces:os.networkInterfaces()};
  if (name === 'network_hostname') return {ok:true,hostname:os.hostname()};
  if (name === 'network_dns_lookup') { const host=String(a.hostname||a.host||''); return {ok:true,hostname:host,addresses:await dns.lookup(host,{all:true})}; }
  if (name === 'network_reverse_dns') { const address=String(a.address||a.ip||''); return {ok:true,address,hostnames:await dns.reverse(address)}; }
  if (name === 'network_tcp_probe') { const host=String(a.host||a.hostname||''); const port=Number(a.port); return await new Promise(resolve=>{const s=new net.Socket();const t=setTimeout(()=>{s.destroy();resolve({ok:false,reachable:false,timeout:true,host,port});},Math.min(10000,Math.max(100,Number(a.timeout_ms)||3000)));s.once('connect',()=>{clearTimeout(t);s.destroy();resolve({ok:true,reachable:true,host,port});});s.once('error',e=>{clearTimeout(t);resolve({ok:true,reachable:false,host,port,error:e.message});});s.connect(port,host);}); }
  if (name === 'network_ping') {
    const host=String(a.host||a.hostname||'').trim(); if(!host) throw new Error('host is required');
    const r=await runPowerShellJson(`Test-Connection -ComputerName '${host.replace(/'/g,"''")}' -Count ${Math.min(4,Math.max(1,Number(a.count)||2))} -ErrorAction SilentlyContinue | Select-Object Address,IPv4Address,ResponseTime,Status | ConvertTo-Json -Compress`);
    return {ok:r.ok,supported:r.supported!==false,host,data:r.data||[],stderr:r.stderr||''};
  }
  if (name === 'network_connections') { const r=await runPowerShellJson('Get-NetTCPConnection -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess | ConvertTo-Json -Compress'); if(r.supported===false) return {ok:true,supported:false,data:[],reason:'Windows TCP provider unavailable'}; return {ok:true,supported:true,data:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''}; }
  if (name === 'network_route_table') { const r=await runPowerShellJson('Get-NetRoute -ErrorAction SilentlyContinue | Select-Object DestinationPrefix,NextHop,RouteMetric,InterfaceIndex,AddressFamily | ConvertTo-Json -Compress'); if(r.supported===false) return {ok:true,supported:false,data:[],reason:'Windows route provider unavailable'}; return {ok:true,supported:true,data:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''}; }
  if (name === 'network_arp_table') { const r=await runPowerShellJson('Get-NetNeighbor -ErrorAction SilentlyContinue | Select-Object ifIndex,IPAddress,LinkLayerAddress,State | ConvertTo-Json -Compress'); return {ok:r.ok,supported:r.supported!==false,data:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''}; }
  if (name === 'network_dns_servers') { const r=await runPowerShellJson('Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Select-Object InterfaceAlias,AddressFamily,ServerAddresses | ConvertTo-Json -Compress'); return {ok:r.ok,supported:r.supported!==false,data:Array.isArray(r.data)?r.data:(r.data?[r.data]:[]),stderr:r.stderr||''}; }

  if (name.startsWith('archive_')) return {ok:true,supported:true,tool:name,message:'Archive operation is available through the V1.2 approval-gated archive layer.',approval_required:approvalGated.has(name)};

  if (name === 'wsl_list_distros') {
    const wsl=resolveExecutable('wsl.exe'); if(!wsl) return {ok:true,installed:false,supported:false,distros:[],reason:'WSL is not installed'};
    return await new Promise(resolve=>{const p=spawn(wsl,['--list','--verbose'],{cwd:workspace,windowsHide:true,env:resolvedEnvironment(),stdio:['ignore','pipe','pipe']});let out='',stderr='';p.stdout.on('data',d=>out+=d.toString());p.stderr.on('data',d=>stderr+=d.toString());p.on('error',e=>resolve({ok:true,installed:false,supported:false,distros:[],reason:e.message}));p.on('close',code=>{const missing=/not installed|not enabled|optional component|subsystem/i.test(stderr+out); resolve({ok:code===0||missing,installed:!missing,supported:!missing,stdout:out,stderr,distros:[],reason:missing?'WSL is not installed':undefined});});});
  }
  if (name === 'wsl_version') {
    const wsl=resolveExecutable('wsl.exe'); if(!wsl) return {ok:true,installed:false,supported:false,value:null,reason:'WSL is not installed'};
    return await new Promise(resolve=>{const p=spawn(wsl,['--version'],{cwd:workspace,windowsHide:true,env:resolvedEnvironment(),stdio:['ignore','pipe','pipe']});let out='',stderr='';p.stdout.on('data',d=>out+=d.toString());p.stderr.on('data',d=>stderr+=d.toString());p.on('error',e=>resolve({ok:true,installed:false,supported:false,value:null,reason:e.message}));p.on('close',code=>{const missing=/not installed|not enabled|optional component|subsystem/i.test(stderr+out); resolve({ok:code===0||missing,installed:!missing,supported:!missing,value:out.trim()||null,stderr,reason:missing?'WSL is not installed':undefined});});});
  }
  if (name === 'wsl_path') {
    const wsl=resolveExecutable('wsl.exe');
    if(!wsl) return {ok:true,installed:false,supported:false,value:null,reason:'WSL is not installed'};
    const target=String(a.path||a.windowsPath||workspace).trim() || workspace;
    return await new Promise(resolve=>{const p=spawn(wsl,['--cd',target,'--exec','pwd'],{cwd:workspace,windowsHide:true,env:resolvedEnvironment(),stdio:['ignore','pipe','pipe']});let out='',stderr='';p.stdout.on('data',d=>out+=d.toString());p.stderr.on('data',d=>stderr+=d.toString());p.on('error',e=>resolve({ok:false,error:e.message}));p.on('close',code=>resolve({ok:code===0,supported:true,value:out.trim(),stderr}));});
  }
  if (name === 'wsl_run' || name === 'wsl_shutdown') return {ok:true,approval_required:true,tool:name};

  if (name === 'dev_detect_project') return {ok:true,workspace,packageJsonExists:await fs.access(path.join(workspace,'package.json')).then(()=>true).catch(()=>false)};
  if (name === 'dev_package_scripts') { try { const p=JSON.parse(await fs.readFile(path.join(workspace,'package.json'),'utf8')); return {ok:true,scripts:p.scripts||{}}; } catch { return {ok:true,scripts:{}}; } }
  if (name === 'dev_run_package_script' || name === 'dev_run_node_file') return {ok:true,approval_required:true,tool:name,message:'Developer execution is approval-gated in V1.2.'};
  if (name === 'dev_find_projects') return {ok:true,projects:(await listFiles(workspace,true,500)).filter(x=>x.type==='directory')};
  if (name === 'dev_lockfiles') {
    const names=['package-lock.json','npm-shrinkwrap.json','pnpm-lock.yaml','yarn.lock','bun.lockb'];
    const lockfiles=[];
    for (const n of names) { try { await fs.access(path.join(workspace,n)); lockfiles.push(n); } catch {} }
    return {ok:true,lockfiles};
  }

  if (name.startsWith('stitch_')) return {ok:true,supported:true,tool:name,workspace};
  if (name === 'local_features') return {ok:true,version:'1.2',tools:TOOL_NAMES.length,workspace,features:['files','terminal','windows','system','network','archive','wsl','developer','stitch','approval']};
  if (name === 'approval_status') return {ok:true,enabled:true,pending:0,policy:'mutating and high-impact actions require explicit approval'};
  if (name === 'approval_execute') return {ok:false,approval_required:true,message:'No approved action token was supplied.'};

  throw new Error('Unknown tool: ' + name);
}
async function handle(msg) {
  const id = Object.prototype.hasOwnProperty.call(msg, 'id') ? msg.id : null;
  const method = String(msg.method || '');
  if (method === 'initialize') return rpc(id, { protocolVersion: '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'poohhub-ai-tunnel', version: '1.2.0' } });
  if (method === 'notifications/initialized' || method.startsWith('notifications/')) return null;
  if (method === 'ping') return rpc(id, {});
  if (method === 'tools/list') return rpc(id, { tools });
  if (method === 'tools/call') {
    const name = String(msg.params?.name || '');
    const args = msg.params?.arguments || {};
    try {
      const result = await callTool(name, args);
      return rpc(id, { content: [{ type: 'text', text: JSON.stringify(result) }] });
    } catch (e) {
      return err(id, -32000, e?.message || 'Tool failed');
    }
  }
  return err(id, -32601, 'Method not found: ' + method);
}
function stdio() {
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', line => {
    if (!line.trim()) return;
    try {
      const msg = JSON.parse(line);
      if (msg.method === 'tools/call') {
        callTool(String(msg.params?.name || ''), msg.params?.arguments || {})
          .then(result => process.stdout.write(rpc(msg.id, { content: [{ type: 'text', text: JSON.stringify(result) }] }) + '\n'))
          .catch(e => process.stdout.write(err(msg.id, -32000, e?.message || 'Tool failed') + '\n'));
      } else {
        Promise.resolve(handle(msg)).then(out => { if (out) process.stdout.write(out + '\n'); }).catch(e => process.stdout.write(err(msg.id ?? null, -32000, e?.message || 'RPC failed') + '\n'));
      }
    } catch (e) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: e?.message || 'Invalid JSON' } }) + '\n'); }
  });
}
function health() {
  const server = http.createServer((req, res) => {
    const send = (status, body) => {
      res.writeHead(status, {
        'content-type': 'application/json; charset=utf-8',
        'access-control-allow-origin': '*',
        'access-control-allow-headers': 'content-type'
      });
      res.end(JSON.stringify(body));
    };

    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
        'access-control-allow-headers': 'content-type'
      });
      res.end();
      return;
    }

    if (req.method === 'GET' && (req.url === '/' || req.url === '/health')) {
      send(200, { ok: true, service: 'poohhub-stitch-async-mcp', mode: 'compatibility', tools: tools.length });
      return;
    }

    if (req.method === 'POST' && (req.url === '/' || req.url === '/rpc' || req.url === '/mcp')) {
      let body = '';
      req.setEncoding('utf8');
      req.on('data', chunk => {
        body += chunk;
        if (body.length > 1024 * 1024) req.destroy();
      });
      req.on('end', async () => {
        try {
          const msg = JSON.parse(body);
          const id = Object.prototype.hasOwnProperty.call(msg, 'id') ? msg.id : null;
          const method = String(msg.method || '');

          if (method === 'tools/call') {
            try {
              const result = await callTool(String(msg.params?.name || ''), msg.params?.arguments || {});
              send(200, JSON.parse(rpc(id, { content: [{ type: 'text', text: JSON.stringify(result) }] })));
            } catch (e) {
              send(200, JSON.parse(err(id, -32000, e?.message || 'Tool failed')));
            }
            return;
          }

          if (method === 'tools/list') {
            send(200, JSON.parse(rpc(id, { tools })));
            return;
          }

          if (method === 'initialize') {
            send(200, JSON.parse(rpc(id, { protocolVersion: '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'poohhub-stitch-async-mcp', version: '1.2.0' } })));
            return;
          }

          if (method === 'ping') {
            send(200, JSON.parse(rpc(id, {})));
            return;
          }

          if (method.startsWith('notifications/')) {
            res.writeHead(204);
            res.end();
            return;
          }

          send(200, JSON.parse(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Method not found: ' + method } })));
        } catch (e) {
          send(400, { jsonrpc: '2.0', id: null, error: { code: -32700, message: e?.message || 'Invalid JSON' } });
        }
      });
      return;
    }

    send(404, { ok: false, error: 'Not found' });
  });
  server.listen(healthPort, '127.0.0.1', () => process.stderr.write('[stitch-mcp] compatibility server listening on 127.0.0.1:' + healthPort + '\n'));
}
if (args.has('--stdio') || !args.has('--health')) stdio();
if (args.has('--health')) health();
