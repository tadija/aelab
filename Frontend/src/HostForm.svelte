<script lang="ts">
  import EntityForm from './EntityForm.svelte';
  import { untrack } from 'svelte';
  import { nameID, hostSourceName } from './model';
  import type { Host } from './model';
  let { existing, initialTint, commit, close }: { existing?: Host; initialTint?: string; commit: (item: Host) => Promise<void>; close: () => void } = $props();
  const seed = untrack(() => existing);
  let name = $state(seed?.name ?? '');
  let transport = $state(seed?.transport ?? 'ssh'), daemon = $state(seed?.daemon ?? ''), destination = $state(seed?.destination ?? ''), port = $state(seed?.port?.toString() ?? '');
  let tint = $state(untrack(() => initialTint) ?? seed?.tint ?? '#2dd4bf'), background = $state(seed?.background ?? '#0b0f0d');
</script>
<EntityForm kind="hosts" editing={!!existing} suggestedName={hostSourceName(transport, destination, daemon)} bind:name {close} submit={() => commit({ id: nameID(name), name, transport, ...(transport !== 'local' && destination ? { destination, ...(port ? { port: Number(port) } : {}) } : {}), ...(daemon ? { daemon } : {}), background, tint, ...(seed?.dockerContext ? { dockerContext: seed.dockerContext } : {}), projects: seed?.projects ?? [], services: seed?.services ?? [], tools: seed?.tools ?? [], plugins: seed?.plugins ?? [] })}>
  <label>Execution<select bind:value={transport}><option value="ssh">Remote SSH</option><option value="local">Local (this server)</option><option value="daemon">Remote daemon</option></select></label>
  {#if transport === 'ssh'}
  <label>Approved SSH alias / user@address<input required bind:value={destination} placeholder="dev-server" /></label>
  <label>Port (optional)<input type="number" min="1" max="65535" bind:value={port} /></label>
  {:else if transport === 'daemon'}<label>Paired connection ID<input required bind:value={daemon} /></label>{:else}<small>Runs under the aelab process account.</small>{/if}
  <label class="inline-field">Host tint<input type="color" bind:value={tint} /></label>
  <label class="inline-field">Terminal background<input type="color" bind:value={background} /></label>
</EntityForm>
