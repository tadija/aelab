<script lang="ts">
  import DirectoryNode from './DirectoryNode.svelte';
  import Icon from './Icon.svelte';
  import type { DirectoryListing, HostDirectory } from './model';
  let { host, directory, showHidden, selected, choose, request }: { host: string; directory: HostDirectory; showHidden: boolean; selected: string; choose: (path: string) => void; request: <T>(path: string) => Promise<T> } = $props();
  let open = $state(false); let listing = $state<DirectoryListing>(); let busy = $state(false); let error = $state('');
  const directories = $derived((listing?.directories ?? []).filter(child => showHidden || !child.name.startsWith('.')));
  async function toggle() {
    open = !open;
    if (!open || listing) return;
    busy = true; error = '';
    try { listing = await request<DirectoryListing>(`/api/hosts/${encodeURIComponent(host)}/directories?path=${encodeURIComponent(directory.path)}`); }
    catch (e) { error = String(e); } finally { busy = false; }
  }
</script>
<li>
  <div class="directory-row"><button type="button" class="directory-name" aria-pressed={selected === directory.path} aria-expanded={open} aria-busy={busy} disabled={busy} onclick={() => { choose(directory.path); void toggle(); }}>{#if busy}<span class="spinner" aria-hidden="true"></span>{:else}<Icon name={open ? 'folder-open' : 'folder'} />{/if}{directory.name}</button></div>
  {#if open}
    {#if error}<p class="error" role="alert">{error} <button type="button" onclick={() => { open = false; void toggle(); }}>Retry</button></p>{/if}
    {#if listing}<ul>{#each directories as child (child.path)}<DirectoryNode {host} {showHidden} directory={child} {selected} {choose} {request} />{/each}</ul>{#if !directories.length}<small>{showHidden ? 'No subdirectories.' : 'No visible subdirectories.'}</small>{/if}{#if listing.truncated}<small>First 256 directories shown.</small>{/if}{/if}
  {/if}
</li>
