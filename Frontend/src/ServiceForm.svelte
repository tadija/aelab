<script lang="ts">
  import EntityForm from './EntityForm.svelte';
  import { untrack } from 'svelte';
  import { nameID } from './model';
  import DirectoryField from './DirectoryField.svelte';
  import type { Service } from './model';
  let { existing, host, request, platform, commit, close }: { existing?: Service; host: string; platform?: string; request: <T>(path: string) => Promise<T>; commit: (item: Service) => Promise<void>; close: () => void } = $props();
  const seed = untrack(() => existing);
  let name = $state(seed?.name ?? '');
  let provider = $state(seed?.provider ?? (untrack(() => platform) === 'macos' ? 'launchd' : 'systemd')), target = $state(seed?.target ?? '');
  let userUnit = $state(seed?.userUnit ?? false), sudo = $state(seed?.sudo ?? false), plist = $state(seed?.plist ?? ''), logFiles = $state(seed?.logFiles?.join('\n') ?? '');
  let directory = $state(seed?.directory ?? ''), files = $state(seed?.files?.join('\n') ?? ''), environmentFile = $state(seed?.environmentFile ?? '');
</script>
<EntityForm kind="services" editing={!!existing} bind:name {close} submit={() => commit({ id: nameID(name), name, provider, target, ...(provider === 'systemd' ? { userUnit, sudo } : provider === 'launchd' ? { sudo, ...(plist ? { plist } : {}), ...(logFiles ? { logFiles: logFiles.split('\n').filter(Boolean) } : {}) } : {}), ...(directory ? { directory } : {}), ...(files ? { files: files.split('\n').filter(Boolean) } : {}), ...(environmentFile ? { environmentFile } : {}) })}>
  <label>Provider<select bind:value={provider}><option>systemd</option><option>launchd</option><option>docker</option><option>compose</option></select></label>
  <label>{{ systemd: 'Systemd unit', launchd: 'Launchd service target', docker: 'Container name or ID', compose: 'Compose project name' }[provider]}<input required bind:value={target} placeholder={{ systemd: 'example.service', launchd: 'gui/502/com.example.agent or system/com.example.daemon', docker: 'web', compose: 'app' }[provider]} /></label>
  {#if provider === 'systemd'}
    <label class="inline-field"><input type="checkbox" bind:checked={userUnit} /> User unit</label><small>Manage this account’s systemd user services (--user); usually no sudo needed.</small><label class="inline-field"><input type="checkbox" bind:checked={sudo} /> Use sudo for start / stop / restart</label><small>Uses sudo -n: no password prompt. Requires permission on this host; keep off for user units.</small>
  {:else if provider === 'launchd'}
    <label>Plist path (optional, required for stop/reload)<input bind:value={plist} placeholder="~/Library/LaunchAgents/com.example.agent.plist" /></label>
    <label>Log files (optional, one per line)<textarea bind:value={logFiles} placeholder="~/Library/Logs/example.log"></textarea></label>
    <label class="inline-field"><input type="checkbox" bind:checked={sudo} /> Use sudo for start / stop / restart</label><small>Uses sudo -n: no password prompt. Requires permission on this host.</small>
    <small>Stop unloads the job; its plist is needed to load it again. Without log files, Logs shows unified launchd lifecycle messages.</small>
  {:else if provider === 'compose'}
    <DirectoryField label="Absolute Compose directory" {host} {request} bind:value={directory} placeholder="/srv/app" />
    <label>Absolute Compose files (one per line)<textarea bind:value={files}></textarea></label>
    <label>Absolute environment file (optional)<input bind:value={environmentFile} /></label>
    <small>Start uses existing containers. No up, build, pull or down.</small>
  {/if}
</EntityForm>
