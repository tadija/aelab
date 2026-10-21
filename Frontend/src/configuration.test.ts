import { expect, it } from 'vitest';
import { ConfigurationClient, RequestError } from './configuration';
import { identifyConfig, type Config, type Snapshot } from './model';

const initial = (): Snapshot => ({ revision: '0', config: { version: 1, tools: [], plugins: [], paths: [], ttyButtons: [], hosts: [
  { id: 'a', name: 'A', transport: 'local', projects: [], services: [], tools: [], plugins: [] },
  { id: 'b', name: 'B', transport: 'local', projects: [], services: [], tools: [], plugins: [] }
] } });
function fixture() {
  let server = initial(); let revision = 0; const writes: string[] = [];
  let beforeRead = async () => {}; let beforeWrite = async () => {};
  const request = async <T>(_path: string, method = 'GET', body?: unknown): Promise<T> => {
    if (method === 'GET') { const read = structuredClone(server); await beforeRead(); return read as T; }
    await beforeWrite(); const draft = body as Snapshot; writes.push(draft.revision);
    if (draft.revision !== server.revision) throw new RequestError('Configuration changed', 409);
    server = { config: identifyConfig(structuredClone(draft.config)), revision: String(++revision) }; return structuredClone(server) as T;
  };
  let shown = initial(); const client = new ConfigurationClient(request, value => shown = value);
  return { client, writes, request, get shown() { return shown; }, get server() { return server; },
    external(edit: (config: Config) => void) { edit(server.config); server.revision = String(++revision); },
    delayRead(work: () => Promise<void>) { beforeRead = work; }, delayWrite(work: () => Promise<void>) { beforeWrite = work; } };
}
function deferred() { let release!: () => void; const promise = new Promise<void>(resolve => release = resolve); return { promise, release }; }

it('queues rapid tool/plugin mutations and preserves both selections', async () => {
  const f = fixture(); await f.client.load(); const gate = deferred(); f.delayWrite(() => gate.promise);
  const first = f.client.update(config => config.hosts[0].tools.push('one'));
  const second = f.client.update(config => config.hosts[0].tools.push('two'));
  const third = f.client.update(config => config.hosts[0].plugins.push('probe'));
  gate.release(); await Promise.all([first, second, third]);
  expect(f.writes).toEqual(['0', '1', '2']);
  expect(f.shown.config.hosts[0].tools).toEqual(['one', 'two']); expect(f.server.config.hosts[0].plugins).toEqual(['probe']);
});
it('an earlier delayed poll cannot replace a newer saved snapshot', async () => {
  const f = fixture(); const gate = deferred(); f.delayRead(() => gate.promise);
  const poll = f.client.load(); const config = initial().config; config.hosts[0].name = 'Saved';
  const save = f.client.replace(config, '0'); gate.release(); await Promise.all([poll, save]);
  expect(f.shown.revision).toBe('1'); expect(f.shown.config.hosts[0].name).toBe('Saved');
});
it('rebases only explicit mutations after an external change and preserves unrelated edits', async () => {
  const f = fixture(); await f.client.load(); f.external(config => config.hosts[1].name = 'External edit');
  await f.client.update(config => config.hosts[0].tools.push('one'));
  expect(f.writes).toEqual(['0', '1']); expect(f.server.config.hosts[1].name).toBe('External edit');
  expect(f.server.config.hosts[0].tools).toEqual(['one']);
});
it('never silently retries stale full-form saves and recovers the queue after an error', async () => {
  const f = fixture(); await f.client.load(); f.external(config => config.hosts[1].name = 'External edit');
  await expect(f.client.replace(initial().config, '0')).rejects.toMatchObject({ status: 409 });
  expect(f.writes).toEqual(['0']); expect(f.server.config.hosts[1].name).toBe('External edit');
  await f.client.load(); await f.client.update(config => config.hosts[0].tools.push('next'));
  expect(f.server.config.hosts[0].tools).toEqual(['next']);
});
it('does not retry validation errors or retry conflicts indefinitely', async () => {
  let attempts = 0;
  const request = async <T>(_path: string, method = 'GET'): Promise<T> => {
    if (method === 'GET') return initial() as T;
    attempts++; throw new RequestError('Changed again', 409);
  };
  const client = new ConfigurationClient(request, () => {}); await client.load();
  await expect(client.update(config => config.hosts[0].tools.push('one'))).rejects.toMatchObject({ status: 409 }); expect(attempts).toBe(2);
  const invalid = new ConfigurationClient(async <T>(_path: string, method = 'GET'): Promise<T> => {
    if (method === 'GET') return initial() as T;
    throw new RequestError('Invalid config', 400);
  }, () => {});
  await expect(invalid.update(() => {})).rejects.toMatchObject({ status: 400 });
});
