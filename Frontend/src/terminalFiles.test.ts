import { describe, expect, it } from 'vitest';
import { execFileSync } from 'node:child_process';
import { quotedFilePath } from './terminalFiles';

describe('terminal file paste', () => {
  it('keeps paths as one literal shell argument, including shell metacharacters', () => {
    for (const path of ['/tmp/a.png', "/tmp/a ' quoted.png", '/tmp/$(printf INJECTED); a.png', '/tmp/🐈 image.png']) {
      const result = execFileSync('/bin/sh', ['-c', `set -- ${quotedFilePath(path)}; test "$#" = 1 && printf '%s' "$1"`], { encoding: 'utf8' });
      expect(result).toBe(path);
    }
  });
  it('rejects relative paths and terminal control characters', () => {
    for (const path of ['relative.png', '/tmp/bad\nfile', '/tmp/escape\x1b', '/tmp/nul\0']) expect(() => quotedFilePath(path)).toThrow();
  });
});
