<script lang="ts">
  import Icon from './Icon.svelte';
  import { onMount, untrack } from 'svelte';
  import { escapeDismiss } from './escapeDismiss';
  import type { Snippet } from 'svelte';
  let { kind, editing, shared = false, suggestedName = '', name = $bindable(''), submit, close, children }: { kind: string; editing: boolean; shared?: boolean; suggestedName?: string; name: string; submit: () => Promise<void>; close: () => void; children: Snippet } = $props();
  const singular = $derived(({ hosts: 'host', projects: 'project', tools: 'tool', plugins: 'plugin', services: 'service' } as Record<string, string>)[kind] ?? kind);
  let customName = $state(untrack(() => editing && name !== suggestedName));
  let nameInput: HTMLInputElement;
  let formElement: HTMLFormElement;
  onMount(() => {
    const frame = requestAnimationFrame(() => {
      const field = formElement.querySelector<HTMLElement>('input:not([readonly]):not(:disabled):not([type="hidden"]):not([type="checkbox"]):not([type="color"]), textarea:not([readonly]):not(:disabled)')
        ?? formElement.querySelector<HTMLElement>('select:not(:disabled), input:not([readonly]):not(:disabled):not([type="hidden"])');
      field?.focus({ preventScroll: true });
    });
    return () => cancelAnimationFrame(frame);
  });
  $effect(() => { if (!customName) name = suggestedName; });
  let busy = $state(false), error = $state('');
  async function save(event: SubmitEvent) {
    event.preventDefault(); busy = true; error = '';
    try { await submit(); } catch (e) { error = String(e); } finally { busy = false; }
  }
</script>
<div class="overlay" role="presentation"><div class="dialog" use:escapeDismiss={close} role="dialog" tabindex="-1" aria-modal="true" aria-label={`Configure ${singular}`}>
  <h2>{editing ? 'Edit' : 'New'} {singular}</h2>
  {#if shared}<small>Shared across all hosts</small>{/if}
  <form bind:this={formElement} onsubmit={save}>
    <div class="name-field"><label>Name<input bind:this={nameInput} required readonly={!customName} bind:value={name} /></label><button type="button" class:custom-name={customName} aria-pressed={customName} aria-label="Custom name" title={customName ? 'Use automatic name' : 'Customize name'} onclick={() => { customName = !customName; if (customName) nameInput.focus(); }}><Icon name="edit" /></button></div>
    {@render children()}
    {#if error}<p class="error">{error}</p>{/if}
    <div class="actions"><button type="button" onclick={close}>Cancel</button><button disabled={busy}>{busy ? 'Saving…' : 'Save'}</button></div>
  </form>
</div></div>
