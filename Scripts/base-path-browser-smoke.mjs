import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const origin = process.env.AELAB_TEST_ORIGIN, base = '/lab/aelab';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const context = await browser.newContext();
  const page = await context.newPage(), errors = [], requests = [], sockets = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(request.url()));
  page.on('websocket', socket => sockets.push(socket.url()));
  for (const path of ['/health', '/api/auth/session', '/ws/terminals/fake', '/lab/aelab-other/health']) {
    expect((await context.request.get(origin + path)).status()).toBe(404);
  }
  const redirect = await context.request.get(origin + base + '?host=local', { maxRedirects: 0 });
  expect(redirect.status()).toBe(308); expect(redirect.headers().location).toBe(base + '/?host=local');
  for (const path of ['/hosts/local/projects/.aelab', '/hosts/local/projects/.aelab/', '/hosts/lab.example/tools/tool.sh']) {
    const response = await context.request.get(origin + base + path);
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toContain('text/html');
    expect(await response.text()).toContain(`<base href="${base}/">`);
  }
  await page.goto(origin + base + '/hosts/local/');
  await page.getByLabel('Administrator password').fill(process.env.AELAB_TEST_PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Work', exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Work', exact: true })).toHaveAttribute('href', base + '/hosts/local/projects/work/');
  const cookie = (await context.cookies()).find(cookie => cookie.name === 'aelab');
  expect(cookie.path).toBe(base + '/'); expect(cookie.httpOnly).toBe(true);
  expect((await context.request.get(origin + base + '/api/config')).status()).toBe(200);
  const rejected = await context.request.put(origin + base + '/api/config', { data: {}, headers: { Origin: 'https://evil.invalid' } });
  expect(rejected.status()).toBe(403);
  expect((await context.request.put(origin + base + '/api/config', { data: {}, headers: { Origin: origin } })).status()).toBe(403);
  const doc = await context.request.get(origin + base + '/api/docs/openapi.json');
  expect((await doc.json()).servers).toEqual([{ url: base }]);
  const docs = await context.newPage(); await docs.goto(origin + base + '/api/docs');
  await expect(docs.getByRole('link', { name: 'Dashboard', exact: true })).toHaveAttribute('href', base + '/');
  await expect(docs.locator('#routes')).toContainText('/api/hosts'); await docs.close();
  await expect(page.locator('footer a').last()).toHaveAttribute('href', base + '/api/docs');
  const session = await (await context.request.get(origin + base + '/api/auth/session')).json();
  const specification = await (await context.request.get(origin + base + '/api/docs/openapi.json')).json();
  await expect(page.getByLabel('Version', { exact: true })).toHaveText(`${session.version} (${session.build.slice(0, 7)})`);
  expect(session.version).toMatch(/^\d+\.\d+\.\d+/);
  expect(specification.info.version).toBe(session.version);
  expect(specification.info['x-build']).toBe(session.build);
  await expect(page.getByLabel('Version', { exact: true })).toHaveAttribute('title', `Build ${session.build}`);
  await page.reload();
  await expect(page.getByLabel('Version', { exact: true })).toHaveText(`${session.version} (${session.build.slice(0, 7)})`);
  await page.goto(origin + base + '/hosts/local/projects/work/');
  await expect(page.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
  const input = page.locator('.xterm-helper-textarea');
  await input.focus(); await input.pressSequentially('printf \"BASE_PATH_TERMINAL_OK\\n\"'); await input.press('Enter');
  await expect(page.locator('.xterm-rows > div').filter({ hasText: /^BASE_PATH_TERMINAL_OK\s*$/ }).last()).toBeVisible();
  await expect(page.getByRole('button', { name: 'Unpin terminal session', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(page).toHaveURL(new RegExp(base + '/hosts/local/tty/pinned/'));
  await page.reload(); await expect(page.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
  expect(sockets.some(url => url.includes(base + '/ws/terminals/'))).toBe(true);
  expect(requests.filter(url => url.startsWith(origin)).every(url => new URL(url).pathname.startsWith(base + '/'))).toBe(true);
  expect(errors).toEqual([]);
  await page.goto(origin + base + '/hosts/local/');
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await expect(page.getByLabel('Administrator password')).toBeVisible();
  expect((await context.cookies()).some(cookie => cookie.name === 'aelab')).toBe(false);
  console.log('PASS: runtime nested prefix, assets, deep links, login/logout cookie scope, Origin rejection, shared session/API/footer version and real terminal WebSocket');
} finally { await browser.close(); }
