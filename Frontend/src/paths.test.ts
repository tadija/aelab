import { it, expect } from 'vitest';
import { shortPath } from './paths';

it('shows the last two absolute path components', () => {
  expect(shortPath('/Users/dev/Developer/GitHub/aelab')).toBe('GitHub/aelab');
  expect(shortPath('/opt/My Tools/bin/')).toBe('My Tools/bin');
  expect(shortPath('/usr')).toBe('usr');
  expect(shortPath('/')).toBe('/');
});
it('keeps executable names and non-absolute labels intact', () => {
  for (const value of ['codex', '~/bin/codex', 'working directory unavailable', '']) expect(shortPath(value)).toBe(value);
});
