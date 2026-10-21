import { describe, expect, it } from 'vitest';
import { appPath, relativePath } from './basePath';
describe('runtime mount paths', () => {
  it('mounts API, navigation and WebSocket paths without changing query strings', () => {
    for (const path of ['/api/config?format=source', '/hosts/a/tty/', '/ws/terminals/ticket']) {
      expect(appPath(path, '/lab/aelab')).toBe('/lab/aelab' + path);
      expect(relativePath(appPath(path, '/lab/aelab'), '/lab/aelab')).toBe(path);
      expect(appPath(path, '')).toBe(path);
    }
  });
  it('uses segment boundaries when removing a prefix', () => {
    expect(relativePath('/aelab-other/hosts/a/', '/aelab')).toBe('/');
    expect(relativePath('/aelab', '/aelab')).toBe('/');
  });
});
