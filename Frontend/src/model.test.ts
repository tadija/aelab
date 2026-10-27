import { describe, it, expect } from 'vitest';
import { route, terminalName, terminalTabTitle, terminalURL, shouldCopy, prefixBytes, discoveryMatchesStatus, validTint, nameID, sourceName, hostSourceName, identifyConfig, configurationPayload, renameReferences, pluginHasSource, tmuxSessionMessage, serviceDiscoveryMessage, launchdState } from './model';
describe('terminal UX boundaries', () => {
 it('requires host-aware tmux deep links', () => { expect(route('/hosts/a/projects/main/')).toMatchObject({host:'a',project:'main',terminal:true}); expect(route('/hosts/a/tty/tmux/saved/')).toMatchObject({host:'a',terminal:true,session:'saved'}); expect(route('/tty/tmux/saved/')).toMatchObject({host:undefined,terminal:false}); });
 it('preserves project/tool combinations in launch URLs', () => { const url = terminalURL({host:'b',project:'p',tool:'t',persistent:true}); expect(url).toContain('/hosts/b/tty/'); expect(url).toContain('project=p'); expect(url).toContain('tool=t'); });
 it('copies selected text and leaves ordinary Ctrl+C as interrupt', () => { expect(shouldCopy('c',true,false,false,false)).toBe(false); expect(shouldCopy('c',true,false,false,true)).toBe(true); expect(shouldCopy('c',false,true,false,false)).toBe(true); expect(shouldCopy('c',true,false,true,false)).toBe(true); });
});

it('maps remote tmux prefixes without changing interrupt semantics', () => { expect(prefixBytes('C-a')).toBe('\x01'); expect(prefixBytes('C-b')).toBe('\x02'); expect(prefixBytes('M-x')).toBe('\x1bx'); });

it('filters native discovery states with running as the default', () => {
 const item = (provider: 'systemd' | 'docker' | 'compose', state: string) => ({provider, state, target:'native'});
 expect(discoveryMatchesStatus(item('systemd','active/running'), 'running')).toBe(true);
 expect(discoveryMatchesStatus(item('systemd','active/exited'), 'running')).toBe(false);
 expect(discoveryMatchesStatus(item('docker','exited'), 'running')).toBe(false);
 expect(discoveryMatchesStatus(item('compose','running, exited'), 'running')).toBe(true);
 expect(discoveryMatchesStatus(item('systemd','failed/failed'), 'failed/failed')).toBe(true);
 expect(discoveryMatchesStatus(item('docker','paused'), 'all')).toBe(true);
});
it('accepts only valid persisted host tint colors', () => {
 expect(validTint('#c75b39')).toBe('#c75b39'); expect(validTint('red')).toBeUndefined(); expect(validTint(null)).toBeUndefined();
});

it('derives URL identity only from the name', () => {
 expect(nameID('.aelab')).toBe('.aelab');
 expect(nameID('aelab')).toBe('aelab');
 expect(nameID('com.example.agent')).toBe('com.example.agent');
 expect(nameID('Dév Server')).toBe('dev-server');
 expect(nameID('DEV---Server')).toBe('dev-server');
 expect(nameID('✨')).toBe('');
 expect(nameID('ＡＢＣ 123')).toBe('abc-123');
});
it('sends name-only definitions and derives every collection on read', () => {
 const config = { version: 1, paths: [], ttyButtons: [], tools: [{ name: 'Shared tool' }], plugins: [{ name: 'Shared plugin' }], hosts: [{ name: 'Dev host', projects: [{ name: 'My project' }], services: [{ name: 'Web service' }], tools: ['shared-tool'], plugins: ['shared-plugin'] }] } as unknown as Config;
 const view = identifyConfig(config);
 expect(view.hosts[0].id).toBe('dev-host'); expect(view.tools[0].id).toBe('shared-tool');
 expect(view.hosts[0].projects[0].id).toBe('my-project'); expect(view.hosts[0].services[0].id).toBe('web-service');
 expect(configurationPayload(view)).toEqual(config);
 renameReferences(view, 'tools', 'shared-tool', 'new-tool');
 renameReferences(view, 'plugins', 'shared-plugin', 'new-plugin');
 renameReferences(view, 'tools', 'new-tool', 'final-tool');
 expect(view.hosts[0].tools).toEqual(['final-tool']); expect(view.hosts[0].plugins).toEqual(['new-plugin']);
});

