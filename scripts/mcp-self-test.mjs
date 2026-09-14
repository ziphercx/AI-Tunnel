#!/usr/bin/env node
import path from 'node:path';
import fs from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { TOOL_NAMES } from './stitch-tool-registry.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const server = path.join(root, 'scripts', 'stitch-mcp.mjs');
const workspace = path.join(root, 'workspace');

const fixture = '.mcp-self-test.txt';

const tests = [
  ['workspace_info', {}],
  ['files_list', { directory: '.', maxEntries: 20 }],
  ['files_exists', { path: fixture }],
  ['files_stat', { path: fixture }],
  ['files_read_text', { path: fixture, maxLines: 20 }],
  ['files_hash', { path: fixture }],
  ['files_find', { pattern: 'mcp-self-test', maxResults: 20 }],
  ['files_search_text', { pattern: 'POOH HUB', directory: '.' }],
  ['files_tree', { directory: '.', maxEntries: 100 }],
  ['files_read_base64', { path: fixture }],
  ['files_compare', { left: fixture, right: fixture }],
  ['workspace_usage', { path: '.', maxEntries: 5000 }],
  ['git_status', { cwd: '.' }],
  ['git_diff', {}],
  ['git_log', {}],
  ['git_branches', {}],
  ['git_remotes', {}],
  ['git_current_branch', {}],
  ['git_repo_root', {}],
  ['terminal_run', { command: 'echo V1.2-MCP-SELF-TEST' }],
  ['terminal_status', {}],
  ['terminal_output', {}],
  ['terminal_list_jobs', {}],
  ['windows_list_windows', {}],
  ['windows_active_window', {}],
  ['windows_session_info', {}],
  ['windows_shell_folders', {}],
  ['system_info', {}],
  ['system_cpu', {}],
  ['system_memory', {}],
  ['system_temp_dir', {}],
  ['system_home_dir', {}],
  ['system_path_exists', { path: fixture }],
  ['network_interfaces', {}],
  ['network_hostname', {}],
  ['network_dns_lookup', { hostname: 'example.com' }],
  ['network_reverse_dns', { address: '1.1.1.1' }],
  ['network_tcp_probe', { host: '127.0.0.1', port: 9, timeout_ms: 500 }],
  ['archive_list_zip', { path: fixture }],
  ['wsl_list_distros', {}],
  ['wsl_status', {}],
  ['wsl_version', {}],
  ['wsl_path', {}],
  ['dev_toolchains', {}],
  ['dev_versions', {}],
  ['dev_detect_project', {}],
  ['dev_package_scripts', {}],
  ['dev_find_projects', {}],
  ['dev_lockfiles', {}],
  ['stitch_list_projects', {}],
  ['stitch_list_screens', {}],
  ['stitch_job_status', {}],
  ['stitch_job_result', {}],
  ['stitch_list_jobs', {}],
  ['local_features', {}],
  ['approval_status', {}],
];

function request(proc, id, method, params = {}) {
  return new Promise((resolve, reject) => {
    let buffer = '';
    const timer = setTimeout(() => reject(new Error(`${method} timed out`)), 15000);
    const onData = chunk => {
      buffer += chunk.toString();
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() || '';
      for (const line of lines) {
        if (!line.trim()) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg.id !== id) continue;
        clearTimeout(timer);
        proc.stdout.off('data', onData);
        if (msg.error) reject(new Error(msg.error.message || 'RPC error'));
        else resolve(msg.result);
      }
    };
    proc.stdout.on('data', onData);
    proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}

console.log('============================================================');
console.log('POOHHUB MCP BACKEND SELF-TEST');
console.log('============================================================');
console.log(`Workspace : ${workspace}`);
console.log(`Registry  : ${TOOL_NAMES.length} implemented tools`);
console.log('Policy    : only tools in the single registry are advertised');
console.log('');

const proc = spawn(process.execPath, [server, '--stdio'], {
  cwd: root,
  env: { ...process.env, WORKSPACE_PATH: workspace },
  stdio: ['pipe', 'pipe', 'pipe'],
  windowsHide: true,
});
proc.stderr.on('data', d => process.stderr.write(`[server] ${d}`));

let failures = 0;
try {
  await fs.mkdir(workspace, { recursive: true });
  await fs.writeFile(path.join(workspace, fixture), 'POOH HUB V1.2 MCP SELF TEST\\n', 'utf8');
  await request(proc, 1, 'initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'mcp-self-test', version: '1.0.0' }
  });
  proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }) + '\n');
  const list = await request(proc, 3, 'tools/list', {});
  const advertised = (list?.tools || []).map(t => t.name);
  const missing = TOOL_NAMES.filter(n => !advertised.includes(n));
  const extra = advertised.filter(n => !TOOL_NAMES.includes(n));
  console.log(`Registry/Backend : ${advertised.length === TOOL_NAMES.length && !missing.length && !extra.length ? 'PASS' : 'FAIL'}`);
  if (missing.length) console.log(`Missing from backend registry: ${missing.join(', ')}`);
  if (extra.length) console.log(`Unexpected tools: ${extra.join(', ')}`);
  if (missing.length || extra.length || advertised.length !== TOOL_NAMES.length) failures++;

  let id = 10;
  for (const [name, args] of tests) {
    process.stdout.write(`${name.padEnd(24)} `);
    try {
      const result = await request(proc, id++, 'tools/call', { name, arguments: args });
      const text = result?.content?.[0]?.text || '';
      if (text.includes('Unknown tool')) throw new Error(text);
      console.log('PASS');
    } catch (e) {
      failures++;
      console.log(`FAIL — ${e.message}`);
    }
  }
} finally {
  proc.kill();
  try { await fs.rm(path.join(workspace, fixture), { force: true }); } catch {}
}

console.log('');
console.log(`RESULT: ${failures === 0 ? 'PASS' : 'FAIL'} (${failures} failure${failures === 1 ? '' : 's'})`);
process.exitCode = failures === 0 ? 0 : 1;
