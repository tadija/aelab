<script lang="ts">
  import { ProgramStatusStore, programStatusReply, programStatusLabel, type ProgramRecord } from './programStatus';
  import { terminalEvents } from './terminalEvents';
  import { appPath } from './basePath';
  import { keySequence } from './terminalKeys';
  import Icon from './Icon.svelte';
  import Logo from './Logo.svelte';
  import { uploadTerminalFile, quotedFilePath, clipboardImageName, maximumFileSize, maximumFileBatch } from './terminalFiles';
  import { onMount, untrack } from 'svelte';
  import { Terminal } from '@xterm/xterm';
  import { FitAddon } from '@xterm/addon-fit';
  import '@xterm/xterm/css/xterm.css';
  import { shouldCopy, terminalURL, terminalTabTitle, prefixBytes, type Launch, type Host, type Tool, type TTYButton } from './model';
  let { launch, host, logoColor, screensaver, tools, buttons, csrf, request }: { launch: Launch; host: Host; logoColor: string; screensaver: () => void; tools: Tool[]; buttons: TTYButton[]; csrf: string; request: <T>(path: string, method?: string, body?: unknown) => Promise<T> } = $props();
  let container: HTMLDivElement; let pageElement: HTMLDivElement;
  let headerCollapsed = $state(localStorage.getItem('aelab-tty-header-collapsed') === '1');
  let keysVisible = $state(false); let pinned = $state(false); let terminalID = $state('');
  let hostname = $state('…'); let platform = $state('');
  const initial = untrack(() => ({ host, launch, tools }));
  const projectDirectory = initial.host.projects.find(project => project.id === initial.launch.project)?.dir;
  const toolDirectory = initial.tools.find(tool => tool.id === initial.launch.tool)?.directory;
  const session = initial.launch.session ?? (initial.launch.persistent !== false && !initial.launch.tool ? initial.host.projects.find(project => project.id === initial.launch.project)?.session : undefined);
  const cwdCacheKey = initial.launch.pinned || session
    ? `aelab-tty-last-cwd:${JSON.stringify([initial.host.id, initial.launch.pinned ?? '', session ?? '', initial.launch.window ?? ''])}` : undefined;
  const initialCwd = (cwdCacheKey && localStorage.getItem(cwdCacheKey)) || initial.launch.directory || projectDirectory || toolDirectory || '';
  let cwd = $state(initialCwd); let activeLaunch = $state<Launch>(initial.launch);
  function toggleHeader() { headerCollapsed = !headerCollapsed; localStorage.setItem('aelab-tty-header-collapsed', headerCollapsed ? '1' : '0'); }
  function togglePin() { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: pinned ? 'unpin' : 'pin' })); }
  const title = $derived(terminalTabTitle(activeLaunch, host, tools, cwd));
  const programStatuses = new ProgramStatusStore();
  let programRecords = $state<ProgramRecord[]>([]);
  const program = $derived(programRecords[0]);
  let notifyProgramChange = () => {};
  function updateProgramStatus() { programRecords = programStatuses.snapshot(); notifyProgramChange(); }
  $effect(() => { document.title = `${program ? `[${programStatusLabel(program)}] ` : ''}${title}`; });
  let status = $state('connecting'); let error = $state('');
  let resolvedSession = $state<string>();
  let tmuxPrefix = $state('\x02');
  const hostBackground = initial.host.background ?? '#0b0f0d';
  const pathKey = $derived(`aelab-tty-cwd-background:${initial.host.id}:${cwd}`);
  let background = $state((initialCwd && localStorage.getItem(`aelab-tty-cwd-background:${initial.host.id}:${initialCwd}`)) || hostBackground);
  $effect(() => {
    if (!cwd) return;
    if (cwdCacheKey) localStorage.setItem(cwdCacheKey, cwd);
    if (pinned && terminalID && !resolvedSession && !activeLaunch.session) {
      localStorage.setItem(`aelab-tty-last-cwd:${JSON.stringify([initial.host.id, terminalID, '', initial.launch.window ?? ''])}`, cwd);
    }
    const liveSession = resolvedSession || activeLaunch.session;
    if (liveSession) localStorage.setItem(`aelab-tty-last-cwd:${JSON.stringify([initial.host.id, '', liveSession, initial.launch.window ?? ''])}`, cwd);
  });
  $effect(() => { background = (cwd && localStorage.getItem(pathKey)) || hostBackground; if (term) term.options.theme = { ...term.options.theme, background }; });
  let alt = $state(false); let shift = $state(false);
  let replayNext = false; let replaying = false;
  let term: Terminal; let fit: FitAddon; let socket: WebSocket;
  function send(data: string) { if (replaying) return; if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data })); term.focus(); }
  function tint(value: string) { if (!cwd) return; localStorage.setItem(pathKey, value); background = value; if (term) term.options.theme = { ...term.options.theme, background }; }
  function resetBackground() { localStorage.removeItem(pathKey); background = hostBackground; if (term) term.options.theme = { ...term.options.theme, background }; }
  function redraw() {
    if (socket?.readyState !== WebSocket.OPEN) return;
    socket.send(JSON.stringify({ type: 'resize', cols: Math.max(2, term.cols - 1), rows: term.rows }));
    setTimeout(() => { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows })); }, 80);
  }
  function keyAction(key: string) {
    if (key === 'alt') { alt = !alt; return; }
    if (key === 'shift') { shift = !shift; return; }
    if (key === 'reload-tty') { redraw(); return; }
    if (key === 'copy') { void copy(); return; }
    if (key === 'paste') { void paste(); return; }
    if (key === 'reconnect') { location.reload(); return; }
    if (key === 'scroll-up' || key === 'scroll-down') { term.scrollLines(Math.round(term.rows / 2) * (key === 'scroll-up' ? -1 : 1)); return; }
    const sequence = keySequence(key, shift, tmuxPrefix);
    if (sequence) { send((alt ? '\x1b' : '') + sequence); shift = false; }
  }
  async function copy() {
    const text = term?.getSelection(); if (!text) return;
    try { await navigator.clipboard.writeText(text); }
    catch {
      const input = document.createElement('textarea'); input.value = text; document.body.appendChild(input); input.select();
      const copied = document.execCommand('copy'); input.remove(); if (!copied) error = 'Copy failed; use the browser copy menu.';
    }
  }
  let dragDepth = $state(0); let uploadLabel = $state(''); let uploadPercent = $state(0);
  let uploadController: AbortController | undefined;
  let pastingFiles = false; let terminalMounted = false;
  async function uploadFiles(files: File[]) {
    if (!terminalMounted || !files.length) return;
    if (uploadController) { error = 'Wait for the current file transfer to finish'; return; }
    if (status !== 'connected' || !terminalID || socket?.readyState !== WebSocket.OPEN) { error = 'Connect the terminal before uploading files'; return; }
    if (files.length > maximumFileBatch) { error = 'Drop up to 10 files at a time'; return; }
    const oversized = files.find(file => file.size > maximumFileSize);
    if (oversized) { error = `${oversized.name}: files must be at most 20 MiB`; return; }
    const controller = new AbortController(), id = terminalID;
    uploadController = controller; error = '';
    try {
      for (const file of files) {
        uploadLabel = file.name; uploadPercent = 0;
        const result = await uploadTerminalFile(host.id, id, file, csrf, controller.signal, percent => uploadPercent = percent);
        if (!terminalMounted || controller.signal.aborted || id !== terminalID || socket?.readyState !== WebSocket.OPEN) return;
        pastingFiles = true;
        try { term.paste(quotedFilePath(result.path)); term.paste(' '); } finally { pastingFiles = false; }
        term.focus();
      }
    } catch (e) { if (!(e instanceof DOMException && e.name === 'AbortError')) error = String(e); }
    finally { uploadController = undefined; uploadLabel = ''; }
  }
  async function paste() {
    try {
      if (navigator.clipboard.read) {
        try {
          const items = await navigator.clipboard.read(), files: File[] = [];
          for (const item of items) {
            const type = item.types.includes('image/png') ? 'image/png' : item.types.find(type => type.startsWith('image/'));
            if (type) files.push(new File([await item.getType(type)], clipboardImageName(type), { type }));
          }
          if (files.length) { await uploadFiles(files); return; }
        } catch { /* Text paste remains available when image clipboard access is unsupported. */ }
      }
      const text = await navigator.clipboard.readText(); if (terminalMounted) term.paste(text);
    } catch { error = 'Clipboard permission denied; use Ctrl+Shift+V or the browser paste menu.'; }
  }
  onMount(() => {
    terminalMounted = true;
    let disposed = false;
    const hasFiles = (event: DragEvent) => Array.from(event.dataTransfer?.types ?? []).includes('Files');
    const dragEnter = (event: DragEvent) => { if (hasFiles(event)) { event.preventDefault(); dragDepth++; } };
    const dragOver = (event: DragEvent) => { if (hasFiles(event)) { event.preventDefault(); if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy'; } };
    const dragLeave = (event: DragEvent) => { if (hasFiles(event)) { event.preventDefault(); dragDepth = Math.max(0, dragDepth - 1); } };
    const drop = (event: DragEvent) => { if (hasFiles(event)) {
      event.preventDefault(); event.stopPropagation(); dragDepth = 0;
      if (Array.from(event.dataTransfer?.items ?? []).some(item => item.webkitGetAsEntry?.()?.isDirectory)) { error = 'Drop files rather than folders'; return; }
      void uploadFiles(Array.from(event.dataTransfer?.files ?? []));
    } };
    const pasteFiles = (event: ClipboardEvent) => {
      const files = Array.from(event.clipboardData?.files ?? []);
      if (files.length) { event.preventDefault(); event.stopPropagation(); void uploadFiles(files); }
    };
    pageElement.addEventListener('dragenter', dragEnter); pageElement.addEventListener('dragover', dragOver);
    pageElement.addEventListener('dragleave', dragLeave); pageElement.addEventListener('drop', drop);
    container.addEventListener('paste', pasteFiles, true);
    const events = terminalEvents();
    let statusTimer: ReturnType<typeof setTimeout> | undefined;
    notifyProgramChange = () => {
      if (pinned && statusTimer === undefined) statusTimer = setTimeout(() => { statusTimer = undefined; events.changed(host.id); }, 150);
    };
    term = new Terminal({ cursorBlink: true, macOptionClickForcesSelection: true, altClickMovesCursor: false, fontSize: 14, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", monospace', scrollback: 10000, theme: { background, foreground: '#d8e6df', cursor: '#34d399', selectionBackground: '#245747' }, allowProposedApi: false });
    fit = new FitAddon(); term.loadAddon(fit); term.open(container); fit.fit();
    term.attachCustomKeyEventHandler(event => {
      if (shouldCopy(event.key, event.ctrlKey, event.metaKey, event.shiftKey, term.hasSelection())) { if (event.type === 'keydown') void copy(); return false; }
      // Native paste remains available; Ctrl+C without a selection reaches the shell.
      return true;
    });
    const cwdHandler = term.parser.registerOscHandler(7, value => {
      try { const url = new URL(value); if (url.protocol === 'file:') cwd = decodeURIComponent(url.pathname); } catch { /* Ignore malformed host cwd metadata. */ }
      return true;
    });
    const programHandler = term.parser.registerOscHandler(7501, value => {
      if (value.trim() === '?') {
        // Replies are terminal input, without sticky modifiers or focus changes.
        if (!replaying && socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'input', data: programStatusReply }));
      } else if (programStatuses.report(value)) updateProgramStatus();
      return true;
    });
    const promptHandler = term.parser.registerOscHandler(133, value => {
      if (value.split(';')[0] === 'A') { programStatuses.commandFinished(); updateProgramStatus(); }
      return false;
    });
    const resetHandler = term.parser.registerEscHandler({ final: 'c' }, () => { programStatuses.reset(); updateProgramStatus(); return false; });
    const key = term.onKey(() => { if (!replaying) { if (programRecords.some(record => record.state === 'done' || record.state === 'error') && socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'ack-program-status' })); programStatuses.acknowledge(); updateProgramStatus(); } });
    const input = term.onData(data => { send(pastingFiles ? data : (alt ? '\x1b' : '') + (shift && data.length === 1 ? data.toUpperCase() : data)); if (!replaying) shift = false; });
    const binaryInput = term.onBinary(data => { if (socket?.readyState === WebSocket.OPEN) socket.send(Uint8Array.from(data, char => char.charCodeAt(0))); });
    const resize = () => { fit.fit(); if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows })); };
    const observer = new ResizeObserver(resize); observer.observe(container);
    void (async () => {
      try {
        const { host: hostID, ...body } = launch;
        const { ticket, session, prefix } = await request<{ ticket: string; session?: string; prefix: string }>(`/api/hosts/${encodeURIComponent(hostID)}/terminal-tickets`, 'POST', body);
        resolvedSession = session || undefined;
        tmuxPrefix = prefixBytes(prefix);
        if (session) history.replaceState({}, '', terminalURL({ ...launch, session, persistent: false }));
        if (disposed) return;
        socket = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}${appPath(`/ws/terminals/${ticket}`)}`); socket.binaryType = 'arraybuffer';
        socket.onopen = () => { status = 'connected'; resize(); term.focus(); };
        socket.onmessage = event => {
          if (typeof event.data !== 'string') {
            const replay = replayNext; replayNext = false;
            if (replay) replaying = true;
            term.write(new Uint8Array(event.data), replay ? () => { replaying = false; } : undefined); return;
          }
          try { const metadata = JSON.parse(event.data);
            if (metadata.type === 'replay') { replayNext = true; return; }
            if (metadata.type === 'terminal') {
              if (metadata.identity) { hostname = metadata.identity.hostname; platform = metadata.identity.platform; }
              const pinTool = !terminalID && launch.tool && !launch.pinned && !resolvedSession && !metadata.pinned;
              const pinChanged = pinned !== metadata.pinned || (metadata.pinned && terminalID !== metadata.id);
              terminalID = metadata.id; pinned = metadata.pinned; cwd = metadata.cwd; activeLaunch = metadata.launch;
              if (pinTool) socket?.send(JSON.stringify({ type: 'pin' }));
              if (pinChanged) events.changed(host.id);
              history.replaceState({}, '', terminalURL({ ...activeLaunch, pinned: pinned && !resolvedSession ? terminalID : undefined, persistent: false }));
              return;
            }
            if (metadata.type === 'tmux-prefix') { tmuxPrefix = prefixBytes(metadata.prefix); return; } } catch { /* Plain-text transport error. */ }
          error = event.data;
        };
        socket.onerror = () => { error = 'Terminal connection failed'; };
        socket.onclose = () => { if (disposed) return; events.changed(host.id); status = 'disconnected'; term.write('', () => { programStatuses.commandFinished(); updateProgramStatus(); }); };
      } catch (e) { status = 'disconnected'; error = String(e); }
    })();
    return () => { disposed = true; terminalMounted = false; uploadController?.abort();
      pageElement.removeEventListener('dragenter', dragEnter); pageElement.removeEventListener('dragover', dragOver);
      pageElement.removeEventListener('dragleave', dragLeave); pageElement.removeEventListener('drop', drop);
      container.removeEventListener('paste', pasteFiles, true); clearTimeout(statusTimer); notifyProgramChange = () => {}; events.close(); observer.disconnect(); input.dispose(); binaryInput.dispose(); cwdHandler.dispose(); programHandler.dispose(); promptHandler.dispose(); resetHandler.dispose(); key.dispose(); socket?.close(); term.dispose(); };
  });
</script>
<div bind:this={pageElement} class="terminal-page" class:header-collapsed={headerCollapsed} style:background style:--terminal-background={background}>
  <header class="terminal-header">
    <div class="terminal-header-left"><div class="terminal-brand"><button class="tint-trigger" title="Screensaver" aria-label="Screensaver" onclick={screensaver}><Logo class="terminal-logo" color={logoColor} /></button><a href={appPath(`/hosts/${host.id}/`)} title="Open host root">aelab</a></div>
      <button class="terminal-circle header-toggle" aria-expanded={!headerCollapsed} aria-label={headerCollapsed ? 'Expand header' : 'Collapse header'} title={headerCollapsed ? 'Expand header' : 'Collapse header'} onclick={toggleHeader}><Icon name="chevron" /></button>
      <div class="terminal-meta"><span><button class="host-background-reset" title="Reset to host terminal background" aria-label="Reset terminal background" onclick={resetBackground}>host</button>{#if platform}<small class="terminal-platform label-chip">{platform}</small>{/if}<code class="label-chip">{hostname}</code></span><span class="terminal-cwd"><label title="Change cwd terminal background">cwd<input type="color" aria-label="background" value={background} disabled={!cwd} oninput={event => tint(event.currentTarget.value)} /></label><code class="label-chip" title={cwd}>{cwd || '…'}</code></span></div>
    </div>
    <div class="terminal-header-actions"><span class="terminal-status" data-status={status}><span class="status-dot" aria-hidden="true"></span><span>{status}</span></span>
      <button class="terminal-circle pin-toggle" aria-pressed={pinned} aria-label={pinned ? 'Unpin terminal session' : 'Pin terminal session'} title={pinned ? 'Unpin terminal session' : 'Pin terminal session'} disabled={status !== 'connected' || !terminalID} onclick={togglePin}><Icon name="validate" /></button>
      <button class="terminal-circle keys-toggle" aria-controls="terminal-keybar" aria-expanded={keysVisible} aria-label={keysVisible ? 'Hide key bar' : 'Show key bar'} title={keysVisible ? 'Hide key bar' : 'Show key bar'} onclick={() => keysVisible = !keysVisible}><Icon name="chevron" /></button>
    </div>
  </header>
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="terminal-workspace">
  {#if dragDepth > 0}<div class="file-drop-overlay" aria-hidden="true">Drop files to upload</div>{/if}
  {#if uploadLabel}<div class="file-upload-progress" role="status"><span>{uploadPercent === 100 ? 'Saving' : 'Uploading'} {uploadLabel}{uploadPercent < 100 ? ` · ${uploadPercent}%` : '…'}</span><button type="button" title="Cancel upload" aria-label="Cancel upload" onclick={() => uploadController?.abort()}><Icon name="close" /></button></div>{/if}
  {#if keysVisible}<div class="terminal-keys" id="terminal-keybar" role="toolbar" aria-label="terminal key bar">
    {#each buttons as button}<button title={button.label} aria-label={button.label} aria-pressed={button.key === 'alt' ? alt : button.key === 'shift' ? shift : undefined} onpointerdown={event => event.preventDefault()} onclick={() => keyAction(button.key)}>{button.label}</button>{/each}
  </div>{/if}
  <div class="terminal-container" bind:this={container}></div>
  </div>

</div>

<style>
  .terminal-workspace { position: relative; }
  .file-drop-overlay { position: absolute; inset: 8px; z-index: 5; display: grid; place-items: center; border: 2px dashed var(--accent); border-radius: 12px; color: var(--accent); background: color-mix(in srgb, var(--terminal-background) 90%, transparent); pointer-events: none; }
  .file-upload-progress { position: absolute; bottom: 12px; right: 12px; left: 12px; z-index: 4; display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 8px 12px; border: 1px solid var(--border); border-radius: 8px; background: var(--panel); font-size: .85rem; }
  .file-upload-progress span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file-upload-progress button { display: inline-flex; padding: 3px; }
</style>
