<script lang="ts">
  import PinnedSessionCard from './PinnedSessionCard.svelte';
  import Icon from './Icon.svelte';
  import { terminalURL, pinnedLaunch, tmuxSessionMessage, type Tool, type Host, type PinnedSession, type Observation } from './model';
  let { hosts, tools, selected, expanded, pins, temporary, filter, observation, pending, choose, toggle, selectFilter, add, open, killPinned, renameSession, killSession }: {
    hosts: Host[]; tools: Tool[]; selected: string; expanded: boolean; pins: PinnedSession[]; temporary: PinnedSession[]; filter: 'all' | 'pinned' | 'tmux' | 'open'; observation?: Observation; pending: boolean; choose: (id: string) => void; toggle: () => void; selectFilter: (value: 'all' | 'pinned' | 'tmux' | 'open') => void; add: () => void; open: (launch: { pinned: string; project?: string; tool?: string }) => void; killPinned: (id: string) => void; renameSession: (name: string) => void; killSession: (name: string) => void;
  } = $props();
  const host = $derived(hosts.find(item => item.id === selected));
  const tmuxSessions = $derived(observation?.tmux?.status === 0 ? observation.tmux.output.trim().split('\n').filter(Boolean) : []);
  const nativePins = $derived(pins.filter(pin => !pin.session));
  const tmuxRows = $derived([...tmuxSessions, ...pins.filter(pin => pin.session && !tmuxSessions.some(line => line.split('|')[0] === pin.session)).map(pin => `${pin.session}|?|?`)]);
</script>
    <div class="picker-heading">Hosts</div>
    <div class="host-picker"><div class="host-picker-row" role="group" aria-label="Host picker" onpointerup={event => { if (!(event.target instanceof Element) || !event.target.closest('button, a')) toggle(); }}><nav class="hosts"><button class:active={!selected} onclick={() => choose('')}>all</button>{#each hosts as h}<button class:active={selected === h.id} onclick={() => { if (selected === h.id) toggle(); else choose(h.id); }}>{h.name}</button>{/each}<button title="Add host" aria-label="Add host" onclick={event => { event.stopPropagation(); add(); }}>+</button></nav>
    {#if host && !expanded && pins.length}<div class="host-pin-shortcuts" aria-label="Pinned shell shortcuts">{#each pins as pin}<a class="pin-number" href={terminalURL(pinnedLaunch(pin))} target="_blank" rel="noreferrer" aria-label={`Open pinned shell ${pin.number}`} title={`Open pinned shell ${pin.number}`}>{pin.number}</a>{/each}</div>{/if}
      {#if host}<button class="picker-toggle" aria-label={(expanded) ? 'Hide shells' : 'Show shells'} title={(expanded) ? 'Hide shells' : 'Show shells'} aria-expanded={expanded} aria-controls="host-shells" onclick={toggle}><Icon name="chevron" /></button>{/if}
    </div>

    {#if host && (expanded)}<div class="host-shells" id="host-shells" role="region" aria-label="SHELLS"><div class="picker-heading"><span>Shells</span><span class="badge shell-count" aria-label="Shell count" aria-live="polite">{filter === 'all' ? nativePins.length + tmuxRows.length + temporary.length : filter === 'pinned' ? pins.length : filter === 'open' ? temporary.length : tmuxRows.length}</span><div class="shell-segments" role="group" aria-label="Shell filter">{#each ['all', 'open', 'pinned', 'tmux'] as option}{@const value = option as 'all' | 'pinned' | 'tmux' | 'open'}<button aria-label={value} aria-pressed={filter === value} onclick={() => selectFilter(value)}>{value}</button>{/each}</div></div>
      <ul>{#if filter === 'all' || filter === 'pinned'}{#each nativePins as pin}<PinnedSessionCard {pin} {host} {tools} {killPinned} />{/each}{/if}{#if filter === 'all' || filter === 'open'}{#each temporary as pin}<PinnedSessionCard {pin} {host} {tools} {killPinned} temporary />{/each}{/if}{#each filter === 'open' ? [] : tmuxRows as line}{@const cells = line.split('|')}{@const pin = pins.find(pin => pin.session === cells[0])}{#if filter !== 'pinned' || pin}<li class="shell-row">
        <div class="shell-heading">{#if pin}<a class="pin-number" href={terminalURL(pinnedLaunch(pin))} target="_blank" rel="noreferrer" aria-label={`Open pinned shell ${pin.number}`}>{pin.number}</a>{/if}<a class="row-title" href={terminalURL({ host: selected, session: cells[0] })} target="_blank" rel="noreferrer">{cells[0]}</a></div>
        <div class="actions shell-actions"><button aria-label={`Rename tmux session ${cells[0]}`} title="Rename session" onclick={() => renameSession(cells[0])}><Icon name="edit" /></button><button aria-label={`Delete tmux session ${cells[0]}`} title="End session" onclick={() => killSession(cells[0])}><Icon name="close" /></button></div>
        <small><span class="label-chip">{cells[1]}</span> windows · <span class="label-chip">{cells[2]}</span> clients</small><div class="shell-badges"><span class="badge tmux-badge">tmux</span></div>
      </li>{/if}{/each}</ul>
      {#if pending && !observation}<div class="loading-state shell-loading" role="status"><span class="loader" aria-hidden="true"></span><span>Checking shells…</span></div>
      {:else if filter === 'pinned' && !pins.length}<small>No pinned shells.</small>
      {:else if filter === 'open' && !temporary.length}<small>No open shells.</small>
      {:else if filter !== 'open' && filter !== 'pinned' && !tmuxRows.length && (filter === 'tmux' || (!nativePins.length && !temporary.length)) && observation?.tmux}<small>{tmuxSessionMessage(observation.tmux)}</small>{/if}
    </div>{/if}</div>
