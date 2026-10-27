<script lang="ts">
  import { escapeDismiss } from './escapeDismiss';
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import DirectoryNode from './DirectoryNode.svelte';
  import type { DirectoryListing } from './model';
  let { host, initial = '', request, choose, close }: { host: string; initial?: string; request: <T>(path: string) => Promise<T>; choose: (path: string) => void; close: () => void } = $props();
  const hiddenPreference = 'aelab-directory-show-hidden';
  let showHidden = $state(localStorage.getItem(hiddenPreference) === '1');
  function toggleHidden() { showHidden = !showHidden; localStorage.setItem(hiddenPreference, showHidden ? '1' : '0'); }
  let listing = $state<DirectoryListing>(); let selected = $state(''); let busy = $state(false); let error = $state(''); let generation = 0;
  const directories = $derived((listing?.directories ?? []).filter(directory => showHidden || !directory.name.startsWith('.')));
  async function load(path = '~') {
    const current = ++generation; busy = true; error = '';
    try {
      const result = await request<DirectoryListing>(`/api/hosts/${encodeURIComponent(host)}/directories?path=${encodeURIComponent(path)}`);
      if (generation === current) { listing = result; selected = result.path; }
    } catch (e) { if (generation === current) error = String(e); } finally { if (generation === current) busy = false; }
  }
  onMount(() => { void load(initial || '~'); return () => { generation++; }; });
</script>
<div class="overlay directory-overlay" role="presentation">
  <div class="dialog directory-picker" use:escapeDismiss={close} role="dialog" tabindex="-1" aria-modal="true" aria-label="Select host directory">
    <h2>SELECT DIRECTORY</h2><small>{host}</small>
    <div class="actions directory-toolbar"><button type="button" aria-label="Root directory" title="Root directory" onclick={() => load('/')}>/</button><button type="button" onclick={() => load('~')}>Home</button><button type="button" class="directory-hidden-toggle" aria-label="Show hidden folders" title={showHidden ? 'Hide hidden folders' : 'Show hidden folders'} aria-pressed={showHidden} onclick={toggleHidden}>*</button><button type="button" aria-label="Parent directory" title="Parent directory" disabled={!listing?.parent || busy} onclick={() => load(listing!.parent!)}><Icon name="arrow-up" /></button></div>
    {#if busy}<p class="loading-state" role="status"><span class="loader" aria-hidden="true"></span> Loading directories…</p>{/if}
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    {#if listing}<button type="button" class="directory-current label-chip" aria-pressed={selected === listing.path} onclick={() => selected = listing!.path}>{listing.path}</button>
      {#key listing.path}<ul class="directory-tree">{#each directories as directory (directory.path)}<DirectoryNode {host} {directory} {showHidden} {selected} choose={path => selected = path} {request} />{/each}</ul>{/key}
      {#if !directories.length}<p class="muted">{showHidden ? 'No subdirectories.' : 'No visible subdirectories.'}</p>{/if}{#if listing.truncated}<small>First 256 directories shown. Navigate to a narrower path to see more.</small>{/if}
    {/if}
    <p class="directory-selection"><code>{selected || 'Select a directory'}</code></p>
    <div class="actions"><button type="button" onclick={close}>Cancel</button><button type="button" disabled={!selected || busy || !!error} onclick={() => choose(selected)}>Select directory</button></div>
  </div>
</div>
