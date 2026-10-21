<script lang="ts">
  import Icon from './Icon.svelte';
  import { terminalURL, tmuxSessionMessage, type Host, type PinnedSession, type Observation } from './model';
  let { hosts, selected, expanded, pins, pinnedOnly, observation, pending, choose, toggle, togglePinned, add, open, killPinned, renameSession, killSession }: {
    hosts: Host[]; selected: string; expanded: boolean; pins: PinnedSession[]; pinnedOnly: boolean; observation?: Observation; pending: boolean; choose: (id: string) => void; toggle: () => void; togglePinned: () => void; add: () => void; open: (launch: { pinned: string; project?: string; tool?: string }) => void; killPinned: (id: string) => void; renameSession: (name: string) => void; killSession: (name: string) => void;
  } = $props();
  const host = $derived(hosts.find(item => item.id === selected));
</script>
    <div class="picker-heading">Hosts</div>
    <div class="host-picker"><div class="host-picker-row" role="group" aria-label="Host picker" onpointerup={event => { if (!(event.target instanceof Element) || !event.target.closest('button')) toggle(); }}><nav class="hosts"><button class:active={!selected} onclick={() => choose('')}>all</button>{#each hosts as h}<button class:active={selected === h.id} onclick={() => { if (selected === h.id) toggle(); else choose(h.id); }}>{h.name}</button>{/each}<button title="Add host" aria-label="Add host" onclick={event => { event.stopPropagation(); add(); }}>+</button></nav>
      {#if host}<button class="picker-toggle" aria-label={(expanded) ? 'Hide shells' : 'Show shells'} title={(expanded) ? 'Hide shells' : 'Show shells'} aria-expanded={expanded} aria-controls="host-shells" onclick={toggle}><Icon name="chevron" /></button>{/if}
    </div>
    {#if host && (expanded)}<div class="host-shells" id="host-shells" role="region" aria-label="SHELLS"><div class="picker-heading"><span>Shells</span><button class="shell-filter" aria-label="Pinned shells only" title={pinnedOnly ? 'Show all shells' : 'Show pinned shells only'} aria-pressed={pinnedOnly} onclick={() => togglePinned()}><Icon name="filter" /></button></div>
      <ul>{#each pins as pin}<li class="shell-row pinned-row">
        <div class="shell-heading"><a class="row-title" href={terminalURL({ host: selected, pinned: pin.id, project: pin.project, tool: pin.tool })} target="_blank" rel="noreferrer">{pin.project ?? pin.tool ?? 'shell'}</a><button class="pin-number" aria-label={`Open pinned shell ${pin.number}`} onclick={() => open({ pinned: pin.id, project: pin.project, tool: pin.tool })}>{pin.number}</button></div>
        <div class="actions shell-actions"><button aria-label={`Delete pinned terminal ${pin.id}`} title="End pinned terminal" onclick={() => killPinned(pin.id)}><Icon name="close" /></button></div>
        <small><span class="label-chip">{pin.cwd || 'working directory unavailable'}</span></small>
        <div class="shell-badges"><span class="badge pinned-badge">pinned</span></div>
      </li>{/each}{#if !pinnedOnly}{#each observation?.tmux?.status === 0 ? observation.tmux.output.trim().split('\n').filter(Boolean) : [] as line}{@const cells = line.split('|')}<li class="shell-row">
        <a class="row-title" href={terminalURL({ host: selected, session: cells[0] })} target="_blank" rel="noreferrer">{cells[0]}</a>
        <div class="actions shell-actions"><button aria-label={`Rename tmux session ${cells[0]}`} title="Rename session" onclick={() => renameSession(cells[0])}><Icon name="edit" /></button><button aria-label={`Delete tmux session ${cells[0]}`} title="End session" onclick={() => killSession(cells[0])}><Icon name="close" /></button></div>
        <small><span class="label-chip">{cells[1]}</span> windows · <span class="label-chip">{cells[2]}</span> clients</small><div class="shell-badges"><span class="badge tmux-badge">tmux</span></div>
      </li>{/each}{/if}</ul>
      {#if pending && !observation}<div class="loading-state shell-loading" role="status"><span class="loader" aria-hidden="true"></span><span>Checking shells…</span></div>
      {:else if pinnedOnly && !pins.length}<small>No pinned shells.</small>
      {:else if !pinnedOnly && observation?.tmux && (observation.tmux.status !== 0 || !observation.tmux.output.trim()) && !pins.length}<small>{tmuxSessionMessage(observation.tmux)}</small>{/if}
    </div>{/if}</div>
