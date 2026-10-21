<script lang="ts">
  import { statusTone } from './model';
  let { state, stale = false }: { state: string; stale?: boolean } = $props();
  const label = $derived(state === 'unknown' ? 'checking' : state);
  const showStale = $derived(stale && label !== 'checking');
  const tone = $derived(showStale && statusTone(label) === 'success' ? 'warning' : statusTone(label));
</script>
<span class="badge" data-tone={tone}>{label}{#if showStale}<span class="stale"> stale</span>{/if}</span>

<style>
  .badge { display: inline-flex; flex-direction: column; align-items: center; }
</style>
