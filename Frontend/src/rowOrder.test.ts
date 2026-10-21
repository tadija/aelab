import { expect, it } from 'vitest';
import { moveRow } from './rowOrder';

it('moves in either direction without changing identifiers or item contents', () => {
  const rows = [{ id: 'a', name: 'First' }, { id: 'b', name: 'Second' }, { id: 'c', name: 'Third' }];
  const original = [...rows];
  expect(moveRow(rows, 'a', 'c')).toBe(true);
  expect(rows.map(row => row.id)).toEqual(['b', 'c', 'a']);
  expect(moveRow(rows, 'a', 'b')).toBe(true);
  expect(rows).toEqual(original);
  expect(rows[0]).toBe(original[0]);
});
it('preserves hidden entries and refuses removed or unchanged targets', () => {
  const rows = ['a', 'hidden-1', 'b', 'hidden-2', 'c'].map(id => ({ id }));
  expect(moveRow(rows, 'c', 'a')).toBe(true);
  expect(rows.map(row => row.id)).toEqual(['c', 'a', 'hidden-1', 'b', 'hidden-2']);
  const original = [...rows];
  for (const [id, target] of [['c','c'], ['removed','a'], ['a','removed']]) expect(moveRow(rows, id, target)).toBe(false);
  expect(rows).toEqual(original);
});
