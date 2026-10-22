import { describe, it, expect } from 'vitest';
import { parseProgramStatus, ProgramStatusStore, programStatusLabel, type ProgramRecord } from './programStatus';
const base64 = (value: string) => btoa(String.fromCharCode(...new TextEncoder().encode(value)));
describe('OSC 7501 program status', () => {
  it('decodes UTF-8, optional padding, all states and contextual fields', () => {
    const report = parseProgramStatus(`state=blocked:kind=permission:progress=42:app=deploy:title=${base64('Déployer').replace(/=+$/, '')}:msg=${base64('Approve?')}`)!;
    expect(report).toEqual({ id: '', state: 'blocked', kind: 'permission', progress: 42, app: 'deploy', title: 'Déployer', msg: 'Approve?' });
    expect(programStatusLabel(report as ProgramRecord)).toBe('approval needed 42%');
    for (const state of ['idle', 'working', 'done', 'blocked', 'error', 'clear']) expect(parseProgramStatus(`state=${state}`)?.state).toBe(state);
    expect(parseProgramStatus('state=done:progress=42:kind=permission')).toEqual({ id: '', state: 'done' });
    expect(parseProgramStatus('state=working:progress=101:app=bad/app')).toEqual({ id: '', state: 'working' });
  });
  it('skips malformed and unknown pairs, trims whitespace, and uses the last repeated key', () => {
    expect(parseProgramStatus('state=working:bad:noise=ok:state = done:msg=%%%:kind=bad;value')).toEqual({ id: '', state: 'done' });
    expect(parseProgramStatus('state=future')).toBeUndefined();
    expect(parseProgramStatus('app=deploy')).toBeUndefined();
    expect(parseProgramStatus('?')).toBeUndefined();
    expect(parseProgramStatus('?:states=idle,working,done,blocked,error')).toBeUndefined();
  });
  it('rejects invalid UTF-8, base64 and controls, and removes invisible formatting', () => {
    for (const value of ['A', 'ab=c', '/w==', base64('bad\ntext'), base64('bad\u009ftext')]) expect(parseProgramStatus(`state=done:msg=${value}`)).toBeUndefined();
    expect(parseProgramStatus(`state=done:title=${base64('safe\u202etext')}`)?.title).toBe('safetext');
    expect(parseProgramStatus(`state=done:msg=${base64('bad\n')}:msg=${base64('good')}`)).toBeUndefined();
  });
  it('enforces every size limit without mutating stored records', () => {
    const store = new ProgramStatusStore(); store.report('state=working');
    for (const body of [
      `state=done:msg=${base64('x'.repeat(2049))}`, `state=done:title=${base64('x'.repeat(193))}`,
      `state=done:app=${'a'.repeat(33)}`, `state=done:${'k'.repeat(17)}=v`,
      `state=done:id=${'a'.repeat(33)}`, `state=done:id=${Array(9).fill('a').join('/')}`,
      `state=done:id=${Array(5).fill('a'.repeat(26)).join('/')}`, `state=done:unknown=${'x'.repeat(4096)}`,
    ]) { expect(store.report(body)).toBe(false); expect(store.snapshot()[0].state).toBe('working'); }
    expect(parseProgramStatus(`state=working:msg=${base64('x'.repeat(2048))}:title=${base64('x'.repeat(192))}`)).toBeDefined();
  });
  it('never lets a malformed id overwrite the root', () => {
    const store = new ProgramStatusStore(); store.report('state=working');
    for (const id of ['', '/a', 'a/', 'a//b', 'a,b', 'bad!id']) expect(store.report(`state=clear:id=${id}`)).toBe(false);
    expect(store.snapshot()).toEqual([{ id: '', state: 'working', app: undefined }]);
  });
  it('replaces records, inherits the nearest app, and prioritizes actionable children', () => {
    const store = new ProgramStatusStore();
    store.report('state=working:app=deploy'); store.report('state=idle:id=build:app=builder');
    store.report('state=blocked:id=build/test:kind=question');
    expect(store.snapshot()[0]).toMatchObject({ id: 'build/test', app: 'builder', state: 'blocked' });
    store.report('state=done:id=build');
    expect(store.snapshot()[0].app).toBe('deploy');
    expect(store.snapshot().find(record => record.id === 'build')).not.toHaveProperty('kind');
  });
  it('clears descendants with path boundaries and preserves unrelated siblings', () => {
    const store = new ProgramStatusStore();
    for (const id of ['build', 'build/test', 'builder', 'other/test']) store.report(`state=working:id=${id}`);
    store.report('state=clear:id=build');
    expect(store.snapshot().map(record => record.id)).toEqual(['other/test', 'builder']);
    store.report('state=clear'); expect(store.snapshot()).toEqual([]);
  });
  it('expires busy records at prompts/exit, retains results until acknowledged, and resets all records', () => {
    const store = new ProgramStatusStore();
    for (const state of ['working', 'blocked', 'done', 'error', 'idle']) store.report(`state=${state}:id=${state}`);
    store.commandFinished(); expect(store.snapshot().map(record => record.state)).toEqual(['error', 'done', 'idle']);
    store.acknowledge(); expect(store.snapshot().map(record => record.state)).toEqual(['idle']);
    store.reset(); expect(store.snapshot()).toEqual([]);
  });
  it('evicts the least recently updated record at the cap', () => {
    const store = new ProgramStatusStore();
    for (let i = 0; i < 256; i++) store.report(`state=working:id=r${i}`);
    store.report('state=done:id=r0'); store.report('state=working:id=new');
    expect(store.snapshot()).toHaveLength(256);
    expect(store.snapshot().some(record => record.id === 'r1')).toBe(false);
    expect(store.snapshot().some(record => record.id === 'r0')).toBe(true);
  });
});
