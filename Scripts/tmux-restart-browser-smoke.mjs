import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const origin = process.env.AELAB_TEST_ORIGIN, base = '/lab/aelab';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const context = await browser.newContext(), page = await context.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(origin + base + '/hosts/local/');
  await page.getByLabel('Administrator password').fill(process.env.AELAB_TEST_PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'pin-work', exact: true })).toBeVisible();
  if (process.env.AELAB_TEST_PHASE === 'before') {
    await page.getByRole('button', { name: 'Host launch menu', exact: true }).click();
    const shellOpened = page.waitForEvent('popup'); await page.getByRole('button', { name: 'Shell', exact: true }).click();
    const shell = await shellOpened;
    await expect(shell.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
    await shell.getByRole('button', { name: 'Pin terminal session', exact: true }).click();
    await expect(shell.getByRole('button', { name: 'Unpin terminal session', exact: true })).toBeVisible();
    const opened = page.waitForEvent('popup'); await page.getByRole('link', { name: 'pin-work', exact: true }).click();
    const tmux = await opened;
    await expect(tmux.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
    await tmux.getByRole('button', { name: 'Pin terminal session', exact: true }).click();
    await expect(tmux.getByRole('button', { name: 'Unpin terminal session', exact: true })).toBeVisible();
    const pins = await (await context.request.get(origin + base + '/api/hosts/local/terminals')).json();
    expect(pins).toHaveLength(2); expect(pins.find(pin => pin.session)?.number).toBe(2);
  } else {
    const pins = await (await context.request.get(origin + base + '/api/hosts/local/terminals')).json();
    expect(pins).toHaveLength(1);
    expect(pins[0]).toMatchObject({ id: process.env.AELAB_TEST_PIN_ID, number: Number(process.env.AELAB_TEST_PIN_NUMBER), session: 'pin-work' });
    await expect(page.locator('.host-shells .pin-number')).toHaveText('2');
    await page.locator('body').click({ position: { x: 5, y: 5 } });
    const opened = page.waitForEvent('popup'); await page.keyboard.press('2'); const tty = await opened;
    await expect(tty.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
    expect(tty.url()).toContain('/tty/tmux/pin-work/');
    await tty.getByRole('button', { name: 'Unpin terminal session', exact: true }).click();
    await expect(tty.getByRole('button', { name: 'Pin terminal session', exact: true })).toBeVisible();
    await expect(page.locator('.host-shells .pin-number')).toHaveCount(0);
    await expect(page.getByRole('link', { name: 'pin-work', exact: true })).toBeVisible();
    console.log('Restart restores only tmux pins with stable IDs/numbers, working shortcuts and persistent unpinning');
  }
  expect(errors).toEqual([]);
} finally { await browser.close(); }
