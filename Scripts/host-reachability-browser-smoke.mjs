import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const page = await browser.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  let checks = 0, inventories = 0, release, reachable = true;
  const host = { name: 'Local', transport: 'local', projects: [], services: [], tools: [], plugins: [] };
  await page.route('**/api/**', async route => {
    const path = new URL(route.request().url()).pathname;
    let data = {};
    if (path.endsWith('/auth/session')) data = { csrf: 'fixture' };
    else if (path.endsWith('/config')) data = { revision: 'fixture', config: { version: 1, hosts: [host], tools: [], plugins: [], paths: [], ttyButtons: [] } };
    else if (path.endsWith('/status')) {
      checks++;
      if (checks === 2) await new Promise(resolve => release = resolve);
      data = { host: 'local', reachable, checked: new Date().toISOString(), staleAfterSeconds: 30, connection: { status: reachable ? 0 : 1 }, tmux: { status: 0, output: '' }, curated: {}, discovered: [] };
    } else if (path.endsWith('/terminals')) data = [];
    else if (path.endsWith('/tools')) { inventories++; data = { tools: [] }; }
    else if (path.endsWith('/plugins')) { inventories++; data = []; }
    await route.fulfill({ json: data });
  });
  await page.clock.install();
  await page.goto(process.env.AELAB_TEST_ORIGIN ?? 'http://127.0.0.1:5173');
  const hosts = page.getByRole('region', { name: 'HOSTS', exact: true });
  const badge = hosts.locator('.managed-status .badge');
  await expect(badge).toHaveText('reachable'); // Immediate check on entry.
  expect(checks).toBe(1); expect(inventories).toBe(0);
  const refresh = page.getByRole('button', { name: 'Refresh all hosts', exact: true });
  await refresh.click();
  await expect.poll(() => checks).toBe(2);
  await expect(refresh).toBeDisabled();
  await expect(badge).toHaveText('reachable');
  await page.clock.runFor(15000); // No overlapping automatic check.
  expect(checks).toBe(2);
  reachable = false; release();
  await expect(badge).toHaveText('unreachable');
  await expect(refresh).toBeEnabled();
  await page.getByRole('group', { name: 'Host picker' }).getByRole('button', { name: 'all', exact: true }).click();
  await expect(badge).toHaveText('unreachable');
  expect(checks).toBe(2); // Re-entering All does not immediately repeat a fresh check.
  await page.clock.runFor(15000);
  await expect.poll(() => checks).toBe(3);
  expect(errors).toEqual([]);
  console.log('Host checks: immediate entry, stable labels, no overlap, fresh-result reuse, and polling passed');
} finally { await browser.close(); }
