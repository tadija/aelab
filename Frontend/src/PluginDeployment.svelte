<script lang="ts">
  import { onMount } from 'svelte';
  import type { Host, PluginDeployment } from './model';
  let { host, plugin, localHosts, request, deployed, close }: { host: string; plugin: string; localHosts: Host[]; request: <T>(path: string, method?: string, body?: unknown) => Promise<T>; deployed: () => void; close: () => void } = $props();
  let sourceHost = $state(''); let plan = $state<PluginDeployment>(); let busy = $state(false); let error = $state(''); let notice = $state(''); let generation = 0;
  const base = $derived(`/api/hosts/${encodeURIComponent(host)}/plugins/${encodeURIComponent(plugin)}/source/deployment`);
  async function load() {
    const current = ++generation; busy = true; error = ''; notice = ''; plan = undefined;
    try { const result = await request<PluginDeployment>(`${base}?from=${encodeURIComponent(sourceHost)}`); if (current === generation) plan = result; }
    catch (e) { if (current === generation) error = String(e); } finally { if (current === generation) busy = false; }
  }
  async function deploy() {
    busy = true; error = '';
    try { await request(base, 'POST', plan); notice = plan?.requiresBuild ? 'Source deployed. Build its executable on this host before running.' : 'Script deployed. Enable the plugin on this host when it is available.'; plan = undefined; deployed(); }
    catch (e) { error = String(e); } finally { busy = false; }
  }
  onMount(() => { sourceHost = localHosts[0]?.id ?? ''; if (sourceHost) void load(); return () => { generation++; }; });
</script>
<div class="overlay" role="presentation"><div class="dialog" role="dialog" tabindex="-1" aria-modal="true" aria-label="Deploy plugin script" aria-busy={busy}>
  <h2>DEPLOY SCRIPT</h2>
  <label>Local source host<select bind:value={sourceHost} disabled={busy} onchange={load}>{#each localHosts as local}<option value={local.id}>{local.name}</option>{/each}</select></label>
  {#if busy}<p class="loading-state" role="status"><span class="loader" aria-hidden="true"></span> {plan ? 'Deploying script…' : 'Loading preview…'}</p>{/if}
  {#if plan}<p><code>{plan.sourcePath}</code><br />→ {host}: <code>{plan.targetPath}</code></p><p class="muted">{plan.targetRevision ? 'Replaces the existing script, preserving its permissions.' : 'Creates the script and its parent directory with private permissions.'} {plan.requiresBuild ? 'Only source is copied; this plugin needs a host-side build.' : 'Interpreters must already be installed on the host.'}</p>{/if}
  {#if error}<p class="error" role="alert">{error}</p>{/if}{#if notice}<p role="status">{notice}</p>{/if}
  <div class="actions"><button type="button" disabled={busy} onclick={close}>Close</button>{#if plan}<button type="button" disabled={busy} onclick={deploy}>{plan.targetRevision ? 'Replace script' : 'Deploy script'}</button>{/if}</div>
</div></div>
