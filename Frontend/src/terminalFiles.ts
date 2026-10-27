import { appPath } from './basePath';

export const maximumFileSize = 20 * 1024 * 1024;
export const maximumFileBatch = 10;
export type UploadedFile = { name: string; path: string; size: number };
export function quotedFilePath(path: string): string {
  if (!path.startsWith('/') || /[\x00-\x1f\x7f]/.test(path)) throw new Error('Invalid uploaded file path');
  return `'${path.replace(/'/g, "'\\''")}'`;
}
export function clipboardImageName(type: string): string {
  const extension: Record<string, string> = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif', 'image/bmp': 'bmp', 'image/avif': 'avif', 'image/tiff': 'tiff', 'image/svg+xml': 'svg' };
  return `pasted-image-${Date.now()}.${extension[type] ?? 'bin'}`;
}
export function uploadTerminalFile(host: string, terminal: string, file: File, csrf: string, signal: AbortSignal, progress: (percent: number) => void): Promise<UploadedFile> {
  if (file.size > maximumFileSize) return Promise.reject(new Error(`${file.name}: files must be at most 20 MiB`));
  return new Promise((resolve, reject) => {
    if (signal.aborted) { reject(new DOMException('Upload cancelled', 'AbortError')); return; }
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    const finish = () => signal.removeEventListener('abort', abort);
    xhr.open('POST', appPath(`/api/hosts/${encodeURIComponent(host)}/terminals/${encodeURIComponent(terminal)}/files?name=${encodeURIComponent(file.name)}`));
    xhr.setRequestHeader('Content-Type', 'application/octet-stream'); xhr.setRequestHeader('X-CSRF-Token', csrf);
    xhr.timeout = 180000;
    xhr.upload.onprogress = event => { if (event.lengthComputable) progress(event.total ? Math.round(event.loaded / event.total * 100) : 100); };
    xhr.onload = () => {
      finish();
      try {
        const result = JSON.parse(xhr.responseText);
        if (xhr.status < 200 || xhr.status >= 300) throw new Error(result.error?.message ?? 'File transfer failed');
        if (typeof result.path !== 'string' || typeof result.name !== 'string' || result.size !== file.size) throw new Error('Invalid file transfer response');
        quotedFilePath(result.path); resolve(result);
      } catch (error) { reject(error); }
    };
    xhr.onerror = () => { finish(); reject(new Error('File transfer failed; check the connection')); };
    xhr.ontimeout = () => { finish(); reject(new Error('File transfer timed out')); };
    xhr.onabort = () => { finish(); reject(new DOMException('Upload cancelled', 'AbortError')); };
    signal.addEventListener('abort', abort, { once: true });
    xhr.send(file);
  });
}
