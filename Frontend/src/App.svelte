<script lang="ts">
  import { appPath } from './basePath';
  import { onMount } from 'svelte';
  import { ConfigurationClient, RequestError } from './configuration';
  import Icon from './Icon.svelte';
  import Logo from './Logo.svelte';
  import Reorder from './Reorder.svelte';
  import DirectoryPicker from './DirectoryPicker.svelte';
  import PluginDeployment from './PluginDeployment.svelte';
  import { moveRow, sortable } from './rowOrder';
  import Terminal from './Terminal.svelte';
  import ConfigForm from './ConfigForm.svelte';
  import Section from './Section.svelte';
  import HostPicker from './HostPicker.svelte';
  import ProjectsSection from './ProjectsSection.svelte';
  import StatusBadge from './StatusBadge.svelte';
  import PluginEditor from './PluginEditor.svelte';
  import ConfigEditor from './ConfigEditor.svelte';
  import { route, terminalURL, nameID, identify, definitionPayload, hostLocation, launchdState, serviceDiscoveryMessage, pluginHasSource, discoveryMatchesStatus, discoveryMatchesSearch, validTint, type PluginAvailability, type PinnedSession, type Plugin, type PluginObservation, type ToolInventory, type Host, type Project, type Service, type Tool, type Snapshot, type Config, type Observation, type Result, type Launch, type Discovery } from './model';
  let authenticated = $state(false); let loading = $state(true); let csrf = $state(''); let password = $state(''); let error = $state('');
  let snapshot = $state<Snapshot>(); let pathname = $state(location.pathname); let selected = $state(route(location.pathname).host ?? '');
  const configuration = new ConfigurationClient(request, value => snapshot = value);
  let enablePending = $state<Record<string, boolean>>({});
  let projectYolo = $state<Record<string, boolean>>({});
  let pinnedOnly = $state<Record<string, boolean>>({});
  let pinnedShells = $state<Record<string, PinnedSession[]>>({});
  let observations = $state<Record<string, Observation>>({}); let pending = $state<Record<string, boolean>>({});
  let now = $state(Date.now()); let hostThemes = $state<Record<string, string>>({});
  const themeKey = $derived(selected || 'overview');
  const theme = $derived(hostThemes[themeKey] ?? localStorage.getItem(`aelab-theme:${themeKey}`) ?? 'dark');
  function toggleTheme() { hostThemes[themeKey] = theme === 'dark' ? 'light' : 'dark'; localStorage.setItem(`aelab-theme:${themeKey}`, hostThemes[themeKey]); }
  let form = $state<{ kind: 'hosts' | 'projects' | 'services' | 'tools' | 'plugins'; existing?: Host | Project | Service | Tool | Plugin }>();
  let directoryChoice = $state<{ host: string; tool: Tool; yolo: boolean }>();
  let deployment = $state<{ host: string; plugin: string }>();
  const localHosts = $derived((snapshot?.config.hosts ?? []).filter(host => host.transport === 'local'));
  let editorOpen = $state(false); let pluginEditor = $state<{ host: string; plugin: string }>(); let launchMenu = $state(false);
  let sectionState = $state<Record<string, Record<string, boolean>>>({});
  async function loadSections() { sectionState = await request('/api/state/sections'); }
  let stateWrites = Promise.resolve();
  function toggleSection(key: string, value: boolean) {
    const id = selected || 'overview'; sectionState[id] = { ...sectionState[id], [key]: value };
    const sections = { ...sectionState[id] };
    stateWrites = stateWrites.catch(() => {}).then(async () => { await request('/api/state/sections', 'PUT', { host: id, sections }); }).catch(e => { error = String(e); });
  }
  async function killPinned(id: string) {
    if (!confirm('End this pinned terminal and its running programs?')) return;
    try { await request(`/api/hosts/${selected}/terminals/${id}`, 'DELETE'); await refresh(selected); } catch (e) { error = String(e); }
  }
  async function renameSession(name: string) {
    const value = prompt('Rename tmux session. Existing links using the old name will need updating.', name);
    if (value === null || value === name) return;
    try { const result = await request<Result>(`/api/hosts/${encodeURIComponent(selected)}/tmux/sessions/${encodeURIComponent(name)}`, 'PATCH', { name: value }); if (result.status) throw new Error(result.error || result.output); await refresh(selected); } catch (e) { error = String(e); }
  }
  async function killSession(name: string) {
    if (!confirm(`End tmux session “${name}” on ${host?.name}? Its running programs will be terminated.`)) return;
    try { const result = await request<Result>(`/api/hosts/${encodeURIComponent(selected)}/tmux/sessions/${encodeURIComponent(name)}`, 'DELETE'); if (result.status) throw new Error(result.error || result.output); await refresh(selected); } catch (e) { error = String(e); }
  }
  let log = $state<{ title: string; content: string }>(); let busyAction = $state('');
  let pluginResults = $state<Record<string, PluginObservation>>({});
  let probing = $state<Record<string, boolean>>({});
  async function probePlugin(plugin: Plugin) {
    const id = selected; const key = `${id}:${plugin.id}`;
    if (probing[key]) return; probing[key] = true;
    try { pluginResults[key] = await request<PluginObservation>(`/api/hosts/${encodeURIComponent(id)}/plugins/${encodeURIComponent(plugin.id)}/runs`, 'POST', {}); }
    catch (e) { error = String(e); } finally { probing[key] = false; }
  }
  let launchContainer = $state<HTMLDivElement>();
  function dismissLaunch(event: PointerEvent) { if (event.target instanceof Node && !launchContainer?.contains(event.target)) launchMenu = false; }
  function toggleShells() { if (host) toggleSection('shells', !(sectionState[selected]?.shells ?? true)); }
  let discoveryView = $state<Record<string, boolean>>({});
  function showingDiscovery(kind: 'tools' | 'services' | 'plugins') { return discoveryView[`${selected}:${kind}`] ?? false; }
  function toggleDiscovery(kind: 'tools' | 'services' | 'plugins') {
    discoveryView[`${selected}:${kind}`] = !showingDiscovery(kind);
    if (sectionState[selected]?.[kind] === false) toggleSection(kind, true);
  }
  let discoveryStatus = $state('running');
  let discoverySearch = $state('');
  let toolInventories = $state<Record<string, ToolInventory>>({});
  let discovering = $state<Record<string, boolean>>({});
  async function discoverTools(id: string, force = false) {
    if (discovering[id]) return; discovering[id] = true;
    try { const inventory = await request<ToolInventory>(`/api/hosts/${encodeURIComponent(id)}/tools`, force ? 'POST' : 'GET'); toolInventories[id] = { ...inventory, tools: inventory.tools.map(row => ({ ...row, tool: identify(row.tool) })) }; }
    catch (e) { error = String(e); } finally { discovering[id] = false; }
  }
  function toolDiscovery(tool: Tool) { return toolInventories[selected]?.tools.find(row => row.tool.id === tool.id); }
  function toolState(tool: Tool) { return toolDiscovery(tool)?.state ?? 'checking'; }
  let pluginAvailability = $state<Record<string, PluginAvailability[]>>({});
  async function discoverPlugins(id: string) {
    try { pluginAvailability[id] = await request<PluginAvailability[]>(`/api/hosts/${encodeURIComponent(id)}/plugins`); }
    catch (e) { error = String(e); }
  }
  function pluginState(id: string) { return pluginAvailability[selected]?.find(row => row.plugin === id)?.state ?? 'checking'; }
  async function toggleEnabled(kind: 'tools' | 'plugins', id: string) {
    const hostID = selected, key = `${hostID}:${kind}:${id}`;
    if (enablePending[key]) return;
    const enabled = !snapshot!.config.hosts.find(h => h.id === hostID)![kind].includes(id);
    enablePending[key] = true;
    try {
      await configuration.update(config => {
        const h = config.hosts.find(h => h.id === hostID);
        if (!h || !config[kind].some(item => item.id === id)) throw new Error('Host or definition was removed. Reload configuration.');
        h[kind] = enabled ? [...new Set([...h[kind], id])] : h[kind].filter(value => value !== id);
      });
    } catch (e) { error = String(e); } finally { enablePending[key] = false; }
  }
  let hostTints = $state<Record<string, string>>({});
  function tintFor(item?: Host) { return item ? validTint(hostTints[item.id] ?? localStorage.getItem(`aelab-tint:${item.id}`) ?? item.tint) : undefined; }
  function setHostTint(value: string) {
    if (!selected || !validTint(value)) return;
    hostTints[selected] = value; localStorage.setItem(`aelab-tint:${selected}`, value);
  }
  $effect(() => {
    if (selected && hostTint) document.documentElement.style.setProperty('--accent', hostTint);
    else document.documentElement.style.setProperty('--accent', 'var(--muted)');
  });
  const parsed = $derived(route(pathname));
  const host = $derived(snapshot?.config.hosts.find(h => h.id === selected));
  const tools = $derived((snapshot?.config.tools ?? []).filter(tool => host?.tools.includes(tool.id)));
  const plugins = $derived((snapshot?.config.plugins ?? []).filter(plugin => host?.plugins.includes(plugin.id)));
  const hostTint = $derived(tintFor(host));
  const observation = $derived(observations[selected]);
  const filteredDiscovery = $derived((observation?.discovered ?? []).filter(item => discoveryMatchesStatus(item, discoveryStatus) && discoveryMatchesSearch(item, discoverySearch) && !host?.services.some(service => service.provider === item.provider && service.target === item.target)));
  const discoveryStates = $derived([...new Set((observation?.discovered ?? []).map(item => item.state))].filter(state => state !== 'running').sort());
  const config = $derived(snapshot?.config);
  const terminalLaunch = $derived.by(() => {
    const query = new URLSearchParams(location.search);
    return { host: parsed.host ?? '', project: query.get('project') ?? parsed.project, tool: query.get('tool') ?? parsed.tool, session: parsed.session, pinned: parsed.pinned, directory: query.get('directory') ?? undefined, persistent: query.has('persistent') ? query.get('persistent') === '1' : undefined, yolo: query.get('yolo') === '1', window: parsed.window } satisfies Launch;
  });
  $effect(() => { document.documentElement.dataset.theme = theme; });
  $effect(() => { if (!parsed.terminal) document.title = host ? `${host.name}@aelab` : 'aelab'; });
  async function request<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
    let response: Response;
    try { response = await fetch(appPath(path), { method, headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }); }
    catch { throw new Error('Server is offline'); }
    const result = await response.json();
    if (!response.ok) { if (response.status === 401) authenticated = false; throw new RequestError(result.error?.message ?? response.statusText, response.status); }
    return result;
  }
  async function refreshConfig() { await configuration.load(); }
  async function login(event: SubmitEvent) {
    event.preventDefault(); error = '';
    try { const session = await request<{ csrf: string }>('/api/auth/session', 'POST', { password }); csrf = session.csrf; password = ''; authenticated = true; await refreshConfig(); await loadSections(); if (selected) await refresh(selected); }
    catch (e) { error = String(e); }
  }
  async function logout() { try { await request('/api/auth/session', 'DELETE'); authenticated = false; } catch (e) { error = String(e); } }
  async function refresh(id: string) {
    if (pending[id]) return; pending[id] = true;
    void discoverTools(id); void discoverPlugins(id);
    try {
      const [status, pins] = await Promise.all([request<Observation>(`/api/hosts/${encodeURIComponent(id)}/status`), request<PinnedSession[]>(`/api/hosts/${encodeURIComponent(id)}/terminals`)]);
      observations[id] = status; pinnedShells[id] = pins;
    }
    catch (e) { error = String(e); } finally { pending[id] = false; }
  }
  function choose(id: string) { discoverySearch = ''; selected = id; launchMenu = false; history.pushState({}, '', appPath(id ? `/hosts/${encodeURIComponent(id)}/` : '/')); pathname = location.pathname; if (id) void refresh(id); }
  async function save(updated: Config, revision = snapshot!.revision) {
    const previous = snapshot!.config;
    const oldHost = form?.kind === 'hosts' ? form.existing as Host | undefined : undefined;
    const newHost = oldHost ? updated.hosts.find(item => !previous.hosts.some(old => old.id === item.id)) : undefined;
    const saved = await configuration.replace(updated, revision);
    if (oldHost && newHost) {
      for (const prefix of ['aelab-theme:', 'aelab-tint:']) { const value = localStorage.getItem(prefix + oldHost.id); if (value !== null) { localStorage.setItem(prefix + newHost.id, value); localStorage.removeItem(prefix + oldHost.id); } }
      const cwdPrefix = `aelab-tty-cwd-background:${oldHost.id}:`;
      for (const key of Object.keys(localStorage).filter(key => key.startsWith(cwdPrefix))) { localStorage.setItem(`aelab-tty-cwd-background:${newHost.id}:` + key.slice(cwdPrefix.length), localStorage.getItem(key)!); localStorage.removeItem(key); }
      hostThemes[newHost.id] = hostThemes[oldHost.id] ?? localStorage.getItem(`aelab-theme:${newHost.id}`) ?? 'dark';
      if (sectionState[oldHost.id]) { sectionState[newHost.id] = sectionState[oldHost.id]; delete sectionState[oldHost.id]; }
      if (selected === oldHost.id) choose(newHost.id);
    }
    for (const kind of ['tools','plugins'] as const) if (saved.config[kind].some(item => !previous[kind].some(old => old.id === item.id))) discoveryView[`${selected}:${kind}`] = true;
    const connection = (config: Config) => { const h = config.hosts.find(h => h.id === selected); return [h?.destination, h?.port, h?.transport]; };
    if (selected && JSON.stringify([previous.tools, previous.plugins, previous.paths, connection(previous)]) !== JSON.stringify([saved.config.tools, saved.config.plugins, saved.config.paths, connection(saved.config)])) { void discoverTools(selected, true); void discoverPlugins(selected); }
    if (selected && previous.hosts.find(host => host.id === selected)?.dockerContext !== saved.config.hosts.find(host => host.id === selected)?.dockerContext) void refresh(selected);
    for (const item of saved.config.hosts) {
      if (item.tint !== previous.hosts.find(h => h.id === item.id)?.tint && validTint(item.tint)) {
        hostTints[item.id] = item.tint!; localStorage.setItem(`aelab-tint:${item.id}`, item.tint!);
      }
    }
  }
  let reordering = $state(false);
  async function reorderRows(kind: 'hosts' | 'projects' | 'services' | 'tools' | 'plugins', id: string, target: string) {
    if (reordering || id === target) return;
    const hostID = selected; reordering = true;
    try {
      await configuration.update(config => {
        const rows: { id: string }[] | undefined = kind === 'hosts' || kind === 'tools' || kind === 'plugins' ? config[kind] : config.hosts.find(h => h.id === hostID)?.[kind];
        if (!rows || !moveRow(rows, id, target)) throw new Error('Row was removed. Reload configuration.');
      });
    } catch (e) { error = String(e); } finally { reordering = false; }
  }
  async function remove(kind: 'hosts' | 'projects' | 'services' | 'tools' | 'plugins', id: string) {
    const shared = kind === 'tools' || kind === 'plugins';
    if (shared && host?.transport !== 'local') return;
    if (shared && !confirm(`Delete this shared ${kind === 'tools' ? 'tool' : 'plugin'} definition from all hosts? Files and running programs are kept. Use Discovery to disable it only on one host.`)) return;
    if (!shared && !confirm(kind === 'hosts' ? `Delete host “${id}” and its projects, services and enabled selections? Running programs are not stopped.` : `Delete ${kind} entry “${id}”? This changes configuration only.`)) return;
    try {
      const updated = structuredClone($state.snapshot(snapshot!.config));
      const rows = (kind === 'hosts' ? updated.hosts : shared ? updated[kind as 'tools' | 'plugins'] : updated.hosts.find(h => h.id === selected)![kind]) as { id: string }[]; const index = rows.findIndex(x => x.id === id); if (index < 0) throw new Error("Entry no longer exists"); rows.splice(index, 1);
      if (shared) for (const h of updated.hosts) { const collection = kind as 'tools' | 'plugins'; h[collection] = h[collection].filter(value => value !== id); }
      await save(updated);
      if (kind === "hosts" && selected === id) choose('');
    } catch (e) { error = String(e); }
  }
  async function serviceAction(service: Service, operation: string) {
    if (!['status', 'logs'].includes(operation) && !confirm(`${operation} ${service.provider} ${service.target} on ${host?.name}?`)) return;
    busyAction = service.id; error = '';
    try {
      const read = ['status', 'logs'].includes(operation);
      const path = `/api/hosts/${encodeURIComponent(selected)}/services/${encodeURIComponent(service.id)}`;
      const result = await request<Result>(path + (read ? operation === 'logs' ? '/logs' : '' : '/actions'), read ? 'GET' : 'POST', read ? undefined : { action: operation });
      log = { title: `${host?.name} · ${service.name} · ${operation}`, content: `${result.output}${result.error ? '\n' + result.error : ''}${result.truncated ? '\n[output truncated]' : ''}` };
      if (result.status) error = ['docker', 'compose'].includes(service.provider) ? serviceDiscoveryMessage('docker', result) : `Command exited ${result.status}`; else if (!['status', 'logs'].includes(operation)) await refresh(selected);
    } catch (e) { error = String(e); } finally { busyAction = ''; }
  }
  function open(launch: Omit<Launch, 'host'>) {
    window.open(terminalURL({ ...launch, host: selected }), '_blank', 'noopener');
  }
  function openTool(tool: Tool, yolo = false) {
    if (tool.directory) open({ tool: tool.id, yolo });
    else directoryChoice = { host: selected, tool, yolo };
  }
  async function curate(item: Discovery) {
    form = { kind: 'services', existing: undefined };
    // Pin uses the regular editor; all discovered candidates still require an explicit validated save.
    const id = nameID(item.target);
    const service: Service = { id, name: item.target, provider: item.provider, target: item.target };
    const updated = structuredClone($state.snapshot(snapshot!.config)); updated.hosts.find(h => h.id === selected)!.services.push(service);
    try { await save(updated); form = { kind: 'services', existing: service }; } catch (e) { error = String(e); form = undefined; }
  }
  function nativeState(service: Service): string {
    const value = observation?.curated[service.id];
    if (!value) return 'unknown';
    if (service.provider === 'launchd') return launchdState(value, observation?.discovered.find(item => item.provider === 'launchd' && item.target === service.target)?.state);
    if (value.status !== 0 && ['docker', 'compose'].includes(service.provider) && serviceDiscoveryMessage('docker', value) === 'Docker engine unavailable') return 'engine-offline';
    if (value.status !== 0) return value.status === 124 ? 'timeout' : value.error.includes('Permission') || value.error.includes('permission') ? 'permission-denied' : 'unavailable';
    if (service.provider === 'systemd') return value.output.match(/^ActiveState=(.+)$/m)?.[1] ?? 'unknown';
    if (service.provider === 'docker') { try { return JSON.parse(value.output).Status ?? 'unknown'; } catch { return 'unknown'; } }
    return observation?.discovered.find(d => d.provider === 'compose' && d.target === service.target)?.state ?? 'inspect status';
  }
  function hostState(id: string) { return pending[id] ? 'checking' : !observations[id] ? 'unknown' : observations[id].reachable ? 'reachable' : 'unreachable'; }
  function stale(item?: Observation) { return !item || now - Date.parse(item.checked) > item.staleAfterSeconds * 1000; }
  let shortcutDigits = ''; let shortcutTimer: ReturnType<typeof setTimeout>;
  function pinnedShortcut(event: KeyboardEvent) {
    if (parsed.terminal || !authenticated || form || editorOpen || pluginEditor || launchMenu || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.repeat) return;
    const target = event.target;
    if (target instanceof Element && target.closest('input,textarea,select,button,a,[contenteditable]')) return;
    if (!/^[0-9]$/.test(event.key) && !(event.key === 'Enter' && shortcutDigits)) { clearTimeout(shortcutTimer); shortcutDigits = ''; return; }
    event.preventDefault(); clearTimeout(shortcutTimer);
    if (event.key !== 'Enter') shortcutDigits += event.key;
    const initialHost = selected;
    const openNumber = () => { const number = Number(shortcutDigits); shortcutDigits = ''; if (selected !== initialHost || form || editorOpen || document.activeElement?.matches('input,textarea,select,button,a,[contenteditable]')) return; const pin = pinnedShells[selected]?.find(pin => pin.number === number); if (pin) open({ pinned: pin.id, project: pin.project, tool: pin.tool }); };
    if (event.key === 'Enter') openNumber(); else shortcutTimer = setTimeout(openNumber, 450);
  }
  onMount(() => {
    let disposed = false;
    void (async () => {
      try { const session = await request<{ csrf: string }>('/api/auth/session'); csrf = session.csrf; authenticated = true; await refreshConfig(); await loadSections(); if (!disposed && selected && !parsed.terminal) await refresh(selected); }
      catch (e) { if (authenticated || String(e).includes('Server is offline')) error = String(e); } finally { loading = false; }
    })();
    const timer = setInterval(() => { now = Date.now(); if (authenticated && !document.hidden && !parsed.terminal) { if (selected) void refresh(selected); else for (const h of config?.hosts ?? []) void refresh(h.id); } }, 15000);
    const external = setInterval(() => { if (authenticated && !form && !editorOpen && !parsed.terminal) void refreshConfig().catch(e => error = String(e)); }, 30000);
    const pop = () => { pathname = location.pathname; selected = route(location.pathname).host ?? ''; if (selected) void refresh(selected); }; window.addEventListener('popstate', pop);
    return () => { disposed = true; clearTimeout(shortcutTimer); clearInterval(timer); clearInterval(external); window.removeEventListener('popstate', pop); };
  });
