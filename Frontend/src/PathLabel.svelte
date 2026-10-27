<script lang="ts">
  import { shortPath } from './paths';
  let { path }: { path: string } = $props();
  let expandedPath = $state<string>();
  const expanded = $derived(expandedPath === path);
</script>
{#if path.startsWith('/')}
  <button class="label-chip path-chip" aria-expanded={expanded} aria-label={`${expanded ? 'Shorten path' : 'Show full path'} ${path}`} title={path} onclick={() => expandedPath = expanded ? undefined : path}><span class="path-text">{expanded ? path : shortPath(path)}</span></button>
{:else}
  <span class="label-chip path-chip"><span class="path-text">{path}</span></span>
{/if}

<style>
  .path-chip { max-width: 100%; min-width: 0; border: 0; color: inherit; font-size: inherit; text-align: left; }
  button.path-chip { cursor: pointer; }
  .path-text { display: block; line-height: 1.5; height: 1.5em; overflow-x: auto; overflow-y: hidden; white-space: nowrap; scrollbar-width: none; }
  .path-text::-webkit-scrollbar { display: none; }
</style>
