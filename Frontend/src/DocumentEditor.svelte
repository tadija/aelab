<script module lang="ts">
  export type EditorDocument = { content: string; revision: string };
</script>
<script lang="ts">
  import { escapeDismiss } from './escapeDismiss';
  import type { Snippet } from 'svelte';
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import CodeEditor from './CodeEditor.svelte';
  import { editorWrap, rememberEditorWrap } from './editorPreferences';
  let { title, label, editorLabel, filename, load, validate, save, saved, close, discard, validNotice, saveNotice, language = 'json', available = true, progress = false }: {
    title: string; label: string; editorLabel: string; filename: Snippet; load: () => Promise<EditorDocument>; validate: (document: EditorDocument) => Promise<unknown>; save: (document: EditorDocument) => Promise<EditorDocument>; saved?: () => Promise<void>; close: () => void; discard: string; validNotice: string; saveNotice: string; language?: string; available?: boolean; progress?: boolean;
  } = $props();
  let content = $state(''), original = $state(''), revision = $state('');
  let busy = $state(false), error = $state(''), notice = $state(''), wrap = $state(editorWrap());
  const dirty = $derived(content !== original);
  function accept(document: EditorDocument) { content = original = document.content; revision = document.revision; }
  async function run(operation: () => Promise<void>) {
    busy = true; error = ''; notice = '';
    try { await operation(); } catch (e) { error = String(e); } finally { busy = false; }
  }
  function submit(saving: boolean) {
    return run(async () => {
      const document = { content, revision };
      if (saving) { accept(await save(document)); await saved?.(); } else await validate(document);
      notice = saving ? saveNotice : validNotice;
    });
  }
  function dismiss() { if (!dirty || confirm(discard)) close(); }
  onMount(() => { void run(async () => accept(await load())); });
</script>
<div class="overlay" role="presentation"><div class="dialog config-editor" use:escapeDismiss={() => { if (!busy) dismiss(); }} role="dialog" tabindex="-1" aria-modal="true" aria-label={label} aria-busy={progress ? busy : undefined}>
  <h2>{title}</h2>{@render filename()}
  {#if progress && busy}<p class="loading-state" role="status"><span class="loader" aria-hidden="true"></span> {revision ? 'Working…' : 'Loading script…'}</p>{/if}
  {#if available}<div class="config-field"><CodeEditor {wrap} bind:value={content} disabled={busy || !revision} {language} label={editorLabel} /></div>{:else}<p class="muted">No existing configured Bash, Ruby or Swift sources are available.</p>{/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}{#if notice}<p role="status">{notice}</p>{/if}
  <div class="actions"><button onclick={() => { wrap = !wrap; rememberEditorWrap(wrap); }} aria-pressed={wrap} aria-label="Wrap lines" title="Wrap lines"><Icon name="wrap" /></button><button onclick={() => submit(false)} disabled={busy || !revision} aria-label="Validate" title="Validate"><Icon name="validate" /></button><button onclick={() => submit(true)} disabled={busy || !revision || !dirty} aria-label="Save" title="Save"><Icon name="save" /></button><button onclick={dismiss} disabled={busy} aria-label="Close" title="Close"><Icon name="logout" /></button></div>
</div></div>
