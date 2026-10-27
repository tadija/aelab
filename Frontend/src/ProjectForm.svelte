<script lang="ts">
  import EntityForm from './EntityForm.svelte';
  import { untrack } from 'svelte';
  import { nameID, sourceName } from './model';
  import DirectoryField from './DirectoryField.svelte';
  import type { Project } from './model';
  let { existing, host, request, commit, close }: { existing?: Project; host: string; request: <T>(path: string) => Promise<T>; commit: (item: Project) => Promise<void>; close: () => void } = $props();
  const seed = untrack(() => existing);
  let name = $state(seed?.name ?? '');
  let directory = $state(seed?.dir ?? ''), session = $state(seed?.session ?? '');
</script>
<EntityForm kind="projects" editing={!!existing} suggestedName={sourceName(directory)} bind:name {close} submit={() => commit({ id: nameID(name), name, dir: directory, ...(session ? { session } : {}) })}>
  <DirectoryField label="Absolute project directory" {host} {request} required bind:value={directory} placeholder="/srv/project" />
  <label>Stable tmux session (optional)<input bind:value={session} /></label>
</EntityForm>
