import { basePath } from './basePath';
import { DEFAULT_FONT_SIZE, rainFontSize } from './matrix-rain/field';
export const LOCK_KEY = `aelab-lock${basePath ? ':' + basePath : ''}`;
export type LockAppearance = { foreground: string; background: string; theme: 'dark' | 'light'; fontSize: number };
// This stores UI appearance only. Locking never changes the authenticated session.
export function decodeLock(value: string | null): LockAppearance | undefined {
  try {
    const lock = JSON.parse(value ?? 'null');
    if (!lock || !/^#[0-9a-f]{6}$/i.test(lock.foreground) || !/^#[0-9a-f]{6}$/i.test(lock.background) || !['dark', 'light'].includes(lock.theme)) return;
    return { foreground: lock.foreground, background: lock.background, theme: lock.theme, fontSize: rainFontSize(typeof lock.fontSize === 'number' ? lock.fontSize : DEFAULT_FONT_SIZE) };
  } catch { return; }
}
export function storedLock() { try { return decodeLock(localStorage.getItem(LOCK_KEY)); } catch { return; } }
export function rememberLock(lock?: LockAppearance) {
  try { if (lock) localStorage.setItem(LOCK_KEY, JSON.stringify(lock)); else localStorage.removeItem(LOCK_KEY); } catch { /* Authentication never depends on browser storage. */ }
}
