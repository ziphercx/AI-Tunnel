// POOH HUB AI-Tunnel V1.2 — canonical 124-tool registry.
// This file is the single source of truth for tools/list and tools/call.
// Schemas intentionally accept additional properties so older V1 clients remain compatible.
const obj = () => ({ type: 'object', additionalProperties: true });

const TOOL_NAMES_124 = [
  // WORKSPACE / FILES (26)
  'workspace_info','files_list','files_stat','files_read_text','files_write_text','files_replace_text','files_search_text','files_create_directory','files_move','files_delete','files_exists','files_copy','files_append_text','files_prepend_text','files_insert_text','files_read_base64','files_write_base64','files_hash','files_compare','files_find','files_find_large','files_tree','files_read_json','files_write_json','files_touch','workspace_usage',
  // GIT (20)
  'git_status','git_diff','git_log','git_branches','git_remotes','git_show','git_blame','git_ls_files','git_grep','git_current_branch','git_repo_root','git_tags','git_add','git_commit','git_create_branch','git_checkout','git_stash','git_stash_pop','git_pull','git_push',
  // TERMINAL (5)
  'terminal_run','terminal_status','terminal_output','terminal_list_jobs','terminal_kill',
  // WINDOWS (14)
  'windows_list_windows','windows_active_window','windows_monitors','windows_session_info','windows_shell_folders','windows_ocr_image','windows_launch_app','windows_open_path','windows_focus_window','windows_clipboard_get','windows_clipboard_set','windows_send_keys','windows_mouse_move','windows_mouse_click','windows_screenshot','windows_notify',
  // SYSTEM (13)
  'system_info','system_cpu','system_memory','system_drives','system_services','system_installed_apps','system_processes','system_process','system_process_tree','system_ports_by_process','system_temp_dir','system_home_dir','system_path_exists',
  // NETWORK (10)
  'network_interfaces','network_hostname','network_dns_lookup','network_reverse_dns','network_tcp_probe','network_ping','network_connections','network_route_table','network_arp_table','network_dns_servers',
  // ARCHIVE (8)
  'archive_list_zip','archive_create_zip','archive_extract_zip','archive_gzip','archive_gunzip','archive_list_tar','archive_create_tar','archive_extract_tar',
  // WSL (6)
  'wsl_list_distros','wsl_status','wsl_version','wsl_path','wsl_run','wsl_shutdown',
  // DEVELOPER (9)
  'dev_toolchains','dev_versions','dev_detect_project','dev_package_scripts','dev_run_package_script','dev_run_node_file','dev_run_python_file','dev_find_projects','dev_lockfiles',
  // STITCH (8)
  'stitch_create_project','stitch_list_projects','stitch_list_screens','stitch_start_generate','stitch_job_status','stitch_job_result','stitch_list_jobs','stitch_pull_screen_artifacts',
  // FEATURES / APPROVAL (3)
  'local_features','approval_status','approval_execute'
];

if (TOOL_NAMES_124.length !== 124) throw new Error(`V1.2 registry must contain exactly 124 tools; found ${TOOL_NAMES_124.length}`);
if (new Set(TOOL_NAMES_124).size !== 124) throw new Error('V1.2 registry contains duplicate tool names');

export const TOOL_REGISTRY = TOOL_NAMES_124.map(name => [
  name,
  `POOH HUB AI-Tunnel V1.2 ${name}`,
  obj()
]);
export const TOOLS = TOOL_REGISTRY.map(([name, description, inputSchema]) => ({ name, description, inputSchema }));
export const TOOL_NAMES = TOOL_NAMES_124;
