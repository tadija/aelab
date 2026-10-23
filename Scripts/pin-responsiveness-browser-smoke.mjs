import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const origin = process.env.AELAB_TEST_ORIGIN, base = '/lab/aelab';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const context = await browser.newContext(), page = await context.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  let holdStatus = false, statusBlocked = false, releaseStatus;
  const statusGate = new Promise(resolve => releaseStatus = resolve);
  const result = { status: 0, output: '', error: '', truncated: false };
  await page.route('**/api/hosts/local/status', async route => {
    if (holdStatus) { statusBlocked = true; await statusGate; }
    await route.fulfill({ json: { host: 'local', hostname: 'pin-fixture', platform: 'linux', reachable: true, checked: new Date().toISOString(), staleAfterSeconds: 60, connection: result, tmux: result, discovered: [], curated: {} } });
  });
  await page.goto(origin + base + '/hosts/local/');
  await page.getByLabel('Administrator password').fill(process.env.AELAB_TEST_PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Work', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Discovery services', exact: true }).click();
  const refresh = page.getByRole('region', { name: 'SERVICES', exact: true }).locator('h2').getByRole('button', { name: 'Refresh services', exact: true });
  await expect(refresh).toBeEnabled();
  holdStatus = true; await refresh.click();
  await expect.poll(() => statusBlocked).toBe(true);

  const shell = await context.newPage();
  let sectionReads = 0;
  shell.on('request', request => { if (request.url().endsWith('/api/state/sections')) sectionReads++; });
  await shell.goto(origin + base + '/hosts/local/tty/');
  await expect(shell.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
  expect(sectionReads).toBe(0);
  const input = shell.locator('.xterm-helper-textarea');
  await input.focus(); await input.pressSequentially("printf 'PIN_READY\\n'"); await input.press('Enter');
  await expect(shell.locator('.xterm-rows > div').filter({ hasText: /^PIN_READY\s*$/ }).last()).toBeVisible();
  await shell.getByRole('button', { name: 'Pin terminal session', exact: true }).click();
  await expect(page.locator('.pinned-row')).toHaveCount(1, { timeout: 1000 });
  await expect(page.locator('.pinned-row .row-title')).toHaveText('shell@aelab');
  await expect(refresh).toBeDisabled(); // Pin updates must not wait for the blocked host probe.
  await expect(shell.getByRole('button', { name: 'Unpin terminal session', exact: true })).toBeVisible();

  await page.bringToFront(); await page.locator('body').click({ position: { x: 5, y: 5 } });
  const popupReady = page.waitForEvent('popup', { timeout: 400 });
  const started = Date.now(); await page.keyboard.press('1');
  const reopened = await popupReady;
  expect(Date.now() - started).toBeLessThan(450);
  await expect(reopened.locator('.terminal-status')).toHaveAttribute('data-status', 'connected', { timeout: 2000 });
  await reopened.close();
  await shell.getByRole('button', { name: 'Unpin terminal session', exact: true }).click();
  await expect(page.locator('.pinned-row')).toHaveCount(0, { timeout: 1000 });
  await shell.getByRole('button', { name: 'Pin terminal session', exact: true }).click();
  await expect(page.locator('.pinned-row')).toHaveCount(1, { timeout: 1000 });
  await input.focus(); await input.pressSequentially('exit'); await input.press('Enter');
  await expect(page.locator('.pinned-row')).toHaveCount(0, { timeout: 1000 });
  const fallback = await context.newPage();
  await fallback.addInitScript(() => Object.defineProperty(window, 'BroadcastChannel', { value: undefined }));
  await fallback.goto(origin + base + '/hosts/local/tty/');
  await expect(fallback.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
  await page.bringToFront();
  await fallback.getByRole('button', { name: 'Pin terminal session', exact: true }).click();
  await expect(page.locator('.pinned-row')).toHaveCount(1, { timeout: 3000 });
  await fallback.getByRole('button', { name: 'Unpin terminal session', exact: true }).click();
  await expect(page.locator('.pinned-row')).toHaveCount(0, { timeout: 3000 });
  await fallback.close();
  releaseStatus();
  expect(errors).toEqual([]);
  console.log('PASS: pin/unpin/exit invalidate dashboard within one second despite blocked host probes; two-second fallback without cross-tab messaging; unambiguous keyboard launch skips delay and terminal pages skip section reads');
} finally { await browser.close(); }
