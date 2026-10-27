// OSC 7501, revision 0.4: https://www.superlogical.com/rex/docs/build/program-status
export type ProgramState = 'idle' | 'working' | 'done' | 'blocked' | 'error';
export type ProgramRecord = { id: string; state: ProgramState; app?: string; title?: string; msg?: string; kind?: string; progress?: number };
type Report = Omit<ProgramRecord, 'state'> & { state: ProgramState | 'clear' };
export const programStatusReply = '\x1b]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth\x1b\\';
const token = /^[A-Za-z0-9_.+-]{1,32}$/;
const encoder = new TextEncoder();

function text(value: string, encodedLimit: number, decodedLimit: number): string {
  if (value.length > encodedLimit || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}(?:==)?|[A-Za-z0-9+/]{3}=?)?$/.test(value)) throw new Error('Invalid base64');
  const bytes = Uint8Array.from(atob(value), char => char.charCodeAt(0));
  if (bytes.length > decodedLimit) throw new Error('Text too long');
  const decoded = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  if (/[\u0000-\u001f\u007f-\u009f]/u.test(decoded)) throw new Error('Control character');
  // Disarm invisible formatting in text rendered outside the terminal grid.
  return decoded.replace(/\p{Cf}/gu, '');
}

export function parseProgramStatus(body: string): Report | undefined {
  // xterm passes only the body, without ESC ] 7501 ; and ST. Use the longer ST.
  if (body.length > 4087 || encoder.encode(body).length + 9 > 4096) return;
  const fields: Record<string, string> = Object.create(null);
  try {
    for (const pair of body.split(':')) {
      const separator = pair.indexOf('=');
      if (separator < 0) continue;
      const key = pair.slice(0, separator).trim(), value = pair.slice(separator + 1).trim();
      if (!/^[a-z]+$/.test(key)) continue;
      // An invalid addressed record must never fall back to overwriting the root.
      if (key === 'id' && !value.split('/').every(segment => token.test(segment))) return;
      if (!/^[A-Za-z0-9_.,+/=-]*$/.test(value)) continue;
      if (key.length > 16) return;
      // Validate every occurrence before applying anything, including overwritten fields.
      if (key === 'msg') text(value, 2732, 2048);
      if (key === 'title') text(value, 256, 192);
      if (key === 'app' && value.length > 32) return;
      if (key === 'id' && (value.length > 128 || value.split('/').length > 8 || value.split('/').some(segment => segment.length > 32))) return;
      fields[key] = value;
    }
    if (!['idle', 'working', 'done', 'blocked', 'error', 'clear'].includes(fields.state)) return;
    if (fields.id !== undefined && !fields.id.split('/').every(segment => token.test(segment))) return;
    const record: Report = { id: fields.id ?? '', state: fields.state as Report['state'] };
    if (token.test(fields.app ?? '')) record.app = fields.app;
    if (fields.title !== undefined) record.title = text(fields.title, 256, 192);
    if (fields.msg !== undefined) record.msg = text(fields.msg, 2732, 2048);
    if (record.state === 'blocked' && ['permission', 'question', 'auth'].includes(fields.kind)) record.kind = fields.kind;
    if (['working', 'blocked'].includes(record.state) && /^\d+$/.test(fields.progress ?? '') && Number(fields.progress) <= 100) record.progress = Number(fields.progress);
    return record;
  } catch { return; }
}

export class ProgramStatusStore {
  private records = new Map<string, ProgramRecord>();
  report(body: string): boolean {
    const report = parseProgramStatus(body);
    if (!report) return false;
    if (report.state === 'clear') {
      for (const id of this.records.keys()) if (!report.id || id === report.id || id.startsWith(report.id + '/')) this.records.delete(id);
    } else {
      this.records.delete(report.id);
      if (this.records.size >= 256) this.records.delete(this.records.keys().next().value!);
      this.records.set(report.id, report as ProgramRecord);
    }
    return true;
  }
  reset() { this.records.clear(); }
  commandFinished() { for (const [id, record] of this.records) if (record.state === 'working' || record.state === 'blocked') this.records.delete(id); }
  acknowledge() { for (const [id, record] of this.records) if (record.state === 'done' || record.state === 'error') this.records.delete(id); }
  snapshot(): ProgramRecord[] {
    const priority: Record<ProgramState, number> = { blocked: 0, error: 1, working: 2, done: 3, idle: 4 };
    return [...this.records.values()].reverse().map(record => {
      let parent = record.id, app = record.app;
      while (!app && parent) { parent = parent.includes('/') ? parent.slice(0, parent.lastIndexOf('/')) : ''; app = this.records.get(parent)?.app; }
      return { ...record, app };
    }).sort((a, b) => priority[a.state] - priority[b.state]);
  }
}

export function programStatusLabel(record: ProgramRecord): string {
  const state = record.state === 'blocked' ? ({ permission: 'approval needed', question: 'answer needed', auth: 'sign-in needed' }[record.kind ?? ''] ?? 'input needed') : record.state;
  return state + (record.progress === undefined ? '' : ` ${record.progress}%`);
}
export function programStatusTone(record: ProgramRecord): string {
  return { idle: 'neutral', working: 'warning', done: 'success', blocked: 'warning', error: 'error' }[record.state];
}
