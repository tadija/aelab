import { appPath, relativePath } from './basePath';
export type Host = { id: string; name: string; destination?: string; transport?: 'ssh' | 'local' | 'daemon'; daemon?: string; port?: number; dockerContext?: string; background?: string; tint?: string; projects: Project[]; services: Service[]; tools: string[]; plugins: string[] };
export type Project = { id: string;  name: string; directory: string; session?: string };
export type Service = { id: string;  name: string; provider: 'systemd' | 'launchd' | 'docker' | 'compose'; target: string; directory?: string; files?: string[]; environmentFile?: string; plist?: string; logFiles?: string[]; userUnit?: boolean; sudo?: boolean };
export type Tool = { id: string;  name: string; directory?: string; executable: string; arguments: string[]; yoloArguments?: string[]; session?: string };
export type TTYButton = { key: string; label: string };
export type Config = { ttyButtons: TTYButton[]; version: number; tools: Tool[]; plugins: Plugin[]; paths: string[]; hosts: Host[] };
export type Snapshot = { config: Config; revision: string };
export type Result = { status: number; output: string; error: string; truncated: boolean };
export type Discovery = { provider: Service['provider']; target: string; state: string; composeProject?: string; image?: string };
export type Observation = { projectBranches?: Record<string, string>; home?: string; hostname?: string; platform?: string; host: string;  checked: string; reachable: boolean; staleAfterSeconds: number; connection: Result; systemd?: Result; launchd?: Result; docker?: Result; tmux?: Result; discovered: Discovery[]; curated: Record<string, Result> };
export type Launch = { directory?: string; host: string; pinned?: string;  project?: string; tool?: string; session?: string; persistent?: boolean; yolo?: boolean; window?: string };
export function route(path: string): { host?: string; terminal: boolean; project?: string; tool?: string; session?: string; service?: string; pinned?: string; window?: string } {
  const p = relativePath(path).split('/').filter(Boolean).map(decodeURIComponent);
  return { host: p[0] === 'hosts' ? p[1] : undefined, terminal: p[2] === 'tty' || p[2] === 'tools' || p[2] === 'projects', project: p[2] === 'projects' ? p[3] : undefined, tool: p[2] === 'tools' ? p[3] : undefined, session: p[3] === 'tmux' ? p[4] : undefined, pinned: p[3] === 'pinned' ? p[4] : undefined, service: p[2] === 'services' ? p[3] : undefined, window: p[5] };
}
export function shouldCopy(key: string, ctrl: boolean, meta: boolean, shift: boolean, selection: boolean): boolean {
  return key.toLowerCase() === 'c' && ((meta || (ctrl && shift)) || (ctrl && selection));
}
export function terminalURL(launch: Launch): string {
  let path = `/hosts/${encodeURIComponent(launch.host)}/tty/`;
  if (launch.pinned) path += `pinned/${encodeURIComponent(launch.pinned)}/`;
  else if (launch.session) path += `tmux/${encodeURIComponent(launch.session)}/`;
  const params = new URLSearchParams();
  for (const key of ['project', 'tool', 'directory'] as const) if (launch[key] !== undefined) params.set(key, launch[key]!);
  if (launch.persistent) params.set('persistent', '1'); if (launch.yolo) params.set('yolo', '1');
  return appPath(path) + (params.size ? `?${params}` : '');
}

export function prefixBytes(prefix: string): string {
  if (/^C-[a-z]$/.test(prefix)) return String.fromCharCode(prefix.charCodeAt(2) - 96);
  if (/^M-.$/.test(prefix)) return '\x1b' + prefix[2];
  if (prefix === 'C-Space') return '\x00';
  if (prefix === 'Escape') return '\x1b';
  if (prefix.length === 1) return prefix;
  return '\x02';
}

export function discoveryMatchesStatus(item: Discovery, filter: string): boolean {
  if (filter === 'all') return true;
  if (filter !== 'running') return item.state === filter;
  // Native systemd substates and grouped Compose container states remain distinct.
  return item.state.split(',').some(state => state.trim() === 'running' || state.trim() === 'active/running');
}
export function discoveryMatchesSearch(item: Discovery, query: string): boolean {
  const text = [item.target, item.provider, item.state, item.composeProject, item.image].filter(Boolean).join(' ').toLocaleLowerCase();
  return query.trim().toLocaleLowerCase().split(/\s+/).every(word => text.includes(word));
}
export function validTint(value: string | null | undefined): string | undefined {
  return value && /^#[0-9a-f]{6}$/i.test(value) ? value : undefined;
}

export function statusTone(state: string): 'success' | 'warning' | 'error' | 'pending' | 'neutral' {
  const states = state.toLowerCase().split(/[,\s/]+/);
  if (states.some(value => ['critical', 'failed', 'unreachable', 'unavailable', 'permission-denied', 'timeout', 'dead', 'engine-offline', 'discovery-error'].includes(value))) return 'error';
  if (states.some(value => ['warning', 'inactive', 'exited', 'stopped', 'paused', 'deactivating', 'unloaded'].includes(value))) return 'warning';
  if (states.some(value => ['checking', 'activating', 'restarting'].includes(value))) return 'pending';
  if (states.some(value => ['ok', 'active', 'running', 'reachable', 'available', 'installed'].includes(value))) return 'success';
  return 'neutral';
}

