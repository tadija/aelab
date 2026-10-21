import { describe, expect, it } from 'vitest';
import { keySequence } from './terminalKeys';
describe('terminal buttons', () => {
  it('sends native control keys and shifted navigation', () => {
    expect(keySequence('ctrl-c')).toBe('\x03'); expect(keySequence('ctrl-z')).toBe('\x1a');
    expect(keySequence('tab', true)).toBe('\x1b[Z'); expect(keySequence('up', true)).toBe('\x1b[1;2A');
    expect(keySequence('enter')).toBe('\r'); expect(keySequence('unknown')).toBeUndefined();
  });
  it('uses each host tmux prefix', () => {
    expect(keySequence('tmux-zoom', false, '\x01')).toBe('\x01z');
    expect(keySequence('tmux-mouse', false, '\x02')).toBe('\x02m');
    expect(keySequence('tmux-split-horizontal', false, '\x01')).toBe('\x01%');
  });
});
