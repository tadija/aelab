import { it, expect } from 'vitest';
import { decodeLock } from './lockState';
it('restores only validated lock appearance, not authentication data', () => {
  const appearance = { foreground: '#2dd4bf', background: '#15191d', theme: 'dark', fontSize: 24 };
  expect(decodeLock(JSON.stringify({ ...appearance, password: 'never restore', token: 'never restore' }))).toEqual(appearance);
  expect(decodeLock(JSON.stringify({ ...appearance, fontSize: 1000 }))?.fontSize).toBe(64);
});
it('falls back safely when stored lock appearance is absent or corrupt', () => {
  for (const value of [null, '', '{}', '{broken', JSON.stringify({ foreground: 'invalid', background: '#15191d', theme: 'dark' })]) expect(decodeLock(value)).toBeUndefined();
});
