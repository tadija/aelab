<script lang="ts">
  import EntityForm from './EntityForm.svelte';
  import { untrack } from 'svelte';
  import { nameID } from './model';
  import DirectoryField from './DirectoryField.svelte';
  import type { Tool } from './model';
  let { existing, host, request, commit, close }: { existing?: Tool; host: string; request: <T>(path: string) => Promise<T>; commit: (item: Tool) => Promise<void>; close: () => void } = $props();
  const seed = untrack(() => existing);
  let name = $state(seed?.name ?? '');
  let executable = $state(seed?.executable ?? ''), argumentsText = $state(JSON.stringify(seed?.arguments ?? []));
  let yoloText = $state(seed?.yoloArguments ? JSON.stringify(seed.yoloArguments) : ''), session = $state(seed?.session ?? ''), directory = $state(seed?.directory ?? '');
</script>
<EntityForm kind="tools" editing={!!existing} shared bind:name {close} submit={() => commit({ id: nameID(name), name, executable, arguments: JSON.parse(argumentsText), ...(yoloText ? { yoloArguments: JSON.parse(yoloText) } : {}), ...(session ? { session } : {}), ...(directory ? { directory } : {}) })}>
  <label>Executable or approved host script<input required bind:value={executable} /></label>
  <label>Arguments (JSON string array)<textarea bind:value={argumentsText}></textarea></label>
  <label>YOLO arguments (optional JSON string array)<textarea bind:value={yoloText}></textarea></label>
  <label>Stable tmux session (optional)<input bind:value={session} /></label>
  <DirectoryField label="Default working directory (optional, absolute)" {host} {request} bind:value={directory} placeholder="/srv/project" />
</EntityForm>
