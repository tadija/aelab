const wrapKey = 'aelab-editor-wrap';
export function editorWrap(): boolean {
  try { return localStorage.getItem(wrapKey) === '1'; } catch { return false; }
}
export function rememberEditorWrap(value: boolean) {
  try { localStorage.setItem(wrapKey, value ? '1' : '0'); } catch { /* Editing still works when storage is unavailable. */ }
}
