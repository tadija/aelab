<script lang="ts">
  import DirectoryNode from './DirectoryNode.svelte';
  import Icon from './Icon.svelte';
  import type { DirectoryListing, HostDirectory } from './model';
  let { host, directory, selected, choose, request }: { host: string; directory: HostDirectory; selected: string; choose: (path: string) => void; request: <T>(path: string) => Promise<T> } = $props();
  let open = $state(false); let listing = $state<DirectoryListing>(); let busy = $state(false); let error = $state('');
  async function toggle() {
    open = !open;
    if (!open || listing) return;
    busy = true; error = '';
    try { listing = await request<DirectoryListing>(`/api/hosts/${encodeURIComponent(host)}/directories?path=${encodeURIComponent(directory.path)}`); }
    catch (e) { error = String(e); } finally { busy = false; }
  }
</script>
<li>
  <div class="directory-row"><button type="button" class="directory-expand" aria-label={`${open ? 'Collapse' : 'Expand'} directory ${directory.name}`} aria-expanded={open} disabled={busy} onclick={toggle}>{#if busy}<span class="spinner" aria-hidden="true"></span>{:else}<span aria-hidden="true">{open ? '▾' : '▸'}</span>{/if}</button><button type="button" class="directory-name" aria-pressed={selected === directory.path} onclick={() => choose(directory.path)}><Icon name="folder" />{directory.name}</button></div>
  {#if open}
    {#if error}<p class="error" role="alert">{error} <button type="button" onclick={() => { open = false; void toggle(); }}>Retry</button></p>{/if}
    {#if listing}<ul>{#each listing.directories as child (child.path)}<DirectoryNode {host} directory={child} {selected} {choose} {request} />{/each}</ul>{#if !listing.directories.length}<small>No subdirectories.</small>{/if}{#if listing.truncated}<small>First 256 directories shown.</small>{/if}{/if}
  {/if}
</li>