import { enabledTools, type Config, type Host } from './model';
it('selects centralized tools by enabled host IDs without copying definitions', () => {
  const config = { tools: [{ id: 'one', name: 'One', executable: 'one', arguments: [] }, { id: 'two', name: 'Two', executable: 'two', arguments: [] }] } as unknown as Config;
  const host = { tools: ['two'] } as Host;
  expect(enabledTools(config, host).map(t => t.id)).toEqual(['two']);
  expect(enabledTools(config, { tools: [] } as unknown as Host)).toEqual([]);
});

import { statusTone } from './model';
it('uses semantic plugin status colors independently of host tint', () => {
 expect(statusTone('ok')).toBe('success'); expect(statusTone('warning')).toBe('warning');
 expect(statusTone('critical')).toBe('error'); expect(statusTone('unknown')).toBe('neutral');
});

it('routes pinned terminals without requesting tmux creation', () => {
 const url = terminalURL({host:'local',pinned:'owned-id',project:'p'});
 expect(url).toBe('/hosts/local/tty/pinned/owned-id/?project=p');
 expect(route('/hosts/local/tty/pinned/owned-id/')).toMatchObject({host:'local',pinned:'owned-id',terminal:true});
 expect(url).not.toContain('persistent=1');
});

it('preserves literal standalone YOLO working directories in terminal links', () => {
  const directory = "/srv/it's a project & more";
  const url = new URL(terminalURL({ host: 'a', tool: 't', yolo: true, directory }), 'http://localhost');
  expect(url.searchParams.get('directory')).toBe(directory);
  expect(url.searchParams.get('yolo')).toBe('1');
  expect(url.searchParams.has('persistent')).toBe(false);
});

it('recognizes only explicit supported plugin source paths for deployment', () => {
 const plugin = { id:'probe', name:'Probe', executable:'ruby', arguments:['~/.aelab/plugins/probe.rb'] };
 expect(pluginHasSource(plugin)).toBe(true);
 expect(pluginHasSource({ ...plugin, executable:'~/.aelab/plugins/probe.sh', arguments:[] })).toBe(true);
 expect(pluginHasSource({ ...plugin, arguments:['relative/probe.rb'] })).toBe(false);
 expect(pluginHasSource({ ...plugin, arguments:['--arbitrary'] })).toBe(false);
});

it('labels empty tmux servers without hiding permission, installation or SSH failures', () => {
 const result = { status:1, output:'', error:'error connecting to /private/tmp/tmux-502/default (No such file or directory)\n', truncated:false };
 expect(tmuxSessionMessage(result)).toBe('No active tmux sessions');
 expect(tmuxSessionMessage({ ...result, error:'no server running on /tmp/tmux-1000/default' })).toBe('No active tmux sessions');
 expect(tmuxSessionMessage({ ...result, status:0, error:'' })).toBe('No active tmux sessions');
 for (const [status, error] of [[1,'error connecting to /tmp/tmux-1000/default (Permission denied)'], [127,'tmux: command not found'], [255,'ssh: connect to host example port 22: Connection refused']] as const) {
  expect(tmuxSessionMessage({ ...result, status, error })).toBe(error);
 }
});

