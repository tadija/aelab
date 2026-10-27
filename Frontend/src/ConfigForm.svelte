<script lang="ts">
  import { untrack } from 'svelte';
  import { nameID, renameReferences, type EntityKind, type Snapshot, type Config, type Host, type Project, type Service, type Tool, type Plugin } from './model';
  import HostForm from './HostForm.svelte';
  import ProjectForm from './ProjectForm.svelte';
  import ServiceForm from './ServiceForm.svelte';
  import ToolForm from './ToolForm.svelte';
  import PluginForm from './PluginForm.svelte';
  type Definition = Host | Project | Service | Tool | Plugin;
  let { snapshot, kind, existing, host, save, prepareProject, close, initialTint, request, platform }: { snapshot: Snapshot; kind: EntityKind; existing?: Definition; host: string; save: (config: Config, revision: string) => Promise<void>; prepareProject: (project: Project) => Promise<void>; close: () => void; initialTint?: string; request: <T>(path: string) => Promise<T>; platform?: string } = $props();
  const revision = untrack(() => snapshot.revision), seed = untrack(() => existing);
  async function commit(item: Definition) {
    const config = structuredClone($state.snapshot(snapshot.config));
    const rows: Definition[] = kind === 'hosts' ? config.hosts : kind === 'tools' || kind === 'plugins' ? config[kind] : config.hosts.find(h => h.id === host)![kind];
    item.id = nameID(item.name);
    if ((!/^[a-z0-9.][a-z0-9.-]{0,63}$/.test(item.id) || !/[a-z0-9]/.test(item.id))) throw new Error('Use a name with letters or numbers and at most 64 URL characters.');
    if (rows.some(row => row.id === item.id && row.id !== seed?.id)) throw new Error('Another name already uses this URL. Choose a different name.');
    if (kind === 'projects') await prepareProject(item as Project);
    if (seed && (kind === 'tools' || kind === 'plugins')) renameReferences(config, kind, seed.id, item.id);
    const index = seed ? rows.findIndex(row => row.id === seed.id) : -1;
    if (index < 0) rows.push(item); else rows[index] = item;
    await save(config, revision); close();
  }
</script>
{#if kind === 'hosts'}<HostForm existing={existing as Host | undefined} {initialTint} {commit} {close} />
{:else if kind === 'projects'}<ProjectForm existing={existing as Project | undefined} {host} {request} {commit} {close} />
{:else if kind === 'services'}<ServiceForm existing={existing as Service | undefined} {host} {request} {platform} {commit} {close} />
{:else if kind === 'tools'}<ToolForm existing={existing as Tool | undefined} {host} {request} {commit} {close} />
{:else}<PluginForm existing={existing as Plugin | undefined} {commit} {close} />{/if}