</script>
<svelte:window onpointerdown={dismissLaunch} onkeydown={event => { if (event.key === 'Escape') { launchMenu = false; shortcutDigits = ''; clearTimeout(shortcutTimer); } else pinnedShortcut(event); }} />
{#if loading}<main class="loading-page"><div class="loading-state" role="status"><span class="loader" aria-hidden="true"></span><span>Loading aelab…</span></div></main>
{:else if !authenticated}
  <main class="login"><div class="brand"><span class="tint-trigger" aria-hidden="true"><Logo /></span><h1>aelab</h1></div><p class="muted">central host console</p><form class="login-form" onsubmit={login}><input type="password" aria-label="Administrator password" placeholder="Password" autocomplete="current-password" required bind:value={password} /><button>Sign in</button></form>{#if error}<p class="error">{error}</p>{/if}</main>
{:else if parsed.terminal && config?.hosts.find(h => h.id === parsed.host)}
  <Terminal logoColor={hostTint ?? (theme === 'dark' ? '#a4afba' : '#57534e')} tools={config.tools} launch={terminalLaunch} host={config.hosts.find(h => h.id === parsed.host)!} buttons={config.ttyButtons} {csrf} {request} />
{:else}
  <main class="dashboard">
    <header class="topbar"><div class="brand"><label class="tint-trigger" title={host ? `Tint for ${host.name}` : 'Select a host to set its tint'}>
      <Logo />
      <input type="color" aria-label="Host tint" disabled={!host} value={hostTint ?? (theme === 'dark' ? '#2dd4bf' : '#0f766e')} oninput={event => setHostTint(event.currentTarget.value)} />
    </label><h1><a href={appPath('/')} onclick={(e) => { e.preventDefault(); choose(''); }}>aelab</a></h1></div>{#if host}<div class="host-launch"><span class="host-identity">{#if observation?.platform}<small class="host-platform label-chip">{observation.platform}</small>{/if}<button class="label-chip" title="Edit host" onclick={() => { launchMenu = false; form = { kind: 'hosts', existing: host }; }}>{observation?.hostname ?? (pending[selected] ? 'Checking hostname…' : 'Hostname unavailable')}</button></span><div class="launch-menu" bind:this={launchContainer}><button aria-label="Host launch menu" aria-expanded={launchMenu} onclick={() => launchMenu = !launchMenu}>+</button>{#if launchMenu}<div class="launch-options"><button onclick={() => { launchMenu = false; open({}); }}>Shell</button><button onclick={() => { launchMenu = false; open({ persistent: true }); }}>tmux</button>{#if tools.some(t => t.yoloArguments)}<hr /><small>YOLO tools</small>{#each tools.filter(t => t.yoloArguments) as tool}<button disabled={!tool.directory && !observation?.home} onclick={() => { launchMenu = false; openTool(tool, true); }}>{tool.name}</button>{/each}{/if}</div>{/if}</div></div>{/if}<div class="actions"><button onclick={toggleTheme} aria-label="Toggle theme">◐</button><button aria-label="Configuration" title="Configuration" onclick={() => editorOpen = true}><Icon name="settings" /></button><button aria-label="Sign out" title="Sign out" onclick={logout}><Icon name="logout" /></button></div></header>


    {#if error}<p class="error" role="alert">{error} <button onclick={() => error = ''}>×</button></p>{/if}
    {#if host && observation && !observation.reachable}<pre class="error" role="alert">{observation.connection.error || observation.connection.output || 'Host execution failed'}</pre>{/if}
    <HostPicker hosts={config?.hosts ?? []} {selected} expanded={sectionState[selected]?.shells ?? true} pins={pinnedShells[selected] ?? []} pinnedOnly={pinnedOnly[selected] ?? false} {observation} pending={pending[selected] ?? false} {choose} toggle={toggleShells} togglePinned={() => pinnedOnly[selected] = !pinnedOnly[selected]} add={() => { launchMenu = false; form = { kind: 'hosts' }; }} {open} {killPinned} {renameSession} {killSession} />
    {#if !selected}
      <Section title="HOSTS" expanded={sectionState[selected || 'overview']?.['hosts'] ?? true} onToggle={value => toggleSection('hosts', value)}>{#snippet actions()}<button onclick={() => { for (const h of config?.hosts ?? []) void refresh(h.id); }}>Check all</button>{/snippet}<ul use:sortable={{ group: 'hosts', move: (id, target) => { void reorderRows('hosts', id, target); } }}>{#each config?.hosts ?? [] as h (h.id)}<li class="managed-row" data-reorder-id={h.id}><div class="managed-content"><a class="row-title host-title" style:color={tintFor(h)} href={appPath(`/hosts/${h.id}/`)} onclick={(e) => { e.preventDefault(); choose(h.id); }}>{h.name}</a><small><span class="label-chip">{hostLocation(h)}</span></small></div><div class="actions managed-actions"><button aria-label="Edit" title="Edit" onclick={() => form = { kind: 'hosts', existing: h }}><Icon name="edit" /></button><button aria-label={`Delete host ${h.name}`} onclick={() => remove('hosts', h.id)} title="Delete"><Icon name="close" /></button></div><div class="managed-status"><StatusBadge state={hostState(h.id)} stale={stale(observations[h.id])} /></div><Reorder id={h.id} name={h.name} group={'hosts'} rows={config?.hosts ?? []} disabled={reordering} move={(id, target) => { void reorderRows('hosts', id, target); }} /></li>{/each}</ul>{#if !config?.hosts.length}<p>Add an approved SSH destination to begin.</p>{/if}</Section>
    {:else if host}
      <ProjectsSection {host} {tools} branches={observation?.projectBranches} expanded={sectionState[selected]?.projects ?? true} toggle={value => toggleSection('projects', value)} edit={existing => form = { kind: 'projects', existing }} remove={id => remove('projects', id)} move={(id, target) => reorderRows('projects', id, target)} {reordering} {open} bind:yolo={projectYolo} />
      <Section title="TOOLS" expanded={sectionState[selected]?.tools ?? true} onToggle={value => toggleSection('tools', value)}>{#snippet actions()}<button aria-label="Add tool" onclick={() => form = { kind: 'tools' }}>+</button><button aria-label="Discovery tools" title="All tools" aria-pressed={showingDiscovery('tools')} onclick={() => toggleDiscovery('tools')}><Icon name="filter" /></button>{#if showingDiscovery('tools')}<button aria-label="Refresh tools" title="Refresh" disabled={discovering[selected]} onclick={() => discoverTools(selected, true)}><Icon name="reload" /></button>{/if}{/snippet}
        <ul use:sortable={{ group: 'tools', move: (id, target) => { void reorderRows('tools', id, target); } }}>{#each showingDiscovery('tools') ? config?.tools ?? [] : tools as t (t.id)}<li class="managed-row" data-reorder-id={t.id}><div class="managed-content"><a class="row-title" href={appPath(`/hosts/${selected}/tools/${t.id}/`)} aria-disabled={!host.tools.includes(t.id) || toolState(t) !== 'installed'} onclick={event => { event.preventDefault(); if (host.tools.includes(t.id) && toolState(t) === 'installed') openTool(t); }} target="_blank" rel="noreferrer">{t.name}</a><small><span class="label-chip">{showingDiscovery('tools') ? toolDiscovery(t)?.path ?? t.executable : t.executable}</span></small>{#if toolDiscovery(t)?.error}<p class="error">{toolDiscovery(t)?.error}</p>{/if}</div><div class="actions managed-actions">
          {#if t.yoloArguments && host.tools.includes(t.id)}<button disabled={!t.directory && !observation?.home} onclick={() => openTool(t, true)}>YOLO</button>{/if}
          <button aria-label="Edit" title="Edit global tool" onclick={() => form = { kind: 'tools', existing: t }}><Icon name="edit" /></button>{#if host.transport === 'local' && !showingDiscovery('tools')}<button aria-label="Delete tool definition" title="Delete shared definition" onclick={() => remove('tools', t.id)}><Icon name="close" /></button>{:else}<button class="selection-toggle" aria-label={`${host.tools.includes(t.id) ? 'Disable' : 'Enable'} tool ${t.name}`} aria-pressed={host.tools.includes(t.id)} title={host.tools.includes(t.id) ? 'Disable on this host' : 'Enable on this host'} disabled={enablePending[`${selected}:tools:${t.id}`] || (!host.tools.includes(t.id) && toolState(t) !== 'installed')} onclick={() => toggleEnabled('tools', t.id)}><Icon name={host.tools.includes(t.id) && !showingDiscovery('tools') ? 'close' : 'validate'} /></button>{/if}</div><div class="managed-status"><StatusBadge state={toolState(t)} /></div><Reorder id={t.id} name={t.name} group={'tools'} rows={showingDiscovery('tools') ? config?.tools ?? [] : tools} disabled={reordering} move={(id, target) => { void reorderRows('tools', id, target); }} /></li>{/each}</ul>

      </Section>
      <Section title="SERVICES" expanded={sectionState[selected || 'overview']?.['services'] ?? true} onToggle={value => toggleSection('services', value)}>{#snippet actions()}<button aria-label="Add service" onclick={() => form = { kind: 'services' }}>+</button><button aria-label="Discovery services" title="Discovery" aria-pressed={showingDiscovery('services')} onclick={() => toggleDiscovery('services')}><Icon name="filter" /></button>{/snippet}{#if !showingDiscovery('services')}<ul use:sortable={{ group: `services:${selected}`, move: (id, target) => { void reorderRows('services', id, target); } }}>{#each host.services as s (s.id)}<li class="managed-row" data-reorder-id={s.id} class:highlight={parsed.service === s.id}><div class="managed-content"><a class="row-title" href={appPath(`/api/hosts/${selected}/services/${s.id}`)} onclick={event => { event.preventDefault(); void serviceAction(s, 'status'); }}>{s.name}</a><small><span class="label-chip">{s.provider} · {s.target}</span></small><div class="actions service-actions">{#each ['status', 'logs', 'start', 'stop', 'restart'] as op}<button disabled={busyAction === s.id || (s.provider === 'launchd' && op === 'stop' && !s.plist)} title={s.provider === 'launchd' && op === 'stop' && !s.plist ? 'Configure the plist path before stopping' : undefined} onclick={() => serviceAction(s, op)}>{op}</button>{/each}</div></div><div class="actions managed-actions"><button aria-label="Edit" title="Edit" onclick={() => form = { kind: 'services', existing: s }}><Icon name="edit" /></button><button aria-label="Delete" title="Delete" onclick={() => remove('services', s.id)}><Icon name="close" /></button></div><div class="managed-status"><StatusBadge state={nativeState(s)} stale={stale(observation)} /></div><Reorder id={s.id} name={s.name} group={`services:${selected}`} rows={host.services} disabled={reordering} move={(id, target) => { void reorderRows('services', id, target); }} /></li>{/each}</ul>
      {:else}<div class="discovery-filter"><input type="search" aria-label="Search services" placeholder="Search services…" bind:value={discoverySearch} /><label>Status<select aria-label="Discovery status" bind:value={discoveryStatus}><option value="running">Running</option><option value="all">All statuses</option>{#each discoveryStates as state}<option value={state}>{state}</option>{/each}</select></label>{#if showingDiscovery('services') && (sectionState[selected]?.services ?? true)}<button aria-label="Refresh services" title="Refresh" disabled={pending[selected]} onclick={() => refresh(selected)}><Icon name="reload" /></button>{/if}</div><small>{filteredDiscovery.length} of {observation?.discovered.length ?? 0} entries</small>{#each [['systemd', observation?.systemd], ['launchd', observation?.launchd], ['docker', observation?.docker]] as [provider, result]}{#if result && (result as Result).status}<details class="provider-notice"><summary>{provider === 'docker' ? '' : `${provider}: `}{serviceDiscoveryMessage(provider as string, result as Result)}</summary><pre>{(result as Result).error || (result as Result).output}</pre></details>{/if}{/each}<ul>{#each filteredDiscovery as item}<li class="row"><div><span class="row-title">{item.target}</span><small><span class="label-chip">{item.provider} · {item.state} {item.composeProject ? `· ${item.composeProject}` : ''}</span></small></div><button disabled={host.services.some(s => s.provider === item.provider && s.target === item.target)} aria-label={`Pin service ${item.target}`} title="Pin service" onclick={() => curate(item)}><Icon name="validate" /></button></li>{/each}</ul>{#if !filteredDiscovery.length}<p class="muted">No available services match these filters. Try All statuses or clear the search.</p>{/if}{/if}
      </Section>
        <Section title="PLUGINS" expanded={sectionState[selected]?.plugins ?? true} onToggle={value => toggleSection('plugins', value)}>{#snippet actions()}<button aria-label="Add plugin" title="Add plugin" onclick={() => form = { kind: 'plugins' }}>+</button><button aria-label="Discovery plugins" title="All plugins" aria-pressed={showingDiscovery('plugins')} onclick={() => toggleDiscovery('plugins')}><Icon name="filter" /></button>{/snippet}
          <ul use:sortable={{ group: 'plugins', move: (id, target) => { void reorderRows('plugins', id, target); } }}>{#each showingDiscovery('plugins') ? config?.plugins ?? [] : plugins as plugin (plugin.id)}{@const result = pluginResults[`${selected}:${plugin.id}`]}<li class="managed-row" data-reorder-id={plugin.id}><div class="managed-content"><div class="plugin-heading"><button class="row-title plugin-run" aria-label={`Probe ${plugin.name}`} disabled={probing[`${selected}:${plugin.id}`] || !host.plugins.includes(plugin.id) || pluginState(plugin.id) !== 'installed'} onclick={() => probePlugin(plugin)}>{plugin.name}</button>{#if host.transport !== 'local' && !['installed', 'checking'].includes(pluginState(plugin.id)) && localHosts.length && pluginHasSource(plugin)}<button aria-label={`Deploy script ${plugin.name}`} title="Deploy from local host" onclick={() => deployment = { host: selected, plugin: plugin.id }}><Icon name="upload" /></button>{/if}</div>
            {#if result?.report}<p>{result.report.summary}</p><dl class="plugin-details">{#each result.report.details as detail}<div><dt>{detail.label}</dt><dd>{detail.value}</dd></div>{/each}</dl>{/if}
            {#if result?.error}<p class="error" role="alert">{result.error}</p>{/if}{#if result}<small><span class="label-chip">Checked {new Date(result.checked).toLocaleString()} · exit {result.exitStatus}</span></small>{:else}<small><span class="label-chip">Run on demand</span></small>{/if}
          </div><div class="actions managed-actions plugin-actions"><button aria-label={`Edit script ${plugin.name}`} title="Edit script" disabled={!pluginAvailability[selected]?.find(row => row.plugin === plugin.id)?.source} onclick={() => pluginEditor = { host: selected, plugin: plugin.id }}><Icon name="code" /></button><button aria-label="Edit" title="Edit global plugin" onclick={() => form = { kind: 'plugins', existing: plugin }}><Icon name="edit" /></button>{#if host.transport === 'local' && !showingDiscovery('plugins')}<button aria-label="Delete plugin definition" title="Delete shared definition" onclick={() => remove('plugins', plugin.id)}><Icon name="close" /></button>{:else}<button class="selection-toggle" aria-label={`${host.plugins.includes(plugin.id) ? 'Disable' : 'Enable'} plugin ${plugin.name}`} aria-pressed={host.plugins.includes(plugin.id)} title={host.plugins.includes(plugin.id) ? 'Disable on this host' : 'Enable on this host'} disabled={enablePending[`${selected}:plugins:${plugin.id}`] || (!host.plugins.includes(plugin.id) && pluginState(plugin.id) !== 'installed')} onclick={() => toggleEnabled('plugins', plugin.id)}><Icon name={host.plugins.includes(plugin.id) && !showingDiscovery('plugins') ? 'close' : 'validate'} /></button>{/if}</div><div class="managed-status"><StatusBadge state={result?.error ? 'failed' : result?.report?.status ?? pluginState(plugin.id)} /></div><Reorder id={plugin.id} name={plugin.name} group={'plugins'} rows={showingDiscovery('plugins') ? config?.plugins ?? [] : plugins} disabled={reordering} move={(id, target) => { void reorderRows('plugins', id, target); }} /></li>{/each}</ul>{#if showingDiscovery('plugins')}<button aria-label="Refresh plugins" title="Refresh" onclick={() => discoverPlugins(selected)}><Icon name="reload" /></button>{/if}
        </Section>
    {:else}<p>Unknown configured host.</p>{/if}
    <footer class="muted"><a href={appPath('/')} onclick={(e) => { e.preventDefault(); choose(''); }}>aelab</a><span aria-hidden="true">·</span><span>one central instance</span><span aria-hidden="true">·</span><span>local / SSH / daemon execution</span><span aria-hidden="true">·</span><span>files are the source of truth</span><span aria-hidden="true">·</span><a href={appPath('/api/docs')} target="_blank" rel="noreferrer">API</a></footer>
  </main>
{/if}
{#if form && snapshot}{#key form}<ConfigForm platform={observation?.platform} {request} {snapshot} kind={form.kind} existing={form.existing} host={selected} initialTint={form.kind === 'hosts' ? tintFor(form.existing as Host | undefined) : undefined} {save} prepareProject={project => request(`/api/hosts/${selected}/projects`, 'POST', definitionPayload(project)).then(() => {})} close={() => form = undefined} />{/key}{/if}
{#if log}<div class="overlay" role="presentation"><div class="dialog logs" role="dialog" tabindex="-1" aria-modal="true" aria-label={log.title}><h2>{log.title}</h2><pre>{log.content || '(no output)'}</pre><button onclick={() => log = undefined}>Close</button></div></div>{/if}

{#if editorOpen && authenticated}<ConfigEditor {request} close={() => editorOpen = false} saved={async () => { await refreshConfig(); await loadSections(); if (selected && !config?.hosts.some(h => h.id === selected)) choose(''); else if (selected && !parsed.terminal) await refresh(selected); }} />{/if}

{#if pluginEditor}<PluginEditor host={pluginEditor.host} plugin={pluginEditor.plugin} source={pluginAvailability[pluginEditor.host]?.find(row => row.plugin === pluginEditor?.plugin)?.source} {request} close={() => pluginEditor = undefined} />{/if}

{#if directoryChoice}<DirectoryPicker host={directoryChoice.host} initial={observations[directoryChoice.host]?.home} {request} choose={path => { const choice = directoryChoice!; window.open(terminalURL({ host: choice.host, tool: choice.tool.id, yolo: choice.yolo, directory: path }), '_blank', 'noopener'); directoryChoice = undefined; }} close={() => directoryChoice = undefined} />{/if}
{#if deployment}<PluginDeployment host={deployment.host} plugin={deployment.plugin} {localHosts} {request} deployed={() => { if (deployment) void discoverPlugins(deployment.host); }} close={() => deployment = undefined} />{/if}
