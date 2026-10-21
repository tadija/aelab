<script lang="ts">
  import DocumentEditor, { type EditorDocument } from './DocumentEditor.svelte';
  let { request, close, saved }: { request: <T>(path: string, method?: string, body?: unknown) => Promise<T>; close: () => void; saved: () => Promise<void> } = $props();
</script>
<DocumentEditor editorLabel="Main configuration JSON" title="CONFIGURATION" label="Main configuration" {close} {saved}
  load={() => request<EditorDocument>('/api/config?format=source')}
  validate={({ content }) => request('/api/config/validation', 'POST', { content })}
  save={document => request<EditorDocument>('/api/config?format=source', 'PUT', document)}
  discard="Discard unsaved configuration edits?" validNotice="Configuration valid. No restart required."
  saveNotice="Saved. New operations use this configuration; reconnect existing terminals to apply host changes.">
  {#snippet filename()}<p class="muted">config/aelab.json</p>{/snippet}
</DocumentEditor>
