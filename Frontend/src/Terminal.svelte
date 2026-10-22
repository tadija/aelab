<script lang="ts">
  import { ProgramStatusStore, programStatusReply, programStatusLabel, programStatusTone, type ProgramRecord } from './programStatus';
  import { appPath } from './basePath';
  import { keySequence } from './terminalKeys';
  import Icon from './Icon.svelte';
  import { onMount, untrack } from 'svelte';
  import { Terminal } from '@xterm/xterm';
  import { FitAddon } from '@xterm/addon-fit';
  import '@xterm/xterm/css/xterm.css';
  import { shouldCopy, terminalURL, prefixBytes, type Launch, type Host, type Tool, type TTYButton } from './model';
  let { launch, host, tools, buttons, csrf, request }: { launch: Launch; host: Host; tools: Tool[]; buttons: TTYButton[]; csrf: string; request: <T>(path: string, method?: string, body?: unknown) => Promise<T> } = $props();
  let container: HTMLDivElement;
  let headerCollapsed = $state(localStorage.getItem('aelab-tty-header-collapsed') === '1');
  let keysVisible = $state(false); let pinned = $state(false); let terminalID = $state('');
  let hostname = $state('…'); let platform = $state('');
  let cwd = $state(''); let activeLaunch = $state<Launch>(untrack(() => launch));
  function toggleHeader() { headerCollapsed = !headerCollapsed; localStorage.setItem('aelab-tty-header-collapsed', headerCollapsed ? '1' : '0'); }
  function togglePin() { if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: pinned ? 'unpin' : 'pin' })); }
  const title = $derived(tools.find(tool => tool.id === activeLaunch.tool)?.name ?? host.projects.find(project => project.id === activeLaunch.project)?.name ?? activeLaunch.session ?? 'shell');
  const programStatuses = new ProgramStatusStore();
  let programRecords = $state<ProgramRecord[]>([]);
  const program = $derived(programRecords[0]);
  function updateProgramStatus() { programRecords = programStatuses.snapshot(); }
  $effect(() => { document.title = `${program ? `[${programStatusLabel(program)}] ` : ''}${title}@aelab`; });
  let status = $state('connecting'); let error = $state('');
  let resolvedSession = $state<string>();
  let tmuxPrefix = $state('\x02');
  const initial = untrack(() => ({ host, launch }));
  const hostBackground = initial.host.background ?? '#0b0f0d';
  const pathKey = $derived(`aelab-tty-cwd-background:${initial.host.id}:${cwd}`);
  let background = $state(hostBackground);
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
  async function paste() { try { term.paste(await navigator.clipboard.readText()); } catch { error = 'Clipboard permission denied; use Ctrl+Shift+V or the browser paste menu.'; } }
  onMount(() => {
    let disposed = false;
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
    const key = term.onKey(() => { if (!replaying) { programStatuses.acknowledge(); updateProgramStatus(); } });
    const input = term.onData(data => { send((alt ? '\x1b' : '') + (shift && data.length === 1 ? data.toUpperCase() : data)); if (!replaying) shift = false; });
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
              terminalID = metadata.id; pinned = metadata.pinned; cwd = metadata.cwd; activeLaunch = metadata.launch;
              history.replaceState({}, '', terminalURL({ ...activeLaunch, pinned: pinned ? terminalID : undefined, persistent: false }));
              return;
            }
            if (metadata.type === 'tmux-prefix') { tmuxPrefix = prefixBytes(metadata.prefix); return; } } catch { /* Plain-text transport error. */ }
          error = event.data;
        };
        socket.onerror = () => { error = 'Terminal connection failed'; };
        socket.onclose = () => { if (disposed) return; status = 'disconnected'; term.write('', () => { programStatuses.commandFinished(); updateProgramStatus(); }); };
      } catch (e) { status = 'disconnected'; error = String(e); }
    })();
    return () => { disposed = true; observer.disconnect(); input.dispose(); binaryInput.dispose(); cwdHandler.dispose(); programHandler.dispose(); promptHandler.dispose(); resetHandler.dispose(); key.dispose(); socket?.close(); term.dispose(); };
  });
</script>
<div class="terminal-page" class:header-collapsed={headerCollapsed} style:background style:--terminal-background={background}>
  <header class="terminal-header">
    <div class="terminal-header-left"><a class="terminal-brand" href={appPath(`/hosts/${host.id}/`)} title="Open host root">aelab</a>
      <button class="terminal-circle header-toggle" aria-expanded={!headerCollapsed} aria-label={headerCollapsed ? 'Expand header' : 'Collapse header'} title={headerCollapsed ? 'Expand header' : 'Collapse header'} onclick={toggleHeader}><Icon name="chevron" /></button>
      <div class="terminal-meta"><span><button class="host-background-reset" title="Reset to host terminal background" aria-label="Reset terminal background" onclick={resetBackground}>host</button>{#if platform}<small class="terminal-platform label-chip">{platform}</small>{/if}<code class="label-chip">{hostname}</code></span><span class="terminal-color" style:background title={background} aria-label={`Terminal background ${background}`}></span><span class="terminal-cwd"><label title="Change cwd terminal background">cwd<input type="color" aria-label="background" value={background} disabled={!cwd} oninput={event => tint(event.currentTarget.value)} /></label><code class="label-chip" title={cwd}>{cwd || '…'}</code></span></div>
    </div>
    <div class="terminal-header-actions"><span class="terminal-status" data-status={status}><span class="status-dot" aria-hidden="true"></span><span>{status}</span></span>
      {#if !resolvedSession}<button class="terminal-circle pin-toggle" aria-pressed={pinned} aria-label={pinned ? 'Unpin terminal session' : 'Pin terminal session'} title={pinned ? 'Unpin terminal session' : 'Pin terminal session'} disabled={status !== 'connected' || !terminalID} onclick={togglePin}><Icon name="validate" /></button>{/if}
      <button class="terminal-circle keys-toggle" aria-controls="terminal-keybar" aria-expanded={keysVisible} aria-label={keysVisible ? 'Hide key bar' : 'Show key bar'} title={keysVisible ? 'Hide key bar' : 'Show key bar'} onclick={() => keysVisible = !keysVisible}><Icon name="chevron" /></button>
    </div>
  </header>
  {#if error}<p class="error" role="alert">{error}</p>{/if}
  <div class="terminal-workspace">
  {#if program}<details class="program-status" aria-label="Program status">
    <summary><span class="badge" data-tone={programStatusTone(program)}>{programStatusLabel(program)}</span><span class="program-message">{program.title || program.app || title}{#if program.msg} · {program.msg}{/if}</span>{#if programRecords.length > 1}<small>{programRecords.length} reports</small>{/if}</summary>
    <ul>{#each programRecords as record (record.id)}<li><span class="badge" data-tone={programStatusTone(record)}>{programStatusLabel(record)}</span><span>{record.title || record.app || title}{#if record.id} · {record.id}{/if}{#if record.msg} · {record.msg}{/if}</span></li>{/each}</ul>
  </details>{/if}
  {#if keysVisible}<div class="terminal-keys" id="terminal-keybar" role="toolbar" aria-label="terminal key bar">
    {#each buttons as button}<button title={button.label} aria-label={button.label} aria-pressed={button.key === 'alt' ? alt : button.key === 'shift' ? shift : undefined} onpointerdown={event => event.preventDefault()} onclick={() => keyAction(button.key)}>{button.label}</button>{/each}
  </div>{/if}
  <div class="terminal-container" bind:this={container}></div>
  </div>
</div>
