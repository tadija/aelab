<script lang="ts">
  import DocumentEditor, { type EditorDocument } from './DocumentEditor.svelte';
  import type { PluginSource } from './model';
  let { host, plugin, source, request, close }: { host: string; plugin: string; source?: PluginSource; request: <T>(path: string, method?: string, body?: unknown) => Promise<T>; close: () => void } = $props();
  const base = $derived(`/api/hosts/${encodeURIComponent(host)}/plugins/${encodeURIComponent(plugin)}/source`);
</script>
<DocumentEditor editorLabel="Plugin source" title="PLUGIN SCRIPTS" label="Plugin scripts" {close} progress available={!!source} language={source?.language ?? 'bash'}
  load={() => request<EditorDocument>(base)} validate={document => request(`${base}/validation`, 'POST', document)}
  save={document => request<EditorDocument>(base, 'PUT', document)} discard="Discard unsaved script edits?"
  validNotice="Syntax valid." saveNotice="Saved. The next probe uses this file; compiled plugins require rebuilding.">
  {#snippet filename()}<small>{source?.filename ?? plugin}</small>{/snippet}
</DocumentEditor>
