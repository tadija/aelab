export function shortPath(path: string): string {
  if (!path.startsWith('/')) return path;
  return path.split('/').filter(Boolean).slice(-2).join('/') || '/';
}