/** Names are the sole persisted identity; IDs are derived view data. */
export function nameID(name: string): string {
  return name.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}
export function identify<T extends { name: string }>(item: T): T & { id: string } { return { ...item, id: nameID(item.name) }; }
export function identifyConfig(config: Config): Config {
  return { ...config, tools: config.tools.map(identify), plugins: config.plugins.map(identify), hosts: config.hosts.map(host => ({ ...identify(host), projects: host.projects.map(identify), services: host.services.map(identify) })) };
}
export function definitionPayload<T extends { id: string }>({ id: _id, ...item }: T): Omit<T, 'id'> { return item; }
export function configurationPayload(config: Config): unknown {
  return { ...config, tools: config.tools.map(definitionPayload), plugins: config.plugins.map(definitionPayload), hosts: config.hosts.map(host => ({ ...definitionPayload(host), projects: host.projects.map(definitionPayload), services: host.services.map(definitionPayload) })) };
}
export type EntityKind = 'hosts' | 'projects' | 'services' | 'tools' | 'plugins';
export function renameReferences(config: Config, kind: 'tools' | 'plugins', from: string, to: string): void {
  if (from === to) return;
  for (const host of config.hosts) {
    host[kind] = host[kind].map(id => id === from ? to : id);
  }
}
export function hostLocation(host: Host): string { return host.transport === 'local' ? 'local · server process' : host.destination ?? ''; }

export type DiscoveredTool = { tool: Tool; state: 'installed' | 'unavailable' | 'discovery-error'; path?: string; error?: string; enabled: boolean };
export type ToolInventory = { host: string; checked: string; staleAfterSeconds: number; tools: DiscoveredTool[] };
export type PluginSource = { id: string; name: string; filename: string; language: string };
export type PluginAvailability = { plugin: string; state: string; error?: string; source?: PluginSource };
export function enabledTools(config: Config, host: Host): Tool[] { return config.tools.filter(tool => host.tools.includes(tool.id)); }

export type Plugin = { source?: string; id: string; name: string; executable: string; arguments: string[]; timeout?: number };
export type PluginReport = { version: number; status: 'ok' | 'warning' | 'critical' | 'unknown'; summary: string; details: { label: string; value: string }[] };
export type PluginObservation = { host: string; plugin: string; checked: string; exitStatus: number; report?: PluginReport; error?: string };

export type PinnedSession = { number: number; id: string; host: string; cwd: string; project?: string; tool?: string };

export type HostDirectory = { name: string; path: string };
export type DirectoryListing = { host: string; path: string; home: string; parent?: string; directories: HostDirectory[]; truncated: boolean };
export type PluginDeployment = { sourceHost: string; targetHost: string; plugin: string; filename: string; sourcePath: string; targetPath: string; configurationRevision: string; sourceRevision: string; targetRevision?: string; requiresBuild: boolean };
export function pluginHasSource(plugin: Plugin): boolean { return [plugin.source, plugin.executable, ...plugin.arguments].some(path => path !== undefined && /^(?:\/|~\/).*\.(?:sh|bash|rb|swift)$/.test(path)); }

export function tmuxSessionMessage(result: Result): string {
  const message = (result.error || result.output).trim();
  const noServer = /^(?:no sessions|no server running on .+|error connecting to .+ \((?:No such file or directory|Connection refused)\)|failed to connect to server: (?:No such file or directory|Connection refused))$/i;
  if ((result.status === 0 && !result.output.trim()) || (result.status === 1 && !result.output.trim() && noServer.test(message))) return 'No active tmux sessions';
  return message || 'Unable to list tmux sessions';
}

export function serviceDiscoveryMessage(provider: string, result: Result): string {
  const diagnostic = (result.error || result.output).trim();
  if (provider === 'docker') {
    if (result.status === 127 && /docker/i.test(diagnostic)) return 'Docker CLI is unavailable. Check installation and the host PATH.';
    if (result.status === 1 && !/permission denied|access denied|unauthorized|certificate|x509/i.test(diagnostic) && /cannot connect to the docker daemon|failed to connect to the docker api|is the docker daemon running/i.test(diagnostic)) return 'Docker engine unavailable';
  }
  return diagnostic || `${provider} discovery failed (exit ${result.status}).`;
}
export function launchdState(result: Result, discovered?: string): string {
  if (result.status !== 0) {
    if (result.status === 124) return 'timeout';
    if (/permission|not privileged|not permitted/i.test(result.error)) return 'permission-denied';
    return /could not find service|no such process/i.test(result.error) ? 'unloaded' : 'unavailable';
  }
  if (discovered) return discovered;
  const state = result.output.match(/^\s*state = (.+)$/m)?.[1].trim();
  return state === 'running' ? 'running' : ['not running','waiting','exited'].includes(state ?? '') ? 'stopped' : 'unknown';
}
