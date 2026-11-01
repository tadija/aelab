<script lang="ts">
  import { statusTone } from './model';
  let { state, stale = false, refreshing = false, showInstalled = true }: { state: string; stale?: boolean; refreshing?: boolean; showInstalled?: boolean } = $props();
  const label = $derived(refreshing || state === 'unknown' ? 'checking' : state);
  const showStale = $derived(stale && label !== 'checking');
  const tone = $derived(refreshing || showStale ? 'warning' : statusTone(label));
</script>
{#if label !== 'installed' || showInstalled}<span class="badge" data-tone={tone}>{label}</span>{/if}

<style>
  .badge { display: inline-flex; flex-direction: column; align-items: center; }
</style>
