<script lang="ts">
  import EntityForm from './EntityForm.svelte';
  import { untrack } from 'svelte';
  import { nameID, sourceName } from './model';
  import DirectoryField from './DirectoryField.svelte';
  import type { Tool } from './model';
  let { existing, host, request, commit, close }: { existing?: Tool; host: string; request: <T>(path: string) => Promise<T>; commit: (item: Tool) => Promise<void>; close: () => void } = $props();
  const seed = untrack(() => existing);
  let name = $state(seed?.name ?? '');
  let executable = $state(seed?.executable ?? ''), argumentsText = $state(JSON.stringify(seed?.arguments ?? []));
  let altText = $state(seed?.altArguments ? JSON.stringify(seed.altArguments) : '');
  let yoloText = $state(seed?.yoloArguments ? JSON.stringify(seed.yoloArguments) : ''), directory = $state(seed?.directory ?? '');
</script>
<EntityForm kind="tools" editing={!!existing} suggestedName={sourceName(executable)} shared bind:name {close} submit={() => commit({ id: nameID(name), name, executable, arguments: JSON.parse(argumentsText), ...(altText ? { altArguments: JSON.parse(altText) } : {}), ...(yoloText ? { yoloArguments: JSON.parse(yoloText) } : {}), ...(directory ? { directory } : {}) })}>
  <label>Executable or approved host script<input required bind:value={executable} /></label>
  <label>Arguments (JSON string array)<textarea bind:value={argumentsText}></textarea></label>
  <label>ALT arguments (optional JSON string array)<textarea bind:value={altText}></textarea></label>
  <label>YOLO arguments (optional JSON string array)<textarea bind:value={yoloText}></textarea></label>
  <DirectoryField label="Default working directory (optional, absolute)" {host} {request} bind:value={directory} placeholder="/srv/project" />
</EntityForm>
