import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const cache = new Map();

function windowsCandidates(name) {
  const n = String(name).replace(/\.exe$|\.cmd$|\.bat$/i, '');
  const home = process.env.USERPROFILE || os.homedir();
  const programFiles = process.env.ProgramFiles || 'C:\\Program Files';
  const programFilesX86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
  const local = process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local');
  const appData = process.env.APPDATA || path.join(home, 'AppData', 'Roaming');
  const roots = [
    process.env.SystemRoot ? path.join(process.env.SystemRoot, 'System32') : 'C:\\Windows\\System32',
    process.env.SystemRoot ? path.join(process.env.SystemRoot) : 'C:\\Windows',
    path.join(programFiles, 'nodejs'),
    path.join(programFilesX86, 'nodejs'),
    path.join(local, 'Programs', 'Python', 'Python313'),
    path.join(local, 'Programs', 'Python', 'Python312'),
    path.join(local, 'Programs', 'Python', 'Python311'),
    path.join(local, 'Programs', 'Python', 'Python310'),
    path.join(local, 'Programs', 'Git', 'cmd'),
    path.join(programFiles, 'Git', 'cmd'),
    path.join(programFiles, 'Git', 'bin'),
    path.join(appData, 'npm'),
  ];
  const names = n.toLowerCase() === 'npm' ? ['npm.cmd', 'npm.exe', 'npm']
    : n.toLowerCase() === 'python' ? ['python.exe', 'python.cmd', 'python']
    : n.toLowerCase() === 'py' ? ['py.exe', 'py.cmd', 'py']
    : n.toLowerCase() === 'git' ? ['git.exe', 'git.cmd', 'git']
    : n.toLowerCase() === 'powershell' ? ['powershell.exe']
    : n.toLowerCase() === 'pwsh' ? ['pwsh.exe']
    : n.toLowerCase() === 'cmd' ? ['cmd.exe']
    : [n + '.exe', n + '.cmd', n];
  return roots.flatMap(r => names.map(x => path.join(r, x)));
}

export function resolveExecutable(command, { required = false } = {}) {
  const raw = String(command || '').trim();
  if (!raw) return null;
  const key = `${process.platform}:${raw.toLowerCase()}`;
  if (cache.has(key)) return cache.get(key);

  const direct = path.isAbsolute(raw) ? [raw] : [];
  // Some MCP clients intentionally start child processes with a minimal
  // environment. Build the search PATH from the current process AND the
  // canonical Windows locations below instead of trusting PATH alone.
  const pathValue = process.env.Path || process.env.PATH || '';
  const pathEntries = pathValue.split(path.delimiter).filter(Boolean);
  const baseNames = process.platform === 'win32'
    ? (raw.includes('.') ? [raw] : [raw, `${raw}.exe`, `${raw}.cmd`, `${raw}.bat`])
    : [raw];
  const candidates = [...direct, ...pathEntries.flatMap(d => baseNames.map(n => path.join(d, n)))];
  if (process.platform === 'win32') candidates.push(...windowsCandidates(raw));

  for (const candidate of candidates) {
    try {
      if (fs.statSync(candidate).isFile()) {
        const resolved = path.normalize(candidate);
        cache.set(key, resolved);
        return resolved;
      }
    } catch {}
  }

  cache.set(key, null);
  if (required) throw new Error(`Executable not found: ${raw}. Checked PATH and standard Windows install locations.`);
  return null;
}

export function commandExists(command) {
  return Boolean(resolveExecutable(command));
}

export function resolvedEnvironment(extra = {}) {
  const env = { ...process.env, ...extra };
  if (process.platform === 'win32') {
    const systemRoot = env.SystemRoot || process.env.SystemRoot || 'C:\\Windows';
    const programFiles = env.ProgramFiles || process.env.ProgramFiles || 'C:\\Program Files';
    const programFilesX86 = env['ProgramFiles(x86)'] || process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
    const localAppData = env.LOCALAPPDATA || process.env.LOCALAPPDATA || path.join(env.USERPROFILE || os.homedir(), 'AppData', 'Local');
    const appData = env.APPDATA || process.env.APPDATA || path.join(env.USERPROFILE || os.homedir(), 'AppData', 'Roaming');
    const additions = [
      path.join(systemRoot, 'System32'),
      systemRoot,
      path.join(programFiles, 'nodejs'),
      path.join(programFilesX86, 'nodejs'),
      path.join(programFiles, 'Git', 'cmd'),
      path.join(programFiles, 'Git', 'bin'),
      path.join(localAppData, 'Programs', 'Python', 'Python313'),
      path.join(localAppData, 'Programs', 'Python', 'Python312'),
      path.join(localAppData, 'Programs', 'Python', 'Python311'),
      path.join(appData, 'npm'),
    ].filter(Boolean);
    const current = env.Path || env.PATH || '';
    const merged = [...current.split(';').filter(Boolean), ...additions];
    env.SystemRoot = systemRoot;
    env.Path = [...new Set(merged)].join(';');
    env.PATH = env.Path;
    // Node's child_process spawn needs PATHEXT when a caller supplied a
    // stripped-down environment. Keeping the normal Windows value here also
    // makes .cmd/.bat resolution deterministic.
    if (!env.PATHEXT) env.PATHEXT = '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC';
  }
  return env;
}

export function resolvePowerShell() {
  if (process.platform !== 'win32') return null;
  const systemRoot = process.env.SystemRoot || 'C:\\Windows';
  const programFiles = process.env.ProgramFiles || 'C:\\Program Files';
  const local = process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE || os.homedir(), 'AppData', 'Local');
  const candidates = [
    path.join(systemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    path.join(programFiles, 'PowerShell', '7', 'pwsh.exe'),
    path.join(local, 'Microsoft', 'PowerShell', '7', 'pwsh.exe'),
  ];
  for (const candidate of candidates) {
    try { if (fs.statSync(candidate).isFile()) return path.normalize(candidate); } catch {}
  }
  return resolveExecutable('powershell') || resolveExecutable('pwsh');
}
