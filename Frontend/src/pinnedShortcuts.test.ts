import { it, expect } from 'vitest';
import { pinnedShortcutAction } from './pinnedShortcuts';

it('opens an unambiguous session number immediately', () => {
  expect(pinnedShortcutAction('1', [1, 2, 3])).toBe('open');
  expect(pinnedShortcutAction('12', [1, 12, 13])).toBe('open');
});
it('waits only while a longer session number remains possible', () => {
  expect(pinnedShortcutAction('1', [1, 12])).toBe('wait');
  expect(pinnedShortcutAction('2', [23])).toBe('wait');
  expect(pinnedShortcutAction('12', [12, 123])).toBe('wait');
});
it('ignores unknown digits instead of scheduling a launch', () => {
  expect(pinnedShortcutAction('9', [1, 12])).toBe('ignore');
  expect(pinnedShortcutAction('14', [1, 12])).toBe('ignore');
});
