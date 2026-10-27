// Runs against the isolated server created by smoke.py. No real host operations.
import { spawn } from 'node:child_process';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
const origin = process.env.AELAB_TEST_ORIGIN;
const password = process.env.AELAB_TEST_PASSWORD;
const executablePath = process.env.AELAB_TEST_BROWSER;
const browser = await chromium.launch({ ...(executablePath ? { executablePath } : {}), headless: true });
let replacementServer;
try {
  const context = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  const identify = config => {
    const entity = item => { Object.defineProperty(item, 'id', { get: () => item.name.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, ''), enumerable: false }); };
    for (const item of [...config.tools, ...config.plugins, ...config.hosts]) entity(item);
    for (const host of config.hosts) for (const item of [...host.projects, ...host.services]) entity(item);
    return config;
  };
  const configSnapshot = async () => { const snapshot = await (await page.request.get(`${origin}/api/config`)).json(); identify(snapshot.config); return snapshot; };
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.goto(origin);
  await expect(page.locator('.login .brand svg circle')).toHaveCount(2);
  await expect(page.getByLabel('Administrator password')).toBeFocused();
  await page.reload();
  await expect(page.getByLabel('Administrator password')).toBeFocused();
  await page.getByLabel('Administrator password').fill(password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await page.getByRole('button', { name: 'Check all' }).waitFor();
  const reference = await context.newPage();
  await reference.goto(`${origin}/api/docs`);
  await expect(reference.locator('details').first()).toBeVisible();
  await expect(reference.locator('html')).toHaveCSS('background-color', 'rgb(21, 25, 29)');
  await reference.getByRole('button', { name: 'Toggle theme', exact: true }).click();
  await expect(reference.locator('html')).toHaveCSS('background-color', 'rgb(244, 241, 234)');
  await reference.reload();
  await expect(reference.locator('html')).toHaveCSS('background-color', 'rgb(244, 241, 234)');
  await reference.locator('#routes > details.route-group > summary').filter({ hasText: /^\/api\/docs$/ }).click();
  await reference.locator('summary').filter({ hasText: /^GET\s*\/api\/docs$/ }).click();
  await expect(reference.locator('details pre:visible').first()).toBeVisible();
  const hostsAPI = reference.locator('#routes > details.route-group').filter({ has: reference.locator(':scope > summary', { hasText: /^\/api\/hosts\/\{host\}$/ }) });
  await expect(hostsAPI.locator(':scope > summary')).toHaveText('/api/hosts/{host}');
  await expect(hostsAPI).toHaveJSProperty('open', false);
  const schema = await (await reference.request.get(`${origin}/api/docs/openapi.json`)).json();
  for (const prefix of ['/api/auth', '/api/config', '/api/state', '/api/docs']) {
    const section = reference.locator('#routes > details.route-group').filter({ has: reference.locator(':scope > summary', { hasText: new RegExp(`^${prefix}$`) }) });
    await expect(section).toHaveCount(1);
    const count = Object.entries(schema.paths).filter(([path]) => path === prefix || path.startsWith(`${prefix}/`)).reduce((sum, [, methods]) => sum + Object.keys(methods).length, 0);
    await expect(section.locator('details:not(.route-group)')).toHaveCount(count);
    await expect(section).toHaveJSProperty('open', prefix === '/api/docs');
  }
  const hostOperations = Object.entries(schema.paths).filter(([path]) => path.startsWith('/api/hosts/{host}/')).reduce((sum, [, methods]) => sum + Object.keys(methods).length, 0);
  await expect(hostsAPI.locator('details:not(.route-group)')).toHaveCount(hostOperations);
  await hostsAPI.locator(':scope > summary').click();
  await expect(hostsAPI.locator(':scope > div > details > summary')).toHaveText(['Host & discovery', 'Plugins', 'Services', 'Shells']);
  await hostsAPI.getByText('Plugins', { exact: true }).click();
  await hostsAPI.locator('summary').filter({ hasText: /^GET\s*\/api\/hosts\/\{host\}\/plugins$/ }).click();
  await expect(hostsAPI.locator('pre:visible')).toContainText('responses');
  await reference.screenshot({ path: '/tmp/aelab-api-colors.png' });
  await reference.getByRole('button', { name: 'Toggle theme', exact: true }).click();
  await reference.close();
  await page.getByRole('button', { name: 'Add host' }).click();
  await page.getByLabel('Name', { exact: true }).fill('Browser fixture');
  await page.getByLabel('Approved SSH alias / user@address').fill('browser-fixture');
  await page.getByRole('dialog', { name: 'Configure host' }).getByLabel('Host tint').evaluate(element => { element.value = '#8b5cf6'; element.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await page.getByRole('button', { name: 'Browser fixture', exact: true }).waitFor();
  const createdConfig = (await configSnapshot()).config;
  if (createdConfig.hosts.find(h => h.id === 'browser-fixture').tint !== '#8b5cf6') throw new Error('Host form tint did not persist');
  const overview = page.getByRole('region', { name: 'HOSTS', exact: true });
  const hostRow = overview.locator('li').filter({ hasText: 'browser-fixture' });
  await hostRow.getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Configure host' }).getByLabel('Host tint')).toHaveValue('#8b5cf6');
  await page.evaluate(() => { localStorage.setItem('aelab-theme:browser-fixture', 'light'); localStorage.setItem('aelab-tty-cwd-background:browser-fixture:/tmp', '#123456'); });
  await page.getByLabel('Name', { exact: true }).fill('Renamed fixture');
  await page.getByRole('dialog', { name: 'Configure host' }).getByLabel('Host tint').evaluate(element => { element.value = '#c2410c'; element.dispatchEvent(new Event('input', { bubbles: true })); });
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Configure host' })).toBeHidden();
  if (!(await configSnapshot()).config.hosts.some(h => h.id === 'renamed-fixture' && h.name === 'Renamed fixture')) throw new Error('Editing a name did not change its derived ID');
  expect(await page.evaluate(() => [localStorage.getItem('aelab-theme:renamed-fixture'), localStorage.getItem('aelab-tty-cwd-background:renamed-fixture:/tmp')])).toEqual(['light', '#123456']);
  await expect(hostRow.locator('.row-title')).toHaveCSS('color', 'rgb(194, 65, 12)');
  const contextConfig = await configSnapshot(); contextConfig.config.hosts.find(host => host.id === 'renamed-fixture').dockerContext = 'desktop-linux';
  const contextCSRF = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
  const contextSaved = await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': contextCSRF }, data: contextConfig });
  if (!contextSaved.ok()) throw new Error(await contextSaved.text());
  await page.reload(); await hostRow.getByRole('button', { name: 'Edit', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Configure host' }).getByLabel('Docker context (optional)', { exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Configure host' })).toBeHidden();
  if (!(await configSnapshot()).config.hosts.some(host => host.id === 'renamed-fixture' && host.dockerContext === 'desktop-linux')) throw new Error('Docker context did not persist');
  await expect(hostRow.locator('.badge')).toHaveCSS('text-transform', 'uppercase');
  const dragPlacement = await hostRow.evaluate(row => {
    const handle = row.querySelector('.reorder-control');
    const before = row.getBoundingClientRect(), corner = handle.getBoundingClientRect();
    handle.style.display = 'none'; const without = row.getBoundingClientRect().height; handle.style.display = '';
    return { height: before.height, without, right: before.right - corner.right, bottom: before.bottom - corner.bottom };
  });
  expect(dragPlacement.height).toBe(dragPlacement.without);
  expect(dragPlacement.right).toBeGreaterThan(0); expect(dragPlacement.right).toBeLessThan(16);
  expect(dragPlacement.bottom).toBeGreaterThan(0); expect(dragPlacement.bottom).toBeLessThan(16);
  page.once('dialog', dialog => dialog.accept());
  await hostRow.getByRole('button', { name: 'Delete host Renamed fixture' }).click();
  await expect(hostRow).toHaveCount(0);
  await page.getByRole('button', { name: 'Configuration', exact: true }).click();
  const editor = page.getByRole('dialog', { name: 'Main configuration', exact: true });
  const text = editor.getByLabel('Main configuration JSON');
  await expect(text).not.toHaveValue('');
  const sourceText = await text.inputValue();
  const savedWrap = editor.getByRole('button', { name: 'Wrap lines', exact: true });
  await savedWrap.click();
  await editor.getByRole('button', { name: 'Close', exact: true }).click();
  await page.reload();
  await page.getByRole('button', { name: 'Configuration', exact: true }).click();
  await expect(savedWrap).toHaveAttribute('aria-pressed', 'true');
  await savedWrap.click();
  await expect(savedWrap).toHaveAttribute('aria-pressed', 'false');
  await expect(editor.locator('.json-key').first()).toBeVisible();
  await expect(editor.locator('.json-gutter > div')).toHaveCount(sourceText.split('\n').length);
  const folding = editor.getByRole('button', { name: /^Fold lines / });
  await expect(folding.first()).toBeVisible();
  await folding.first().click();
  await expect(editor.getByRole('region', { name: 'Folded configuration preview' })).toBeVisible();
  await expect(editor.getByRole('button', { name: 'Save', exact: true })).toBeDisabled();
  await page.screenshot({ path: '/tmp/aelab-config-folded.png' });
  await editor.getByRole('button', { name: 'Expand all to edit', exact: true }).click();
  await expect(text).toHaveValue(sourceText);
  await text.evaluate(element => { element.scrollTop = 150; element.dispatchEvent(new Event('scroll')); });
  await expect.poll(() => editor.locator('.json-gutter').evaluate(element => element.scrollTop)).toBeGreaterThan(0);
  await text.evaluate(element => { element.scrollTop = 0; element.dispatchEvent(new Event('scroll')); });

  const wrapButton = editor.getByRole('button', { name: 'Wrap lines', exact: true });
  const longText = sourceText + '\n' + 'long-unbroken-value'.repeat(60);
  await text.fill(longText);
  await wrapButton.click(); await expect(wrapButton).toHaveAttribute('aria-pressed', 'true');
  await expect(text).toHaveValue(longText);
  await expect.poll(() => editor.locator('.json-gutter > div').last().evaluate(element => element.getBoundingClientRect().height)).toBeGreaterThan(40);
  await expect.poll(() => text.evaluate(element => element.scrollWidth - element.clientWidth)).toBeLessThan(2);
  await wrapButton.click(); await expect(text).toHaveValue(longText);
  await expect.poll(() => editor.locator('.json-gutter > div').last().evaluate(element => element.getBoundingClientRect().height)).toBeLessThan(25);
  await text.fill(sourceText);
  await page.screenshot({ path: '/tmp/aelab-config-lines.png' });
  await text.fill('{ invalid JSON'); await editor.getByRole('button', { name: 'Validate', exact: true }).click();
  await expect(editor.getByRole('alert')).toBeVisible();
  await text.fill(sourceText + '\n');
  await editor.getByRole('button', { name: 'Validate', exact: true }).click();
  await expect(editor.getByRole('status')).toContainText('Configuration valid');
  const concurrent = (await configSnapshot());
  concurrent.config.hosts.find(h => h.destination === 'test-host').name = 'Concurrent Test';
  const csrfToken = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
  await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': csrfToken }, data: concurrent });
  await editor.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(editor.getByRole('alert')).toContainText('changed');
  await expect(text).toHaveValue(sourceText + '\n');
  page.once('dialog', dialog => dialog.accept()); await editor.getByRole('button', { name: 'Close', exact: true }).click();
  await page.getByRole('button', { name: 'Configuration', exact: true }).click();
  await expect(text).toBeEnabled();
  await expect(editor.getByRole('button', { name: 'Reload', exact: true })).toHaveCount(0);
  await expect(editor.locator('.actions > button').last()).toHaveAttribute('aria-label', 'Close');
  await expect(editor.getByRole('alert')).toHaveCount(0);
  await text.fill((await text.inputValue()) + '\n  ');
  await editor.getByRole('button', { name: 'Save', exact: true }).click();
  await expect(editor.getByRole('status')).toContainText('Saved.');
  await editor.getByRole('button', { name: 'Close', exact: true }).click();
  // Never select it: this fixture is configuration only, not simulated SSH discovery.
  if (process.env.AELAB_TEST_SSH) {
    await page.goto(`${origin}/hosts/fixture-1/`);
    await expect(page.getByRole('button', { name: 'Screensaver', exact: true })).toBeEnabled();
    // Definitions are global; projects and services stay on their host. IDs follow names on rename.
    const projectParent = (await configSnapshot()).config.hosts.find(host => host.id === 'fixture-1').projects[0].dir;
    for (const id of ['fixture-1','fixture-3']) {
      await page.goto(`${origin}/hosts/${id}/`);
      await page.getByRole('button', { name: 'Add project', exact: true }).click();
      const projectForm = page.getByRole('dialog', { name: 'Configure project', exact: true });
      await projectForm.getByRole('button', { name: 'Browse Absolute project directory', exact: true }).click();
      const picker = page.getByRole('dialog', { name: 'Select host directory', exact: true });
      try { await expect(picker.getByRole('button', { name: 'Select directory', exact: true })).toBeEnabled(); }
      catch (e) { console.log('Directory picker failed', id, await picker.innerText()); throw e; }
      await picker.getByRole('button', { name: 'directory picker', exact: true }).click();
      await expect(picker.getByRole('button', { name: 'private-file.txt', exact: true })).toHaveCount(0);
      await expect(picker.getByRole('button', { name: 'loop', exact: true })).toHaveCount(0);
      await picker.getByRole('button', { name: 'nested', exact: true }).click();
      await picker.getByRole('button', { name: 'Select directory', exact: true }).click();
      await expect(projectForm.getByLabel('Absolute project directory', { exact: true })).toHaveValue(/directory picker\/nested$/);
      await projectForm.getByRole('button', { name: 'Cancel', exact: true }).click();
    }
    await page.goto(`${origin}/hosts/fixture-1/`);
    for (const [kind, title, add, field, value] of [
      ['projects', 'PROJECTS', 'Add project', 'Absolute project directory', `${projectParent}/created from form`],
      ['services', 'SERVICES', 'Add service', process.env.AELAB_TEST_PLATFORM === 'macos' ? 'Launchd service target' : 'Systemd unit', process.env.AELAB_TEST_PLATFORM === 'macos' ? `gui/${process.env.AELAB_TEST_UID}/com.aelab.fixture` : 'aelab-fixture.service'],
      ['tools', 'TOOLS', 'Add tool', 'Executable or approved host script', '/bin/sh'],
      ['plugins', 'PLUGINS', 'Add plugin', 'Executable or approved host script', '/bin/sh']
    ]) {
      await page.getByRole('button', { name: add, exact: true }).click();
      const dialog = page.getByRole('dialog', { name: `Configure ${kind}`, exact: true });
      await dialog.getByLabel('Name', { exact: true }).fill(`Fresh ${kind}`);
      if (kind === 'services') {
        await expect(dialog.getByLabel('Terminal project (optional)', { exact: true })).toHaveCount(0);
        await expect(dialog.getByLabel('Interactive tool (optional)', { exact: true })).toHaveCount(0);
        for (const [provider, label] of [['docker', 'Container name or ID'], ['compose', 'Compose project name'], ['systemd', 'Systemd unit'], ['launchd', 'Launchd service target']]) {
          await dialog.getByRole('combobox', { name: /^Provider/ }).selectOption(provider); await expect(dialog.getByLabel(label, { exact: true })).toBeVisible();
        }
        await dialog.getByRole('combobox', { name: /^Provider/ }).selectOption(process.env.AELAB_TEST_PLATFORM === 'macos' ? 'launchd' : 'systemd');
      }
      await dialog.getByLabel(field, { exact: true }).fill(value);
      if (kind === 'plugins') await dialog.getByLabel('Arguments (JSON string array)', { exact: true }).fill(JSON.stringify((await configSnapshot()).config.plugins[0].arguments));
      await dialog.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(dialog).toHaveCount(0);
      const result = (await configSnapshot()).config;
      const rows = kind === 'tools' || kind === 'plugins' ? result[kind] : result.hosts.find(h => h.id === 'fixture-1')[kind];
      if (!rows.some(x => x.id === `fresh-${kind}`)) throw new Error('Entity saved in the wrong scope');
      if (kind === 'projects') {
        const csrf = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
        const prepared = await page.request.post(`${origin}/api/hosts/fixture-1/terminal-tickets`, { headers: { Origin: origin, 'X-CSRF-Token': csrf }, data: { project: 'fresh-projects' } });
        if (!prepared.ok()) throw new Error('Created project directory is not accessible');
      }
      const row = page.getByRole('region', { name: title, exact: true }).locator(':scope > ul > li').filter({ hasText: `Fresh ${kind}` });
      if (kind !== 'projects') {
        const positions = await row.evaluate(element => {
          const badge = element.querySelector('.managed-status .badge').getBoundingClientRect();
          const drag = element.querySelector('.reorder-control summary').getBoundingClientRect();
          return { center: badge.y + badge.height / 2, expected: drag.y + drag.height / 2 };
        });
        expect(Math.abs(positions.center - positions.expected)).toBeLessThan(2);
        await row.screenshot({ path: `/tmp/aelab-${kind}-row.png` });
      }
      if (kind === 'services') {
        let statusRequests = 0;
        const statusURL = `${origin}/api/hosts/fixture-1/services/fresh-services`;
        await page.route(statusURL, route => { statusRequests++; return route.fulfill({ json: { status: 0, output: 'SERVICE_STATUS_FIXTURE', error: '', truncated: false } }); });
        for (const trigger of [row.getByRole('link', { name: 'Fresh services', exact: true }), row.getByRole('button', { name: 'status', exact: true })]) {
          await trigger.click(); const output = page.getByRole('dialog', { name: /Fresh services.*status/ });
          await expect(output).toContainText('SERVICE_STATUS_FIXTURE'); await output.getByRole('button', { name: 'Close', exact: true }).click();
        }
        expect(statusRequests).toBe(2); await page.unroute(statusURL);
        const badge = await row.locator('.managed-status .badge').boundingBox(), edit = await row.getByRole('button', { name: 'Edit', exact: true }).boundingBox();
        if (badge.y < edit.y + edit.height) throw new Error('Service badge does not sit below edit/delete');
      }
      await row.getByRole('button', { name: 'Edit', exact: true }).click();
      await dialog.getByLabel('Name', { exact: true }).fill(`Renamed ${kind}`);
      await dialog.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(dialog).toHaveCount(0);
      const afterRename = (await configSnapshot()).config;
      const renamed = kind === 'tools' || kind === 'plugins' ? afterRename[kind] : afterRename.hosts.find(h => h.id === 'fixture-1')[kind];
      if (!renamed.some(x => x.id === `renamed-${kind}` && x.name === `Renamed ${kind}`)) throw new Error('Nested form rename did not update its derived ID');
      if (kind === 'services') { const service = renamed.find(service => service.id === 'renamed-services'); expect(service).not.toHaveProperty('project'); expect(service).not.toHaveProperty('tool'); }
      const deletionRow = page.getByRole('region', { name: title, exact: true }).locator(':scope > ul > li').filter({ hasText: `Renamed ${kind}` });
      if (kind === 'tools' || kind === 'plugins') {
        const singular = kind === 'tools' ? 'tool' : 'plugin';
        await expect(deletionRow.getByRole('button', { name: `Delete ${singular} definition`, exact: true })).toHaveCount(0);
        await deletionRow.getByRole('button', { name: `Enable ${singular} Renamed ${kind}`, exact: true }).click();
        await expect(deletionRow.getByRole('button', { name: `Disable ${singular} Renamed ${kind}`, exact: true })).toHaveAttribute('aria-pressed', 'true');
        await page.getByRole('button', { name: `Discovery ${kind}`, exact: true }).click();
        await deletionRow.getByRole('button', { name: `Disable ${singular} Renamed ${kind}`, exact: true }).click();
        await expect(deletionRow).toHaveCount(0);
        const afterDisable = await configSnapshot();
        expect(afterDisable.config[kind]).toEqual(afterRename[kind]);
        expect(afterDisable.config.hosts.find(h => h.id === 'fixture-2')).toEqual(afterRename.hosts.find(h => h.id === 'fixture-2'));
        // Exercise central deletion from the explicit local host, without touching host files.
        afterDisable.config.hosts.find(h => h.id === 'fixture-3')[kind].push(`renamed-${kind}`);
        const csrf = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
        expect((await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': csrf }, data: afterDisable })).ok()).toBeTruthy();
        await page.goto(`${origin}/hosts/fixture-3/`);
        const localRow = page.getByRole('region', { name: title, exact: true }).locator(':scope > ul > li').filter({ hasText: `Renamed ${kind}` });
        const deleteButton = localRow.getByRole('button', { name: `Delete ${singular} definition`, exact: true });
        await expect(deleteButton).toBeVisible();
        page.once('dialog', async dialog => { expect(dialog.message()).toContain('from all hosts'); expect(dialog.message()).toContain('Files and running programs are kept'); await dialog.dismiss(); });
        await deleteButton.click(); await expect(localRow).toBeVisible();
        page.once('dialog', dialog => dialog.accept()); await deleteButton.click();
        await expect(localRow).toHaveCount(0);
        expect((await configSnapshot()).config[kind].some(row => row.id === `renamed-${kind}`)).toBeFalsy();
        await page.goto(`${origin}/hosts/fixture-1/`);
      } else {
        page.once('dialog', dialog => dialog.accept());
        await deletionRow.getByRole('button', { name: 'Delete', exact: true }).click();
        await expect(deletionRow).toHaveCount(0);
      }
    }

    await page.getByRole('button', { name: 'Host launch menu', exact: true }).click();
    await expect(page.locator('.launch-options').getByRole('button', { name: 'tmux', exact: true })).toBeVisible();
    await page.locator('.picker-heading').first().click();
    await expect(page.locator('.launch-options')).toHaveCount(0);
    await page.getByRole('button', { name: 'Host launch menu', exact: true }).click();
    await page.keyboard.press('Escape'); await expect(page.locator('.launch-options')).toHaveCount(0);
    await page.getByRole('button', { name: 'Edit host', exact: true }).click();
    await expect(page.getByRole('dialog', { name: 'Configure host' }).getByLabel('Name', { exact: true })).toHaveValue('Fixture 1');
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(page.getByRole('region', { name: 'SHELLS', exact: true }).getByRole('button', { name: 'Open shell' })).toHaveCount(0);
    const beforeTemporary = (await (await page.request.get(`${origin}/api/hosts/fixture-1/status`)).json()).tmux.output;
    // Leave global-definition discovery views after form checks.
    for (const kind of ['tools','plugins']) { const filter = page.getByRole('button', { name: `Discovery ${kind}`, exact: true }); if (await filter.getAttribute('aria-pressed') === 'true') await filter.click(); }
    const projectRows = page.getByRole('region', { name: 'PROJECTS', exact: true });
    for (const [index, click] of [() => projectRows.getByRole('link', { name: 'Project 1', exact: true }).click(), () => projectRows.getByRole('button', { name: 'Open Project tool in Project 1', exact: true }).click()].entries()) {
      const opened = context.waitForEvent('page'); await click(); const temporary = await opened;
      await temporary.getByText('connected', { exact: true }).waitFor();
      if (index) await expect(temporary.locator('.xterm-rows')).toContainText('PROJECT_TOOL_OK');
      await temporary.locator('.xterm-helper-textarea').pressSequentially('pwd'); await temporary.locator('.xterm-helper-textarea').press('Enter');
      const cfg = (await configSnapshot()).config;
      await expect(temporary.locator('.xterm-rows')).toContainText(cfg.hosts.find(h => h.id === 'fixture-1').projects[0].dir);
      if (temporary.url().includes('persistent=1') || temporary.url().includes('/tmux/')) throw new Error('Ordinary project launch created tmux');
      await temporary.close();
    }
    await expect.poll(async () => (await (await page.request.get(`${origin}/api/hosts/fixture-1/status`)).json()).tmux.output).toBe(beforeTemporary);
    await expect(projectRows.getByRole('button', { name: 'Open tmux in Project 1', exact: true })).toHaveCount(0);
    // A project's explicit session is honored by its ordinary title link.
    const projectCSRF = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
    let sessionConfig = await configSnapshot();
    sessionConfig.config.hosts.find(h => h.id === 'fixture-1').projects.find(p => p.id === 'project-1').session = 'configured-project';
    let savedSession = await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: sessionConfig });
    if (!savedSession.ok()) throw new Error(await savedSession.text());
    await page.reload();
    for (let attempt = 0; attempt < 2; attempt++) {
      const opened = context.waitForEvent('page');
      await projectRows.getByRole('link', { name: 'Project 1', exact: true }).click();
      const sessionPage = await opened;
      await sessionPage.getByText('connected', { exact: true }).waitFor();
      await expect(sessionPage).toHaveURL(/\/tty\/tmux\/configured-project\//);
      if (!attempt) await sessionPage.locator('.xterm-helper-textarea').pressSequentially("printf '\\nCONFIGURED_PROJECT_OK\\n'\n");
      await expect(sessionPage.locator('.xterm-rows')).toContainText('CONFIGURED_PROJECT_OK');
      await sessionPage.close();
    }
    const endedProject = await page.request.delete(`${origin}/api/hosts/fixture-1/tmux/sessions/configured-project`, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF } });
    if ((await endedProject.json()).status !== 0) throw new Error('Could not remove fixture project session');
    sessionConfig = await configSnapshot();
    delete sessionConfig.config.hosts.find(h => h.id === 'fixture-1').projects.find(p => p.id === 'project-1').session;
    savedSession = await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: sessionConfig });
    if (!savedSession.ok()) throw new Error(await savedSession.text());
    await page.reload();
    // Normal title links use the same picker without enabling YOLO.
    const normalTool = page.getByRole('region', { name: 'TOOLS', exact: true }).getByRole('link', { name: 'Tool 1', exact: true });
    await normalTool.click();
    const normalPicker = page.getByRole('dialog', { name: 'Select host directory', exact: true });
    await expect(normalPicker.getByRole('button', { name: 'Select directory', exact: true })).toBeEnabled();
    const normalPath = await normalPicker.locator('.directory-current').textContent();
    const normalOpened = context.waitForEvent('page');
    await normalPicker.getByRole('button', { name: 'Select directory', exact: true }).click();
    const normalPage = await normalOpened;
    await expect(normalPage.locator('.xterm-rows')).toContainText('HOST-1');
    expect(new URL(normalPage.url()).searchParams.get('directory')).toBe(normalPath);
    expect(new URL(normalPage.url()).searchParams.get('yolo')).not.toBe('1');
    await normalPage.close();
    // Standalone YOLO defaults to host home and carries the chosen literal directory.
    const hostHome = (await (await page.request.get(`${origin}/api/hosts/fixture-1/status`)).json()).home;
    const pickerHome = (await (await page.request.get(`${origin}/api/hosts/fixture-1/directories`)).json()).path;
    const yoloOpened = context.waitForEvent('page');
    await page.getByRole('region', { name: 'TOOLS', exact: true }).locator('li').filter({ has: page.getByRole('link', { name: 'Tool 1', exact: true }) }).getByRole('button', { name: 'YOLO', exact: true }).click();
    const yoloPicker = page.getByRole('dialog', { name: 'Select host directory', exact: true });
    await expect(yoloPicker.locator('.directory-selection')).toContainText(pickerHome);
    await yoloPicker.getByRole('button', { name: 'Select directory', exact: true }).click();
    const yoloPage = await yoloOpened;
    await expect(yoloPage.locator('.xterm-rows')).toContainText('HOST-1');
    if (new URL(yoloPage.url()).searchParams.get('directory') !== pickerHome) throw new Error('YOLO directory not preserved');
    await yoloPage.close();
    // A configured default launches directly without opening the picker or confirmation.
    const defaultConfig = await configSnapshot();
    defaultConfig.config.tools.find(tool => tool.id === 'tool-1').directory = hostHome;
    const defaultSaved = await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: defaultConfig });
    if (!defaultSaved.ok()) throw new Error(await defaultSaved.text());
    await page.reload();
    const rejectYoloPrompt = () => { throw new Error('YOLO with a default directory must not prompt'); };
    page.on('dialog', rejectYoloPrompt);
    const defaultOpened = context.waitForEvent('page');
    await page.getByRole('region', { name: 'TOOLS', exact: true }).locator('li').filter({ has: page.getByRole('link', { name: 'Tool 1', exact: true }) }).getByRole('button', { name: 'YOLO', exact: true }).click();
    const defaultPage = await defaultOpened;
    await expect(defaultPage.locator('.xterm-rows')).toContainText('HOST-1');
    await defaultPage.close(); page.off('dialog', rejectYoloPrompt);
    const normalDefaultOpened = context.waitForEvent('page');
    await normalTool.click();
    const normalDefault = await normalDefaultOpened;
    await expect(normalDefault.locator('.xterm-rows')).toContainText('HOST-1');
    await expect(page.getByRole('dialog', { name: 'Select host directory', exact: true })).toHaveCount(0);
    expect(new URL(normalDefault.url()).searchParams.get('yolo')).not.toBe('1');
    await normalDefault.close();
    const yoloToggle = projectRows.getByRole('button', { name: 'YOLO mode for Project 1', exact: true });
    await yoloToggle.click();
    await expect(projectRows.getByRole('button', { name: 'Open Tool 1 in Project 1', exact: true })).toBeVisible();
    await expect(projectRows.getByRole('button', { name: 'Open Project tool in Project 1', exact: true })).toHaveCount(0);
    await yoloToggle.click();
    await expect(projectRows.getByRole('button', { name: 'Open Project tool in Project 1', exact: true })).toBeVisible();
    await expect(projectRows.getByRole('button', { name: 'shell', exact: true })).toHaveCount(0);
    await expect(projectRows.getByRole('combobox')).toHaveCount(0);
    await expect(projectRows.locator('.project-tools')).not.toContainText('shell');
    await expect(projectRows.locator('.project-tools')).not.toContainText('tmux');
    const toolsRegion = page.getByRole('region', { name: 'TOOLS', exact: true });
    await expect(toolsRegion.getByRole('button', { name: 'tmux', exact: true })).toHaveCount(0);
    await expect(toolsRegion.getByRole('button', { name: 'Refresh tools', exact: true })).toHaveCount(0);
    await toolsRegion.getByRole('button', { name: 'Discovery tools', exact: true }).click();
    await expect(toolsRegion.getByRole('button', { name: 'Discovery tools', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await expect(toolsRegion.getByRole('link', { name: 'Tool 1', exact: true })).toBeVisible();
    await expect(toolsRegion.getByRole('button', { name: 'Enable tool Tool 2', exact: true })).toBeEnabled();
    const order = async () => (await configSnapshot()).config.tools.map(tool => tool.id).slice(0, 3);
    await toolsRegion.getByLabel('Reorder Tool 3', { exact: true }).press('ArrowUp');
    await expect.poll(order).toEqual(['tool-1', 'tool-3', 'tool-2']);
    await toolsRegion.getByLabel('Reorder Tool 3', { exact: true }).dragTo(toolsRegion.locator('li[data-reorder-id="tool-1"]'));
    await expect.poll(order).toEqual(['tool-3', 'tool-1', 'tool-2']);
    await toolsRegion.getByLabel('Reorder Tool 3', { exact: true }).click();
    await toolsRegion.getByRole('button', { name: 'Move Tool 3 down', exact: true }).click();
    await expect.poll(order).toEqual(['tool-1', 'tool-3', 'tool-2']);
    await page.reload();
    await toolsRegion.getByRole('button', { name: 'Discovery tools', exact: true }).click();
    await expect.poll(order).toEqual(['tool-1', 'tool-3', 'tool-2']);
    await toolsRegion.getByLabel('Reorder Tool 3', { exact: true }).press('ArrowDown');
    await expect.poll(order).toEqual(['tool-1', 'tool-2', 'tool-3']);

    // Hold the first committed response while another checkbox is clicked.
    let releaseWrite; const firstWrite = new Promise(resolve => releaseWrite = resolve); let heldWrites = 0;
    await page.route('**/api/config', async route => {
      if (route.request().method() === 'PUT' && heldWrites++ === 0) {
        const response = await route.fetch(); await firstWrite; await route.fulfill({ response });
      } else await route.continue();
    });
    let refreshes = 0;
    const countRefresh = request => { if (request.method() === 'POST' && request.url().endsWith('/tools')) refreshes++; };
    page.on('request', countRefresh);
    await toolsRegion.getByRole('button', { name: 'Enable tool Tool 2', exact: true }).click();
    await expect.poll(() => heldWrites).toBe(1);
    await toolsRegion.getByRole('button', { name: 'Enable tool Tool 3', exact: true }).click();
    releaseWrite();
    await expect(toolsRegion.getByRole('button', { name: 'Disable tool Tool 2', exact: true })).toBeEnabled();
    await expect(toolsRegion.getByRole('button', { name: 'Disable tool Tool 3', exact: true })).toBeEnabled();
    await page.unroute('**/api/config'); page.off('request', countRefresh);
    if (refreshes) throw new Error('Host enablement unnecessarily re-ran tool discovery');
    const selections = (await configSnapshot()).config.hosts.find(h => h.id === 'fixture-1').tools;
    if (!selections.includes('tool-2') || !selections.includes('tool-3')) throw new Error('Rapid checkbox clicks lost a selection');
    await expect(page.getByRole('alert')).toHaveCount(0);
    const centralCSRF = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
    await toolsRegion.getByRole('button', { name: 'Disable tool Tool 2', exact: true }).click();
    await toolsRegion.getByRole('button', { name: 'Disable tool Tool 3', exact: true }).click();
    await expect(toolsRegion.getByRole('button', { name: 'Enable tool Tool 2', exact: true })).toBeEnabled();
    await expect(toolsRegion.getByRole('button', { name: 'Enable tool Tool 3', exact: true })).toBeEnabled();
    const disabledTool = await page.request.post(`${origin}/api/hosts/fixture-1/terminal-tickets`, { headers: { Origin: origin, 'X-CSRF-Token': centralCSRF }, data: { tool: 'tool-2' } });
    if (disabledTool.ok()) throw new Error('Disabled central tool still launches');
    await expect(toolsRegion.getByRole('button', { name: 'Refresh tools', exact: true })).toBeVisible();
    await toolsRegion.getByRole('button', { name: 'TOOLS', exact: true }).click();
    await expect(toolsRegion.getByRole('button', { name: 'Refresh tools', exact: true })).toHaveCount(0);
    await toolsRegion.getByRole('button', { name: 'TOOLS', exact: true }).click();
    await toolsRegion.getByRole('button', { name: 'Discovery tools', exact: true }).click();
    await expect(toolsRegion.getByRole('link', { name: 'Tool 1', exact: true })).toBeVisible();
    const pluginsRegion = page.getByRole('region', { name: 'PLUGINS', exact: true });
    await pluginsRegion.getByRole('button', { name: 'Disable plugin Example 1', exact: true }).click();
    await expect(pluginsRegion.getByRole('button', { name: /^Probe Example /, exact: true })).toHaveCount(0);
    const disabledPlugin = await page.request.post(`${origin}/api/hosts/fixture-1/plugins/example-1/runs`, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: {} });
    if (disabledPlugin.ok()) throw new Error('Disabled plugin still executes');
    await pluginsRegion.getByRole('button', { name: 'Discovery plugins', exact: true }).click();
    await expect(pluginsRegion.getByRole('button', { name: /^Probe Example /, exact: true })).toHaveCount(3);
    const deploymentURL = `${origin}/api/hosts/fixture-1/plugins/portable-probe/source/deployment`;
    await pluginsRegion.getByRole('button', { name: 'Deploy script Portable probe', exact: true }).click();
    const deploy = page.getByRole('dialog', { name: 'Deploy plugin script', exact: true });
    await expect(deploy.getByRole('button', { name: 'Deploy script', exact: true })).toBeEnabled();
    await expect(deploy.getByRole('button', { name: 'Reload preview', exact: true })).toHaveCount(0);
    await page.route(deploymentURL, async route => { await new Promise(resolve => setTimeout(resolve, 800)); await route.continue(); }, { times: 1 });
    await deploy.getByRole('button', { name: 'Deploy script', exact: true }).click();
    await expect(deploy).toHaveAttribute('aria-busy', 'true');
    await expect(deploy.getByRole('status')).toContainText('Deploying script');
    await expect(deploy.locator('.loader')).toHaveCSS('animation-name', 'loading-spin');
    await expect(deploy.getByRole('status')).toContainText('Script deployed.');
    await deploy.getByRole('button', { name: 'Close', exact: true }).click();
    const preview = await (await page.request.get(deploymentURL + '?from=fixture-3')).json();
    if (!preview.sourcePath.endsWith('/local/.aelab/plugins/portable.sh') || !preview.targetPath.endsWith('/1/.aelab/plugins/portable/portable.sh') || !preview.targetRevision) throw new Error('Deployment did not resolve each host home');
    await expect(pluginsRegion.getByRole('button', { name: 'Deploy script Portable probe', exact: true })).toHaveCount(0);
    const sourceURL = `${origin}/api/hosts/fixture-1/plugins/portable-probe/source`;
    const targetDoc = await (await page.request.get(sourceURL)).json();
    const edit = await page.request.put(sourceURL, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: { ...targetDoc, content: targetDoc.content + '\n# concurrent deployment edit\n' } });
    if (!edit.ok()) throw new Error(await edit.text());
    const stale = await page.request.post(deploymentURL, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: preview });
    if (stale.status() !== 409) throw new Error('Deployment overwrote a concurrent edit');
    if (!(await (await page.request.get(sourceURL)).json()).content.includes('concurrent deployment edit')) throw new Error('Deployment lost concurrent source');
    const latest = await (await page.request.get(deploymentURL + '?from=fixture-3')).json();
    const replacement = await page.request.post(deploymentURL, { headers: { Origin: origin, 'X-CSRF-Token': projectCSRF }, data: latest });
    if (!replacement.ok()) throw new Error(await replacement.text());
    if ((await page.request.get(deploymentURL + '?from=fixture-2')).ok()) throw new Error('Deployment accepted a remote source host');

    await pluginsRegion.getByRole('button', { name: /^Enable plugin Example /, exact: true }).first().click();
    await pluginsRegion.getByRole('button', { name: 'Discovery plugins', exact: true }).click();
    await page.getByRole('button', { name: /^Probe Example /, exact: true }).click();
    const extension = page.getByRole('region', { name: 'PLUGINS', exact: true });
    await expect(extension).toContainText('Root filesystem:');
    await expect(extension.locator('.plugin-details')).toContainText('Mount');
    await expect.poll(() => page.locator('.dashboard-content > section > h2 > .section-toggle').allTextContents()).toEqual(['▾PROJECTS','▾TOOLS','▾PLUGINS','▾SERVICES']);
    await expect(page.getByRole('region', { name: 'SHELLS', exact: true }).getByRole('heading')).toHaveCount(0);
    await page.getByRole('button', { name: 'Hide shells', exact: true }).click();
    await expect(page.getByRole('region', { name: 'SHELLS', exact: true })).toHaveCount(0);
    await expect.poll(async () => (await (await page.request.get(`${origin}/api/state/sections`)).json())['fixture-1']?.shells).toBe(false);
    await page.reload();
    await expect(page.getByRole('button', { name: 'Show shells', exact: true })).toHaveAttribute('aria-expanded', 'false');
    await page.locator('.host-picker-row').click({ position: { x: 4, y: 4 } });
    await expect(page.getByRole('region', { name: 'SHELLS', exact: true })).toBeVisible();
    await expect(page.getByRole('region', { name: 'TOOLS', exact: true }).getByRole('button', { name: 'Discovery tools', exact: true })).toBeVisible();
    await expect(page.getByRole('region', { name: 'SERVICES', exact: true }).getByRole('button', { name: 'Discovery services', exact: true })).toBeVisible();
    await expect(page.locator('body')).toHaveCSS('font-size', '16px');
    async function setTint(value) {
      await page.getByRole('button', { name: 'Edit host', exact: true }).click();
      const form = page.getByRole('dialog', { name: 'Configure host' });
      await form.getByLabel('Host tint').evaluate((element, tint) => { element.value = tint; element.dispatchEvent(new Event('input', { bubbles: true })); }, value);
      await form.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(form).toHaveCount(0);
    }
    await setTint('#c75b39');
    await expect.poll(() => page.evaluate(() => document.documentElement.style.getPropertyValue('--accent'))).toBe('#c75b39');
    await page.getByRole('button', { name: 'Toggle theme' }).click();
    await page.reload(); await expect(page.getByRole('button', { name: 'Screensaver', exact: true })).toBeEnabled();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
    await expect.poll(() => page.evaluate(() => document.documentElement.style.getPropertyValue('--accent'))).toBe('#c75b39');
    await page.goto(`${origin}/hosts/fixture-2/`); await expect(page.getByRole('button', { name: 'Screensaver', exact: true })).toBeEnabled();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    await expect.poll(() => page.evaluate(() => document.documentElement.style.getPropertyValue('--accent'))).not.toBe('#c75b39');
    await setTint('#346bd6');
    await page.goto(`${origin}/hosts/fixture-1/`); await expect(page.getByRole('button', { name: 'Screensaver', exact: true })).toBeEnabled();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
    await expect.poll(() => page.evaluate(() => document.documentElement.style.getPropertyValue('--accent'))).toBe('#c75b39');
    await expect(page.locator('.hosts button.active')).toHaveCSS('color', 'rgb(255, 255, 255)');
    await expect(page.locator('.hosts button.active')).toHaveCSS('font-weight', '700');
    const projectSection = page.getByRole('region', { name: 'PROJECTS', exact: true });
    await projectSection.getByRole('button', { name: 'PROJECTS', exact: true }).click();
    await expect(projectSection.locator('li')).toHaveCount(0);
    await expect.poll(async () => (await (await page.request.get(`${origin}/api/state/sections`)).json())['fixture-1']?.projects).toBe(false);
    await page.reload();
    await expect(projectSection.getByRole('button', { name: 'PROJECTS', exact: true })).toHaveAttribute('aria-expanded', 'false');
    await page.goto(`${origin}/hosts/fixture-2/`);
    await expect(page.getByRole('button', { name: 'PROJECTS', exact: true })).toHaveAttribute('aria-expanded', 'true');
    await page.goto(`${origin}/hosts/fixture-1/`);
    await projectSection.getByRole('button', { name: 'PROJECTS', exact: true }).click();
    await expect(projectSection.locator('.row-title')).toHaveCSS('font-size', '19.2px');
    const iconBounds = await page.locator('.brand .tint-trigger').boundingBox();
    const titleBounds = await page.locator('.brand h1').boundingBox();
    if (Math.abs(iconBounds.y + iconBounds.height / 2 - titleBounds.y - titleBounds.height / 2 - 2) > 1) throw new Error('Brand title and tint control are not centered');
    await page.getByRole('button', { name: 'Discovery services', exact: true }).click();
    await expect(page.getByLabel('Discovery status')).toHaveValue('running');
    await page.getByLabel('Discovery status').selectOption('all');
    await expect(page.getByLabel('Discovery status')).toHaveValue('all');
    await page.getByLabel('Discovery status').selectOption('running');
    await page.screenshot({ path: '/tmp/aelab-dashboard-refinement.png', fullPage: true });
    await page.getByRole('button', { name: 'Toggle theme' }).click();
    // Optional controls extend the restored defaults through the same shared config.
    const ttyConfig = await configSnapshot();
    ttyConfig.config.ttyButtons = ttyConfig.config.ttyButtons.filter(button => !['copy','paste','tmux-split-horizontal'].includes(button.key));
    ttyConfig.config.ttyButtons.push({ key: 'copy', label: 'Copy' }, { key: 'paste', label: 'Paste' }, { key: 'tmux-split-horizontal', label: 'split ↔' });
    const ttyCSRF = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
    const ttySaved = await page.request.put(`${origin}/api/config`, { headers: { Origin: origin, 'X-CSRF-Token': ttyCSRF }, data: ttyConfig });
    if (!ttySaved.ok()) throw new Error('Shared ttyButtons configuration failed');
    // These aliases are disposable sshd processes with separate temporary tmux socket roots.
    for (const number of [1, 2, 3]) {
      const sessionName = `ae-test-${number}-${Date.now()}`;
      // A plain SSH shell must retain normal line endings and be able to enter tmux itself.
      await page.goto(`${origin}/hosts/fixture-${number}/`);
      await expect(page.locator('.host-platform')).toHaveText(process.env.AELAB_TEST_PLATFORM);
      await expect(page.getByRole('region', { name: 'PROJECTS', exact: true }).locator('.git-badge')).toHaveText(`fixture/host-${number}`);
      if (number === 1) await page.route(`${origin}/api/hosts/fixture-1/plugins/example-1/source`, async route => { await new Promise(resolve => setTimeout(resolve, 800)); await route.continue(); }, { times: 1 });
      await page.getByRole('button', { name: `Edit script Example ${number}`, exact: true }).click();
      const scripts = page.getByRole('dialog', { name: 'Plugin scripts', exact: true });
      if (number === 1) {
        await expect(scripts).toHaveAttribute('aria-busy', 'true');
        await expect(scripts.getByRole('status')).toContainText('Loading script');
        await expect(scripts.locator('.loader')).toHaveCSS('animation-name', 'loading-spin');
      }
      const scriptInput = scripts.getByRole('textbox', { name: 'Plugin source', exact: true });
      await expect(scriptInput).toBeEnabled();
      const scriptOriginal = await scriptInput.inputValue();
      const scriptWrap = scripts.getByRole('button', { name: 'Wrap lines', exact: true });
      await expect(scriptWrap).toHaveAttribute('aria-pressed', 'false');
      await scriptWrap.click(); await expect(scriptWrap).toHaveAttribute('aria-pressed', 'true');
      await expect(scriptInput).toHaveValue(scriptOriginal);
      await scriptWrap.click();
      const addition = number === 3 ? '\n// editor integration check\n' : '\n# editor integration check\n';
      await scriptInput.fill(scriptOriginal + addition);
      await scripts.getByRole('button', { name: 'Validate', exact: true }).click();
      await expect(scripts.getByRole('status')).toContainText('Syntax valid');
      await scripts.getByRole('button', { name: 'Save', exact: true }).click();
      await expect(scripts.getByRole('status')).toContainText('Saved.');
      await expect(scripts.getByRole('button', { name: 'Reload', exact: true })).toHaveCount(0);
      await expect(scripts.locator('.actions > button').last()).toHaveAttribute('aria-label', 'Close');
      await scripts.getByRole('button', { name: 'Close', exact: true }).click();
      await page.getByRole('button', { name: `Edit script Example ${number}`, exact: true }).click();
      await expect(scriptInput).toHaveValue(scriptOriginal + addition);
      await scripts.getByRole('button', { name: 'Close', exact: true }).click();
      const shellOpened = context.waitForEvent('page');
      if (number === 1) {
        await page.getByRole('button', { name: 'Host launch menu', exact: true }).click();
        await page.locator('.launch-options').getByRole('button', { name: 'Shell', exact: true }).click();
      } else { await page.getByRole('button', { name: 'Host launch menu', exact: true }).click(); await page.locator('.launch-options').getByRole('button', { name: 'Shell', exact: true }).click(); }
      const shell = await shellOpened;
      await shell.getByText('connected', { exact: true }).waitFor({ timeout: 15000 });
      await expect(shell.locator('.terminal-meta')).not.toContainText(`Fixture ${number}`);
      await expect(shell.locator('.terminal-meta')).toContainText(process.env.AELAB_TEST_HOSTNAME);
      if (number === 1) {
        await shell.setViewportSize({ width: 390, height: 844 });
        const hostLabel = shell.getByRole('button', { name: 'Reset terminal background', exact: true });
        const cwdLabel = shell.locator('.terminal-cwd label');
        await expect(hostLabel).toBeVisible(); await expect(cwdLabel).toBeVisible();
        const hostBounds = await hostLabel.boundingBox(), cwdBounds = await cwdLabel.boundingBox();
        if (cwdBounds.y < hostBounds.y + hostBounds.height) throw new Error('Compact host/cwd are not on separate lines');
        await shell.screenshot({ path: '/tmp/aelab-terminal-mobile.png' });
        await shell.setViewportSize({ width: 1280, height: 720 });
      }
      await expect(shell.locator('.terminal-page')).toHaveCSS('background-color', 'rgb(34, 51, 68)');
      await expect(shell.locator('.terminal-meta input[type=color]')).toHaveCount(1);
      await expect(shell.locator('.terminal-logo circle')).toHaveCount(2);
      await expect(shell.getByRole('button', { name: 'Copy', exact: true })).toHaveCount(0);
      await shell.getByRole('button', { name: 'Collapse header', exact: true }).click();
      await expect(shell.locator('.terminal-page')).toHaveClass(/header-collapsed/);
      await shell.getByRole('button', { name: 'Expand header', exact: true }).click();
      await shell.getByRole('button', { name: 'Show key bar', exact: true }).click();
      await expect(shell.getByRole('button', { name: 'Copy', exact: true })).toBeVisible();
      await shell.getByRole('button', { name: 'Hide key bar', exact: true }).click();
      const shellInput = shell.locator('.xterm-helper-textarea');
      await shellInput.pressSequentially("test -t 0 && test -t 1 && printf 'TTY_OK\\n'; printf 'ALIGN_ONE\\nALIGN_TWO\\nALIGN_THREE\\n'", { delay: 3 });
      await shellInput.press('Enter');
      await shell.locator('.xterm-rows > div').filter({ hasText: /^ALIGN_TWO\s*$/ }).last().waitFor({ timeout: 10000 });
      await expect(shell.locator('.xterm-rows')).toContainText('TTY_OK');
      const nestedSession = `${sessionName}-shell`;
      await shellInput.pressSequentially(`tmux new-session -s ${nestedSession}`); await shellInput.press('Enter');
      await shellInput.pressSequentially("printf 'NESTED_TMUX_OK\\n'; tmux display-message -p '#{session_name}'", { delay: 3 }); await shellInput.press('Enter');
      await shell.locator('.xterm-rows > div').filter({ hasText: /^\s*NESTED_TMUX_OK\s*$/ }).last().waitFor({ timeout: 10000 });
      await expect(shell.locator('.xterm-rows')).toContainText(nestedSession);
      await shellInput.pressSequentially('exit'); await shellInput.press('Enter');
      await expect(shell.locator('.xterm-rows')).not.toContainText('NESTED_TMUX_OK');
      await shellInput.pressSequentially("printf 'OUTER_SHELL_OK\\n'", { delay: 3 }); await shellInput.press('Enter');
      await shell.locator('.xterm-rows > div').filter({ hasText: /^OUTER_SHELL_OK\s*$/ }).last().waitFor({ timeout: 10000 });
      await shellInput.pressSequentially('AELAB_PIN_CHECK=kept'); await shellInput.press('Enter');
      await shell.getByRole('button', { name: 'Pin terminal session', exact: true }).click();
      await expect(shell.getByRole('button', { name: 'Unpin terminal session', exact: true })).toHaveAttribute('aria-pressed', 'true');
      const pinnedURL = shell.url(); if (!pinnedURL.includes('/pinned/')) throw new Error('Pin did not create a retained-terminal URL');
      await shell.screenshot({ path: `/tmp/aelab-terminal-header-${number}.png` });
      await shell.close();
      const resumed = await context.newPage(); await resumed.goto(pinnedURL);
      await resumed.getByText('connected', { exact: true }).waitFor();
      const resumedInput = resumed.locator('.xterm-helper-textarea');
      await resumedInput.pressSequentially('printf "PIN_STATE:%s\\n" "$AELAB_PIN_CHECK"'); await resumedInput.press('Enter');
      await expect(resumed.locator('.xterm-rows')).toContainText('PIN_STATE:kept');
      const pins = await (await page.request.get(`${origin}/api/hosts/fixture-${number}/terminals`)).json();
      if (pins.length !== 1) throw new Error('Pinned terminal was not listed');
      if (number === 1) {
        for (const [name, id] of [['Renamed host', 'renamed-host'], ['Fixture 1', 'fixture-1']]) {
          await page.getByRole('button', { name: 'Edit host', exact: true }).click();
          const hostForm = page.getByRole('dialog', { name: 'Configure host', exact: true });
          await hostForm.getByLabel('Name', { exact: true }).fill(name);
          await hostForm.getByRole('button', { name: 'Save', exact: true }).click();
          await expect(hostForm).toBeHidden(); await expect(page).toHaveURL(`${origin}/hosts/${id}/`);
          const retained = await (await page.request.get(`${origin}/api/hosts/${id}/terminals`)).json();
          if (retained[0]?.id !== pins[0].id) throw new Error('Host rename lost the owned pinned terminal');
          const renamedPin = await context.newPage(); await renamedPin.goto(`${origin}/hosts/${id}/tty/pinned/${pins[0].id}/`);
          await renamedPin.getByText('connected', { exact: true }).waitFor();
          await renamedPin.locator('.xterm-helper-textarea').pressSequentially('printf "PIN_RENAME:%s\\n" "$AELAB_PIN_CHECK"');
          await renamedPin.locator('.xterm-helper-textarea').press('Enter');
          await expect(renamedPin.locator('.xterm-rows')).toContainText('PIN_RENAME:kept'); await renamedPin.close();
        }
        const other = await browser.newContext();
        const login = await other.request.post(`${origin}/api/auth/session`, { headers: { Origin: origin }, data: { password } });
        const { csrf: otherCSRF } = await login.json();
        const headers = { Origin: origin, 'X-CSRF-Token': otherCSRF };
        if ((await (await other.request.get(`${origin}/api/hosts/fixture-1/terminals`)).json()).length) throw new Error('Another login saw native pins');
        if ((await other.request.post(`${origin}/api/hosts/fixture-1/terminal-tickets`, { headers, data: { pinned: pins[0].id } })).ok()) throw new Error('Another login attached to a native pin');
        if ((await other.request.delete(`${origin}/api/hosts/fixture-1/terminals/${pins[0].id}`, { headers })).ok()) throw new Error('Another login deleted a native pin');
        await other.request.delete(`${origin}/api/auth/session`, { headers }); await other.close();
      }
      if ((await page.getByRole('button', { name: 'Discovery services', exact: true }).getAttribute('aria-pressed')) !== 'true') await page.getByRole('button', { name: 'Discovery services', exact: true }).click();
      await page.getByRole('button', { name: 'Refresh services', exact: true }).click();
      await expect(page.locator('.host-shells a[href*="/pinned/"]')).toHaveCount(1);
      await expect(page.locator('.host-shells .pin-number')).toHaveText(String(pins[0].number));
      const numberBox = await page.locator('.host-shells .pin-number').boundingBox();
      const badgeBox = await page.locator('.host-shells .pinned-row .row-title').boundingBox();
      if (numberBox.x + numberBox.width > badgeBox.x) throw new Error('Pin number must precede the title');
      if (badgeBox.x - numberBox.x - numberBox.width > 12) throw new Error('Pin number is separated by a spacer');
      await expect(page.locator('.host-shells .pin-number')).toHaveCSS('border-radius', '50%');
      await page.getByRole('button', { name: 'Hide shells', exact: true }).click();
      const collapsedPin = page.locator('.host-picker-row').getByRole('link', { name: `Open pinned shell ${pins[0].number}`, exact: true });
      await expect(collapsedPin).toBeVisible();
      const collapsedPage = context.waitForEvent('page'); await collapsedPin.click();
      const collapsedTerminal = await collapsedPage; await collapsedTerminal.getByText('connected', { exact: true }).waitFor(); await collapsedTerminal.close();
      await page.getByRole('button', { name: 'Show shells', exact: true }).click();
      await expect(page.locator('.host-pin-shortcuts')).toHaveCount(0);
      await page.locator('body').click({ position: { x: 5, y: 5 } });
      const shortcutPage = context.waitForEvent('page');
      await page.keyboard.type(String(pins[0].number)); await page.keyboard.press('Enter');
      const numbered = await shortcutPage; await numbered.getByText('connected', { exact: true }).waitFor();
      if (!numbered.url().includes(`/pinned/${pins[0].id}/`)) throw new Error('Numeric shortcut opened the wrong terminal');
      await numbered.close();
      const sessionFilter = page.getByRole('group', { name: 'Shell filter' }).getByRole('button', { name: 'pinned', exact: true });
      await expect(sessionFilter).toHaveAttribute('aria-pressed', 'false');
      await sessionFilter.click();
      await expect(sessionFilter).toHaveAttribute('aria-pressed', 'true');
      await expect(page.locator('.host-shells .tmux-badge')).toHaveCount(0);
      await expect(page.locator('.host-shells .pinned-badge')).toHaveCount(1);
      const pinColor = await page.locator('.pinned-badge').evaluate(el => getComputedStyle(el).backgroundColor);
      await page.getByRole('group', { name: 'Shell filter' }).getByRole('button', { name: 'all', exact: true }).click();
      await expect(page.locator('.hosts').getByRole('button', { name: 'all', exact: true })).toBeVisible();
      const sessionBackground = await page.locator('.host-shells li').first().evaluate(el => getComputedStyle(el).backgroundColor);
      const rowBackground = await page.getByRole('region', { name: 'PROJECTS', exact: true }).locator('li').first().evaluate(el => getComputedStyle(el).backgroundColor);
      if (sessionBackground !== rowBackground) throw new Error('Session rows do not use the main-branch panel background');
      await resumed.getByRole('button', { name: 'Unpin terminal session', exact: true }).click();
      await expect(resumed.getByRole('button', { name: 'Pin terminal session', exact: true })).toHaveAttribute('aria-pressed', 'false');
      await resumed.close();
      await expect.poll(async () => (await (await page.request.get(`${origin}/api/hosts/fixture-${number}/terminals`)).json()).length).toBe(0);
      const expiredPin = await context.newPage(); await expiredPin.goto(pinnedURL);
      await expiredPin.getByText('disconnected', { exact: true }).waitFor(); await expiredPin.close();
      const tty = await context.newPage();
      const resizes = []; const metadata = []; const tmuxInputs = [];
      tty.on('websocket', ws => ws.on('framesent', event => {
        if (typeof event.payload === 'string') { try { const frame = JSON.parse(event.payload); if (frame.type === 'resize') resizes.push(frame); if (frame.type === 'input' && frame.data.endsWith('%')) tmuxInputs.push([...frame.data].map(c => c.charCodeAt(0))); } catch {} }
      }));
      tty.on('websocket', ws => ws.on('framereceived', event => { if (typeof event.payload === 'string') { try { metadata.push(JSON.parse(event.payload)); } catch {} } }));
      await tty.goto(`${origin}/hosts/fixture-${number}/tty/tmux/${sessionName}/?project=project-${number}&persistent=1`);
      await tty.getByText('connected', { exact: true }).waitFor({ timeout: 15000 });
      await tty.getByRole('button', { name: 'Show key bar', exact: true }).click();
      if ((await page.getByRole('button', { name: 'Discovery services', exact: true }).getAttribute('aria-pressed')) !== 'true') await page.getByRole('button', { name: 'Discovery services', exact: true }).click();
      await page.getByRole('button', { name: 'Refresh services', exact: true }).click();
      await expect(page.locator('.host-shells .tmux-badge')).not.toHaveCount(0);
      const tmuxColor = await page.locator('.tmux-badge').first().evaluate(el => getComputedStyle(el).backgroundColor);
      if (pinColor === tmuxColor) throw new Error('Pinned and tmux badges use the same color');
      await sessionFilter.click();
      await expect(page.locator('.host-shells .tmux-badge')).toHaveCount(0);
      await sessionFilter.click();
      await expect(page.locator('.host-shells .tmux-badge')).not.toHaveCount(0);
      const input = tty.locator('.xterm-helper-textarea');
      await input.pressSequentially("printf 'AE_CLIPBOARD_MARKER\\n'; pwd; stty size", { delay: 5 });
      await input.press('Enter');
      const marker = tty.locator('.xterm-rows > div').filter({ hasText: /^\s*AE_CLIPBOARD_MARKER\s*$/ }).last();
      await marker.waitFor({ timeout: 10000 });
      const snapshot = await tty.request.get(`${origin}/api/config`);
      const cfg = identify((await snapshot.json()).config);
      const directory = cfg.hosts.find(h => h.id === `fixture-${number}`).projects.find(p => p.id === `project-${number}`).dir;
      await expect(tty.locator('.xterm-rows')).toContainText(directory);
      const bounds = await marker.boundingBox();
      // Shift forces xterm selection even when remote tmux enables mouse reporting.
      await tty.keyboard.down(process.platform === 'darwin' ? 'Alt' : 'Shift');
      await tty.mouse.dblclick(bounds.x + 30, bounds.y + bounds.height / 2);
      await tty.keyboard.up(process.platform === 'darwin' ? 'Alt' : 'Shift');
      await tty.getByRole('button', { name: 'Copy', exact: true }).click();
      const copied = await tty.evaluate(() => navigator.clipboard.readText());
      if (!copied.includes('AE_CLIPBOARD_MARKER')) throw new Error(`Terminal copy failed: ${copied}`);
      console.log(`Host ${number}: real terminal selection copied`);
      await tty.evaluate(() => navigator.clipboard.writeText("printf 'PASTE_OK\\n'\n"));
      await tty.getByRole('button', { name: 'Paste', exact: true }).click();
      // Clipboard reading is asynchronous; wait until the remote line editor has the paste.
      await expect(tty.locator('.xterm-rows')).toContainText('PASTE_OK');
      await input.press('Enter');
      try { await tty.locator('.xterm-rows > div').filter({ hasText: /^\s*PASTE_OK\s*$/ }).last().waitFor({ timeout: 10000 }); }
      catch (error) { console.log('Fixture terminal after paste:', await tty.locator('.xterm-rows').innerText()); throw error; }
      // Browser resize must propagate through the SSH PTY to remote stty.
      const sizes = tty.locator('.xterm-rows > div').filter({ hasText: /^\s*\d+\s+\d+\s*$/ });
      const originalSize = (await sizes.last().textContent()).trim();
      await tty.setViewportSize({ width: 950, height: 620 });
      await new Promise(resolve => setTimeout(resolve, 150));
      await input.pressSequentially('stty size'); await input.press('Enter');
      try { await expect.poll(async () => (await sizes.last().textContent()).trim()).not.toBe(originalSize); }
      catch (error) {
        console.log('Resize frames:', resizes, 'container:', await tty.locator('.terminal-container').boundingBox(), 'screen:', await tty.locator('.xterm-screen').boundingBox());
        console.log('Fixture terminal after resize:', await tty.locator('.xterm-rows').innerText()); throw error;
      }
      await tty.getByLabel('background', { exact: true }).evaluate(element => {
        element.value = '#112233'; element.dispatchEvent(new Event('input', { bubbles: true }));
      });
      await expect(tty.locator('.terminal-page')).toHaveCSS('background-color', 'rgb(17, 34, 51)');
      await tty.getByRole('button', { name: 'Reset terminal background', exact: true }).click();
      await expect(tty.locator('.terminal-page')).toHaveCSS('background-color', 'rgb(34, 51, 68)');
      await tty.getByLabel('background', { exact: true }).evaluate(element => { element.value = '#112233'; element.dispatchEvent(new Event('input', { bubbles: true })); });
      // Toolbar uses the remote prefix, including config loaded when the first tmux server starts.
      const csrf = (await (await tty.request.get(`${origin}/api/auth/session`)).json()).csrf;
      await tty.getByRole('button', { name: 'split ↔', exact: true }).click();
      await input.pressSequentially("printf 'PANES:%s\\n' \"$(tmux display-message -p '#{window_panes}')\""); await input.press('Enter');
      console.log('Tmux metadata:', metadata, 'pane keys:', tmuxInputs);
      await expect(tty.locator('.xterm-rows')).toContainText('PANES:2');
      await input.pressSequentially('exit'); await input.press('Enter');
      // Explicit new-window API uses a configured tool and the selected project directory.
      const windowResult = await tty.request.post(`${origin}/api/hosts/fixture-${number}/tmux/sessions/${sessionName}/windows`, { headers: { Origin: origin, 'X-CSRF-Token': csrf }, data: { project: `project-${number}` } });
      const windowStatus = await windowResult.json();
      if (windowStatus.status !== 0) throw new Error(windowStatus.error);
      await new Promise(resolve => setTimeout(resolve, 150));
      await input.pressSequentially('pwd'); await input.press('Enter');
      await expect(tty.locator('.xterm-rows')).toContainText(directory);
      await input.pressSequentially('exit'); await input.press('Enter');

      // Resize is a real PTY operation; Ctrl+C must remain an interrupt without selection.
      await tty.locator('.xterm-screen').click(); await input.focus(); await input.pressSequentially('sleep 30'); await input.press('Enter');
      await input.press('Control+c');
      await input.pressSequentially("printf 'INTERRUPT_OK\\n'"); await input.press('Enter');
      try { await tty.locator('.xterm-rows > div').filter({ hasText: /^\s*INTERRUPT_OK\s*$/ }).last().waitFor({ timeout: 8000 }); }
      catch (error) { console.log(`Host ${number} interrupt screen:`, await tty.locator('.xterm-rows').innerText()); throw error; }
      const canonical = tty.url(); if (canonical.includes('persistent=1')) throw new Error('Canonical session URL can recreate a deleted session'); await tty.close();
      if (number === 1 || number === 3) {
        // Restart only the isolated central test process; remote tmux must survive.
        process.kill(replacementServer?.pid ?? Number(process.env.AELAB_TEST_SERVER_PID), 'SIGTERM');
        for (let i = 0; i < 100; i++) {
          try { await fetch(`${origin}/health`, { signal: AbortSignal.timeout(100) }); await new Promise(r => setTimeout(r, 50)); }
          catch { break; }
        }
        replacementServer = spawn(process.env.AELAB_TEST_SERVER_BINARY, [], { env: process.env, stdio: 'ignore' });
        for (let i = 0; i < 100; i++) {
          try { const health = await fetch(`${origin}/health`); if (health.ok) break; } catch {}
          await new Promise(r => setTimeout(r, 50));
        }
        await page.goto(origin);
        await page.getByLabel('Administrator password').fill(password);
        await page.getByRole('button', { name: 'Sign in', exact: true }).click();
        await page.getByRole('button', { name: 'Check all' }).waitFor();
      }
      const again = await context.newPage(); await again.goto(canonical);
      await again.getByText('connected', { exact: true }).waitFor({ timeout: 15000 });
      await expect(again.locator('.terminal-page')).toHaveCSS('background-color', 'rgb(17, 34, 51)');
      await again.locator('.xterm-helper-textarea').pressSequentially("printf 'REATTACH_OK\\n'");
      await again.locator('.xterm-helper-textarea').press('Enter');
      await again.locator('.xterm-rows > div').filter({ hasText: /^\s*REATTACH_OK\s*$/ }).last().waitFor();
      // End only the newly created disposable fixture session, through the real dashboard.
      await page.goto(`${origin}/hosts/fixture-${number}/`);
      if (number === 3) {
        const renameCSRF = (await (await page.request.get(`${origin}/api/auth/session`)).json()).csrf;
        const collision = await page.request.patch(`${origin}/api/hosts/fixture-3/tmux/sessions/${sessionName}`, { headers: { Origin: origin, 'X-CSRF-Token': renameCSRF }, data: { name: 'fixture-bootstrap' } });
        if (!(await collision.json()).status) throw new Error('tmux rename overwrote an existing session');
      }
      const renamed = `${sessionName}-renamed`;
      page.once('dialog', dialog => dialog.accept(renamed));
      await page.getByRole('button', { name: `Rename tmux session ${sessionName}`, exact: true }).click();
      const deletion = page.getByRole('button', { name: `Delete tmux session ${renamed}`, exact: true });
      try { await deletion.waitFor({ timeout: 10000 }); }
      catch (e) { console.log('Fixture session lookup:', canonical, await page.locator('.host-shells').innerText(), await (await page.request.get(`${origin}/api/hosts/fixture-${number}/status`)).json()); throw e; }
      await again.locator('.xterm-helper-textarea').pressSequentially("printf 'RENAMED_ATTACHMENT_OK\\n'");
      await again.locator('.xterm-helper-textarea').press('Enter');
      await again.locator('.xterm-rows > div').filter({ hasText: /^\s*RENAMED_ATTACHMENT_OK\s*$/ }).last().waitFor();
      page.once('dialog', dialog => dialog.dismiss()); await deletion.click();
      await expect(deletion).toBeVisible();
      const sessionRow = deletion.locator('..').locator('..');
      await expect(sessionRow.locator('.tmux-badge')).toHaveText('tmux');
      await expect(sessionRow.locator('small')).toContainText('windows');
      page.once('dialog', dialog => dialog.accept()); await deletion.click();
      await expect(deletion).toHaveCount(0);
      await again.getByText('disconnected', { exact: true }).waitFor(); await again.close();
      const ended = await context.newPage(); await ended.goto(canonical);
      await ended.getByText('disconnected', { exact: true }).waitFor(); await ended.close();
      const sessionsAfter = (await (await page.request.get(`${origin}/api/hosts/fixture-${number}/status`)).json()).tmux.output;
      if (sessionsAfter.split('\n').some(line => [sessionName, renamed].includes(line.split('|')[0]))) throw new Error('Opening an ended session recreated it');

    }
    console.log('PASS: two SSH hosts plus native local PTYs, aligned plain-shell output, tmux entered from an ordinary shell, project directories, tmux reattachment across central restart, stable protected SSH identity, resize, tmux panes/windows, backgrounds, Chromium clipboard copy/paste, Ctrl+C, header controls, native pin replay/ownership, tmux rename/collisions and confirmed deletion');
  }
  await page.getByRole('button', { name: 'Toggle theme' }).click();
  if (await page.locator('html').getAttribute('data-theme') !== 'light') throw new Error('Theme toggle failed');
  await page.route('**/api/config?format=source', route => route.abort('connectionrefused'));
  await page.getByRole('button', { name: 'Configuration', exact: true }).click();
  const offlineEditor = page.getByRole('dialog', { name: 'Main configuration', exact: true });
  await expect(offlineEditor.getByRole('alert')).toContainText('Server is offline');
  await page.unroute('**/api/config?format=source');
  await offlineEditor.getByRole('button', { name: 'Close', exact: true }).click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor();
  if (errors.length) throw new Error(errors.join('\n'));
  await context.close();
  console.log('PASS: real Chromium login/nested forms/name-derived IDs/config editor/section persistence/theme/host tint/discovery filter/logout; no browser runtime errors');
} finally {
  await browser.close();
  if (replacementServer && replacementServer.exitCode === null) { replacementServer.kill('SIGTERM'); await new Promise(resolve => replacementServer.once('exit', resolve)); }
}
