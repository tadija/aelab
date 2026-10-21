<script lang="ts">
  import type { Snippet } from 'svelte';
  let { kind, editing, shared = false, name = $bindable(''), submit, close, children }: { kind: string; editing: boolean; shared?: boolean; name: string; submit: () => Promise<void>; close: () => void; children: Snippet } = $props();
  let busy = $state(false), error = $state('');
  async function save(event: SubmitEvent) {
    event.preventDefault(); busy = true; error = '';
    try { await submit(); } catch (e) { error = String(e); } finally { busy = false; }
  }
</script>
<div class="overlay" role="presentation"><div class="dialog" role="dialog" tabindex="-1" aria-modal="true" aria-label={`Configure ${kind}`}>
  <h2>{editing ? 'Edit' : 'New'} {kind}</h2>
  {#if shared}<small>Shared across all hosts</small>{/if}
  <form onsubmit={save}>
    <label>Name<input required bind:value={name} /></label>
    {@render children()}
    {#if error}<p class="error">{error}</p>{/if}
    <div class="actions"><button type="button" onclick={close}>Cancel</button><button disabled={busy}>{busy ? 'Saving…' : 'Save'}</button></div>
  </form>
</div></div>
