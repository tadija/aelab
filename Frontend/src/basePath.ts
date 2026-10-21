// The server supplies this at runtime; the same build works at any mount point.
export const basePath = typeof document === 'undefined' ? '' : (document.querySelector('base')?.getAttribute('href') ?? '/').replace(/\/$/, '');
export function appPath(path: string, base = basePath): string { return base + path; }
export function relativePath(path: string, base = basePath): string {
  if (!base) return path;
  if (path === base) return '/';
  return path.startsWith(base + '/') ? path.slice(base.length) : '/';
}
