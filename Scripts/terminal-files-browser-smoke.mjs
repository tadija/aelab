import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
import { readFileSync, statSync } from 'node:fs';
const origin = process.env.AELAB_TEST_ORIGIN, base = '/lab/aelab', homes = JSON.parse(process.env.AELAB_TEST_UPLOAD_HOMES);
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=', 'base64');
try {
  const context = await browser.newContext(), page = await context.newPage(), errors = [];
  context.on('page', page => page.on('pageerror', e => errors.push(e.message)));
  await page.goto(origin + base + '/hosts/local/');
  await page.getByLabel('Administrator password').fill(process.env.AELAB_TEST_PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Lock', exact: true })).toBeVisible();
  const session = await (await context.request.get(origin + base + '/api/auth/session')).json();
  const headers = { Origin: origin, 'X-CSRF-Token': session.csrf };
  async function drop(target, files, paste = false) {
    const transfer = await target.evaluateHandle(files => {
      const data = new DataTransfer();
      for (const file of files) data.items.add(new File([Uint8Array.from(file.bytes)], file.name, { type: file.type || 'application/octet-stream' }));
      return data;
    }, files.map(file => ({ ...file, bytes: Array.from(file.bytes) })));
    if (paste) await target.locator('.xterm-helper-textarea').evaluate((node, data) => node.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true })), transfer);
    else await target.locator('.terminal-container').dispatchEvent('drop', { dataTransfer: transfer });
    await transfer.dispose();
  }
  let localID;
  for (const host of ['local', 'ssh', 'daemon']) {
    const tty = await context.newPage(); let id;
    tty.on('websocket', socket => socket.on('framereceived', frame => { try { const value = JSON.parse(String(frame.payload)); if (value.type === 'terminal') id = value.id; } catch {} }));
    await tty.goto(`${origin}${base}/hosts/${host}/tty/`);
    await expect(tty.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
    await expect.poll(() => id).toBeTruthy(); if (host === 'local') localID = id;
    const input = tty.locator('.xterm-helper-textarea'), rows = tty.locator('.xterm-rows');
    const name = "a ' literal; $(echo BAD).txt", bytes = Buffer.concat([Buffer.from('native file transfer\n'), Buffer.alloc(180000)]);
    await input.focus(); await input.pressSequentially("printf 'FILE_BYTES:'; wc -c < ");
    const response = tty.waitForResponse(response => response.url().includes(`/terminals/${id}/files?`));
    await drop(tty, [{ name, bytes }]);
    const uploaded = await (await response).json();
    expect(uploaded.path.startsWith(homes[host]+'/.aelab/uploads/')).toBe(true);
    expect(uploaded.name).toBe(name); expect(readFileSync(uploaded.path).equals(bytes)).toBe(true);
    expect(statSync(uploaded.path).mode & 0o777).toBe(0o600);
    await expect(tty.getByRole('status')).toHaveCount(0);
    await expect(rows.locator('> div').filter({ hasText: new RegExp(`^FILE_BYTES:\\s*${bytes.length}\\s*$`) })).toHaveCount(0);
    await input.press('Enter');
    await expect(rows.locator('> div').filter({ hasText: new RegExp(`^FILE_BYTES:\\s*${bytes.length}\\s*$`) }).last()).toHaveCount(1);
    await input.pressSequentially("printf 'FILE_COUNT:'; set -- ");
    const uploads = [];
    const record = async response => { if (response.url().includes(`/terminals/${id}/files?`)) uploads.push(await response.json()); };
    tty.on('response', record);
    await drop(tty, [{ name: 'one.txt', bytes: Buffer.from('one') }, { name: 'two.txt', bytes: Buffer.from('two') }]);
    await expect.poll(() => uploads.length).toBe(2);
    await expect(tty.getByRole('button', { name: 'Cancel upload', exact: true })).toHaveCount(0);
    tty.off('response', record);
    await input.pressSequentially('; printf \'%s\\n\' "$#"'); await input.press('Enter');
    await expect(rows.locator('> div').filter({ hasText: /^FILE_COUNT:2\s*$/ }).last()).toHaveCount(1);
    // Text paste still reaches the running shell normally.
    const textPaste = await tty.evaluateHandle(() => { const data = new DataTransfer(); data.setData('text/plain', "printf 'TEXT_PASTE_OK\\n'"); return data; });
    await input.evaluate((node, data) => node.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true })), textPaste);
    await textPaste.dispose(); await input.press('Enter');
    await expect(rows.locator('> div').filter({ hasText: /^TEXT_PASTE_OK\s*$/ }).last()).toHaveCount(1);
    // Native TUI receives a single bracketed image path and creates the placeholder itself.
    const probe = await context.newPage(); await probe.goto(`${origin}${base}/hosts/${host}/tools/attachment-probe/`);
    await expect(probe.locator('.xterm-rows')).toContainText('PROBE_READY');
    await probe.getByRole('button', { name: 'Show key bar', exact: true }).click();
    await probe.getByRole('button', { name: 'Alt', exact: true }).click();
    await drop(probe, [{ name: 'an image.png', bytes: png, type: 'image/png' }]);
    await expect(probe.locator('.xterm-rows')).toContainText('[Image #1]');
    const pasteResponse = probe.waitForResponse(response => response.url().includes('/files?'), { timeout: 8000 });
    await drop(probe, [{ name: 'screenshot.png', bytes: png, type: 'image/png' }], true);
    const pasteUpload = await pasteResponse.catch(async error => { console.log('Paste errors', await probe.locator('.error').allTextContents()); throw error; });
    expect(pasteUpload.status()).toBe(200);
    await expect(probe.locator('.xterm-rows')).toContainText('[Image #2]');
    // Exercise the key-bar image reader without touching the machine's real clipboard.
    await probe.evaluate(bytes => Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
      read: async () => [{ types: ['image/png'], getType: async () => new Blob([Uint8Array.from(bytes)], { type: 'image/png' }) }],
      readText: async () => ''
    } }), Array.from(png));
    await probe.getByRole('button', { name: 'Paste', exact: true }).click();
    await expect(probe.locator('.xterm-rows')).toContainText('[Image #3]');
    await expect(probe.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
    await probe.close();
    // Authorization and filename validation precede upload writes.
    const endpoint = `${origin}${base}/api/hosts/${host}/terminals/${id}/files?name=file.txt`;
    expect((await context.request.post(endpoint, { headers: { Origin: origin }, data: 'x' })).status()).toBe(403);
    expect((await context.request.post(endpoint, { headers: { ...headers, Origin: 'https://invalid.example' }, data: 'x' })).status()).toBe(403);
    expect((await context.request.post(endpoint.replace('name=file.txt', 'name=..%2Fescape'), { headers, data: 'x' })).status()).toBe(400);
    expect((await context.request.post(endpoint.replace(`/hosts/${host}/`, `/hosts/${host === 'local' ? 'ssh' : 'local'}/`), { headers, data: 'x' })).status()).toBe(400);
    if (host === 'local') {
      expect((await context.request.post(endpoint, { headers, data: Buffer.alloc(20 * 1024 * 1024 + 1) })).status()).toBe(413);
      let hold;
      const pending = new Promise(resolve => hold = resolve);
      await tty.route('**/files?*', async route => { await pending; await route.abort().catch(() => {}); });
      await drop(tty, [{ name: 'cancel.txt', bytes }]);
      await expect(tty.getByRole('button', { name: 'Cancel upload', exact: true })).toBeVisible();
      await tty.getByRole('button', { name: 'Cancel upload', exact: true }).click(); hold();
      await expect(tty.getByRole('button', { name: 'Cancel upload', exact: true })).toHaveCount(0);
      await expect(tty.locator('.terminal-status')).toHaveAttribute('data-status', 'connected');
    }
    await tty.close();
    expect(readFileSync(uploaded.path).equals(bytes)).toBe(true); // Files survive temporary terminal closure too.
  }
  const anonymous = await browser.newContext();
  expect((await anonymous.request.post(`${origin}${base}/api/hosts/local/terminals/${localID}/files?name=x`, { headers: { Origin: origin }, data: 'x' })).status()).toBe(401);
  await anonymous.close();
  expect(errors).toEqual([]);
  console.log('PASS: local/SSH/daemon file drop, screenshot paste, native image placeholders, shell quoting, private byte-exact files, ownership/Origin/CSRF/size validation, cancellation and terminal continuity');
} finally { await browser.close(); }
