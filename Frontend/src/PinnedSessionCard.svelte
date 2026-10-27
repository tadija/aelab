<script lang="ts">
  import PathLabel from './PathLabel.svelte';
  import Icon from './Icon.svelte';
  import { appPath } from './basePath';
  import { programStatusLabel, programStatusTone } from './programStatus';
  import { terminalURL, terminalName, pinnedLaunch, type Tool, type Host, type PinnedSession } from './model';
  let { pin, host, tools, killPinned, temporary = false, showHost = false, hostColor, number = pin.number }: {
    pin: PinnedSession; host: Host; tools: Tool[]; killPinned: (id: string) => void; temporary?: boolean; showHost?: boolean; hostColor?: string; number?: number;
  } = $props();
  const url = $derived(terminalURL(pinnedLaunch(pin)));
</script>
<li class="shell-row pinned-row">
        <div class="shell-top"><div class="shell-heading">{#if !temporary}<button class="pin-number" style:--accent={showHost ? hostColor : undefined} aria-label={`Open pinned shell ${number}`} onclick={() => window.open(url, '_blank', 'noopener')}>{number}</button>{/if}<a class="row-title" title={terminalName(pin, host, tools, pin.cwd)} href={url} target="_blank" rel="noreferrer">{terminalName(pin, host, tools, pin.cwd)}</a>{#if pin.programStatus}<span class="badge pin-program-status" data-tone={programStatusTone(pin.programStatus)} title={[pin.programStatus.title, pin.programStatus.app, pin.programStatus.msg].filter(Boolean).join(' · ')}>{programStatusLabel(pin.programStatus)}</span>{/if}</div>
        <div class="actions shell-actions"><button aria-label={`Delete ${temporary ? 'open' : 'pinned'} terminal ${pin.id}`} title={temporary ? 'End open terminal' : 'End pinned terminal'} onclick={() => killPinned(pin.id)}><Icon name="close" /></button></div></div>
        <small>{#if pin.session}<span class="label-chip">tmux session</span>{:else}<PathLabel path={pin.cwd || 'working directory unavailable'} />{/if}</small>
        <div class="shell-badges">{#if showHost}<a class="badge host-badge" style:--host-color={hostColor ?? 'var(--accent)'} href={appPath(`/hosts/${encodeURIComponent(host.id)}/`)}>{host.name}</a>{:else}{#if pin.session}<span class="badge tmux-badge">tmux</span>{:else}<span class="badge" class:open-badge={temporary} class:pinned-badge={!temporary}>{temporary ? 'open' : 'pinned'}</span>{/if}{/if}</div>
      </li>
