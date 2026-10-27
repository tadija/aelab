<script lang="ts">
  import EntityForm from './EntityForm.svelte';
  import { untrack } from 'svelte';
  import { nameID, sourceName } from './model';
  import type { Plugin } from './model';
  let { existing, commit, close }: { existing?: Plugin; commit: (item: Plugin) => Promise<void>; close: () => void } = $props();
  const seed = untrack(() => existing);
  let name = $state(seed?.name ?? '');
  let executable = $state(seed?.executable ?? ''), argumentsText = $state(JSON.stringify(seed?.arguments ?? []));
  let source = $state(seed?.source ?? ''), timeout = $state(seed?.timeout ?? 10);
</script>
<EntityForm kind="plugins" editing={!!existing} suggestedName={sourceName(executable)} shared bind:name {close} submit={() => commit({ id: nameID(name), name, executable, arguments: JSON.parse(argumentsText), timeout, ...(source ? { source } : {}) })}>
  <label>Executable or approved host script<input required bind:value={executable} /></label>
  <label>Arguments (JSON string array)<textarea bind:value={argumentsText}></textarea></label>
  <label>Source file (optional, absolute or ~/)<input bind:value={source} placeholder="~/.aelab/plugins/probe.swift" /></label>
  <label>Timeout (seconds)<input type="number" min="1" max="30" required bind:value={timeout} /></label>
</EntityForm>
