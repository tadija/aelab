import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  const page = await context.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    const stats = window.matrixStats = { pending: new Set(), paints: 0, characters: new Set(), glyphBuilds: 0, fontSize: 0 };
    const request = requestAnimationFrame.bind(window), cancel = cancelAnimationFrame.bind(window);
    window.requestAnimationFrame = callback => { const id = request(time => { stats.pending.delete(id); callback(time); }); stats.pending.add(id); return id; };
    window.cancelAnimationFrame = id => { stats.pending.delete(id); cancel(id); };
    const draw = CanvasRenderingContext2D.prototype.drawImage, text = CanvasRenderingContext2D.prototype.fillText;
    CanvasRenderingContext2D.prototype.drawImage = function (...args) { if (this.canvas.isConnected) stats.paints++; return draw.apply(this, args); };
    CanvasRenderingContext2D.prototype.fillText = function (value, ...args) { stats.characters.add(value); stats.glyphBuilds++; stats.fontSize = Number(/([\d.]+)px/.exec(this.font)?.[1]); return text.call(this, value, ...args); };
  });
  let signedIn = true;
  const password = 'matrix-password0+-';
  await page.route('**/api/**', async route => {
    const path = new URL(route.request().url()).pathname;
    let json = {};
    if (path.endsWith('/auth/session/verify')) { const valid = route.request().postDataJSON().password === password; await route.fulfill({ status: valid ? 200 : 403, json: valid ? { ok: true } : { error: { message: 'Invalid password' } } }); return; }
    if (path.endsWith('/auth/session')) {
      if (route.request().method() === 'DELETE') { signedIn = false; await route.fulfill({ json: { ok: true } }); return; }
      if (route.request().method() === 'POST') signedIn = route.request().postDataJSON().password === password;
      await route.fulfill({ status: signedIn ? 200 : 401, json: signedIn ? { csrf: 'fixture' } : { error: { message: 'Invalid password' } } }); return;
    }
    if (!signedIn) { await route.fulfill({ status: 401, json: { error: { message: 'Authentication required' } } }); return; }
    if (path.endsWith('/config')) json = { revision: 'fixture', config: { version: 1, paths: [], tools: [], plugins: [], ttyButtons: [], hosts: [{ name: 'Local', transport: 'local', tint: '#2b9d6f', projects: [], services: [], tools: [], plugins: [] }] } };
    else if (path.endsWith('/status')) json = { reachable: true, checked: new Date().toISOString(), staleAfterSeconds: 30, hostname: 'matrix-fixture', connection: { status: 0 }, tmux: { status: 0, output: '' }, discovered: [], curated: {} };
    else if (path.endsWith('/terminals')) json = [{ host: 'local', id: 'one', number: 1, cwd: '/tmp/work' }];
    else if (path.endsWith('/tools')) json = { tools: [] };
    else if (path.endsWith('/plugins')) json = [];
    await route.fulfill({ json });
  });
  const origin = process.env.AELAB_TEST_ORIGIN ?? 'http://127.0.0.1:5173';
  await page.goto(origin + '/hosts/local/');
  const start = page.getByRole('button', { name: 'Lock', exact: true });
  await expect(start).toBeVisible();
  await expect(start).toHaveAttribute('title', 'Lock');
  await expect(page.getByRole('button', { name: 'Sign out', exact: true })).toHaveAttribute('title', 'Exit');
  await expect(page.getByRole('button', { name: 'Toggle theme', exact: true })).toHaveAttribute('title', 'Theme');
  expect(await start.evaluate(button => [button.previousElementSibling.getAttribute('aria-label'), button.nextElementSibling.getAttribute('aria-label')])).toEqual(['Configuration', 'Sign out']);
  const screen = page.getByRole('dialog', { name: 'Locked aelab', exact: true });
  const canvas = screen.locator('canvas');
  const signIn = async () => {
    await screen.getByLabel('Administrator password', { exact: true }).fill(password);
    await screen.getByRole('button', { name: 'Sign in', exact: true }).click();
    await expect(screen).toHaveCount(0);
  };
  await start.click(); await expect(screen).toBeVisible();
  await expect(canvas).toHaveCSS('color', 'rgb(43, 157, 111)');
  await expect(canvas).toHaveCSS('background-color', 'rgb(21, 25, 29)');
  await expect.poll(() => page.evaluate(() => window.matrixStats.paints)).toBeGreaterThan(100);
  const frame = await canvas.evaluate(node => node.toDataURL());
  await expect.poll(() => canvas.evaluate(node => node.toDataURL())).not.toBe(frame);
  const alphabet = 'ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789';
  expect((await page.evaluate(() => [...window.matrixStats.characters])).every(char => alphabet.includes(char))).toBe(true);
  // Only the canvas surface remains; shortcuts work without visible chrome.
  expect(await screen.innerText()).toBe('');
  await expect(screen.getByRole('button')).toHaveCount(1);
  await page.keyboard.press('+');
  await expect.poll(() => page.evaluate(() => window.matrixStats.fontSize)).toBe(22);
  await page.keyboard.press('-');
  await expect.poll(() => page.evaluate(() => window.matrixStats.fontSize)).toBe(20);
  await page.keyboard.press('+'); await page.keyboard.press('0');
  await expect.poll(() => page.evaluate(() => window.matrixStats.fontSize)).toBe(20);
  // A viewport-only resize reuses its cached font rather than rebuilding glyphs.
  await page.evaluate(() => document.fonts.ready);
  const builds = await page.evaluate(() => window.matrixStats.glyphBuilds);
  await page.setViewportSize({ width: 900, height: 700 });
  await expect.poll(() => canvas.evaluate(node => Math.round(node.getBoundingClientRect().width))).toBe(900);
  expect(await page.evaluate(() => window.matrixStats.glyphBuilds)).toBe(builds);
  await page.setViewportSize({ width: 1440, height: 900 });
  // The screensaver must consume dashboard shortcuts and contain keyboard focus.
  await page.keyboard.press('1'); expect(context.pages()).toHaveLength(1);
  await page.keyboard.press('Tab'); expect(await page.evaluate(() => !!document.activeElement.closest('dialog'))).toBe(true);
  await page.keyboard.press('Shift+Tab'); expect(await page.evaluate(() => !!document.activeElement.closest('dialog'))).toBe(true);
  // A hidden tab should stop rendering, then resume without a large simulation jump.
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, value: true }); document.dispatchEvent(new Event('visibilitychange')); });
  expect(await page.evaluate(() => window.matrixStats.pending.size)).toBe(0);
  const paused = await page.evaluate(() => window.matrixStats.paints);
  await page.waitForTimeout(100); expect(await page.evaluate(() => window.matrixStats.paints)).toBe(paused);
  await page.evaluate(() => { delete document.hidden; document.dispatchEvent(new Event('visibilitychange')); });
  await expect.poll(() => page.evaluate(() => window.matrixStats.paints)).toBeGreaterThan(paused);
  await screen.locator('.surface').focus();
  await page.screenshot({ path: '/tmp/aelab-matrix-dark.png' });
  for (const [width, height] of [[2560, 1440], [320, 640], [1440, 900]]) {
    await page.setViewportSize({ width, height });
    await expect.poll(() => canvas.evaluate(node => [Math.round(node.getBoundingClientRect().width), Math.round(node.getBoundingClientRect().height)])).toEqual([width, height]);
    expect(await canvas.evaluate(node => node.width * node.height)).toBeLessThan(8_020_000);
    expect(await screen.evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
  }
  await page.keyboard.press('Escape'); await expect(screen).toBeVisible();
  const passwordField = screen.getByLabel('Administrator password', { exact: true });
  await expect(passwordField).toBeFocused();
  await passwordField.pressSequentially('bad0+++');
  expect(await page.evaluate(() => window.matrixStats.fontSize)).toBe(20);
  await page.keyboard.press('Escape'); await expect(passwordField).toHaveCount(0);
  await page.keyboard.press('Escape'); await passwordField.fill('bad0+++');
  await screen.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(screen.getByRole('alert')).toContainText('Invalid password');
  await expect(screen).toBeVisible();
  await page.screenshot({ path: '/tmp/aelab-matrix-lock.png' });
  await signIn(); await expect(start).toBeFocused();
  expect(await page.evaluate(() => window.matrixStats.pending.size)).toBe(0);
  const stopped = await page.evaluate(() => window.matrixStats.paints);
  await page.waitForTimeout(100); expect(await page.evaluate(() => window.matrixStats.paints)).toBe(stopped);
  await page.setViewportSize({ width: 320, height: 640 });
  expect(await page.locator('.topbar').evaluate(header => {
    const brand = header.querySelector('.brand').getBoundingClientRect(), actions = header.querySelector('.actions').getBoundingClientRect();
    return brand.right <= actions.left && actions.right <= innerWidth;
  })).toBe(true);
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.getByRole('button', { name: 'Toggle theme', exact: true }).click();
  await start.click(); await expect(canvas).toHaveCSS('background-color', 'rgb(244, 241, 234)');
  await page.waitForTimeout(250); await page.screenshot({ path: '/tmp/aelab-matrix-light.png' });
  await page.keyboard.press('Escape'); await signIn();
  await start.click(); await screen.locator('.surface').click({ position: { x: 20, y: 200 } });
  await expect(screen.getByLabel('Administrator password', { exact: true })).toBeVisible();
  await signIn(); expect(await page.evaluate(() => window.matrixStats.pending.size)).toBe(0);
  // The renderer can be transplanted without Svelte or any aelab modules.
  await page.evaluate(async () => {
    const { createMatrixRain } = await import('/src/matrix-rain/renderer.ts');
    const canvas = document.createElement('canvas'); canvas.style.cssText = 'width:480px;height:220px;position:fixed;top:0;left:0'; document.body.append(canvas);
    window.standaloneRain = { canvas, controller: createMatrixRain(canvas, { foreground: '#22c55e', background: '#101010', fontSize: 28 }) };
  });
  await expect.poll(() => page.evaluate(() => window.matrixStats.pending.size)).toBe(1);
  await page.evaluate(() => window.standaloneRain.controller.update({ foreground: '#f97316', fontSize: 24 }));
  expect(await page.evaluate(() => getComputedStyle(window.standaloneRain.canvas).color)).toBe('rgb(249, 115, 22)');
  await page.evaluate(() => { window.standaloneRain.controller.destroy(); window.standaloneRain.canvas.remove(); });
  expect(await page.evaluate(() => window.matrixStats.pending.size)).toBe(0);
  expect(errors).toEqual([]);
  console.log('Matrix rain: palette/alphabet, motion, hidden controls, keyboard sizing, glyph caching, viewport coverage, modal isolation, password dismissal/focus, pause/cleanup and standalone reuse passed');
} finally { await browser.close(); }