it('distinguishes missing Docker CLI, unreachable engine and genuine security errors', () => {
 const result = { status:1, output:'', error:'failed to connect to the docker API at unix:///var/run/docker.sock: dial unix /var/run/docker.sock: connect: no such file or directory', truncated:false };
 expect(serviceDiscoveryMessage('docker', result)).toBe('Docker engine unavailable');
 expect(serviceDiscoveryMessage('docker', { ...result, status:127, error:'zsh:2: command not found: docker' })).toContain('Docker CLI is unavailable');
 for (const error of ['permission denied while trying to connect to the Docker daemon', 'x509: certificate signed by unknown authority', 'unauthorized: authentication required']) expect(serviceDiscoveryMessage('docker', { ...result, error })).toBe(error);
 const ssh = 'ssh: connect to host example port 22: Connection refused';
 expect(serviceDiscoveryMessage('docker', { ...result, status:255, error:ssh })).toBe(ssh);
});
it('renders launchd states conservatively without treating unloaded jobs as healthy', () => {
 const result = { status:0, output:'gui/502/com.example = {\n\tstate = running\n}', error:'', truncated:false };
 expect(launchdState(result)).toBe('running');
 expect(launchdState({ ...result, output:'format changed' })).toBe('unknown');
 expect(launchdState({ ...result, output:'state = not running' })).toBe('stopped');
 expect(launchdState({ ...result, status:113, error:'Could not find service com.example' })).toBe('unloaded');
 expect(launchdState({ ...result, status:1, error:'Operation not permitted' })).toBe('permission-denied');
 expect(launchdState({ ...result, status:124 }, 'running')).toBe('timeout');
});

 it('labels terminals with their project or launch directory without a redundant host suffix', () => {
   const host = { name: 'Dev', projects: [{id:'dotfiles',name:'.dotfiles',dir:'/home/me/.dotfiles'}] } as Host;
   const tools = [{id:'codex',name:'Codex',executable:'codex',arguments:[],directory:'/opt/work/default'}];
   expect(terminalName({project:'dotfiles',tool:'codex'},host,tools)).toBe('Codex@.dotfiles');
   expect(terminalName({project:'dotfiles',tool:'codex'},{...host,name:'local'},tools)).toBe('Codex@.dotfiles');
   expect(terminalTabTitle({project:'dotfiles',tool:'codex'},{...host,name:'local'},tools)).toBe('Codex@.dotfiles.local');
   expect(terminalName({project:'dotfiles'},host,tools)).toBe('shell@.dotfiles');
   expect(terminalName({tool:'codex',directory:'/src/other/'},host,tools)).toBe('Codex@other');
   expect(terminalName({tool:'codex'},host,tools)).toBe('Codex@default');
   expect(terminalName({tool:'codex'},host,tools,'/src/chosen')).toBe('Codex@chosen');
   expect(terminalName({},host,tools,'/home/me')).toBe('shell@me');
   expect(terminalName({session:'saved'},host,tools,'/srv/work')).toBe('saved@work');
   expect(terminalName({},host,tools,'/')).toBe('shell@/');
   expect(terminalName({},host,tools)).toBe('shell@Dev');
 });

import { pinnedLaunch } from './model';
it('opens tmux pins through existing sessions and native pins through retained PTYs', () => {
 expect(pinnedLaunch({host:'local',id:'shortcut',number:2,cwd:'',session:'work'})).toEqual({host:'local',session:'work'});
 expect(pinnedLaunch({host:'remote',id:'pty',number:1,cwd:'/tmp',project:'p'})).toEqual({host:'remote',pinned:'pty',project:'p',tool:undefined});
});

it('derives default names from paths and host connections', () => {
 expect(sourceName('/Users/dev/GitHub/.aelab/')).toBe('.aelab');
 expect(sourceName('/usr/local/bin/codex')).toBe('codex');
 expect(sourceName('~/scripts/probe.swift')).toBe('probe.swift');
 expect(sourceName('gui/502/com.example.agent')).toBe('com.example.agent');
 expect(sourceName('example.service')).toBe('example.service');
 expect(sourceName('')).toBe('');
 expect(hostSourceName('ssh', 'dev@lab.example', '')).toBe('lab.example');
 expect(hostSourceName('daemon', '', 'remote-lab')).toBe('remote-lab');
 expect(hostSourceName('local', '', '')).toBe('localhost');
});

it('preserves independent ALT and YOLO launch flags in terminal links', () => {
 const url = new URL(terminalURL({host:'local',tool:'codex',project:'work',alt:true,yolo:true}), 'http://test');
 expect(url.searchParams.get('alt')).toBe('1');
 expect(url.searchParams.get('yolo')).toBe('1');
 expect(new URL(terminalURL({host:'local',tool:'codex'}), 'http://test').searchParams.has('alt')).toBe(false);
});
