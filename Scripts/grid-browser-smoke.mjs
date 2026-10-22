import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const origin = process.env.AELAB_TEST_ORIGIN, base = '/lab/aelab';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const context = await browser.newContext({ viewport: { width: 1100, height: 1000 } });
  const page = await context.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  // Display fixtures keep this layout check independent of machine services and sessions.
  const result = { status: 0, output: '', error: '', truncated: false };
  await page.route('**/api/hosts/*/status', route => route.fulfill({ json: { host: 'local', hostname: 'layout-fixture', platform: 'linux', reachable: true, checked: new Date().toISOString(), staleAfterSeconds: 60, connection: result, tmux: { ...result, output: 'one|1|0\ntwo|1|0' }, discovered: [{ provider: 'systemd', target: 'discovered-one.service', state: 'running' }, { provider: 'systemd', target: 'discovered-two.service', state: 'running' }], curated: {}, projectBranches: { work: 'feature/Case-Sensitive', 'work-two': 'main', 'work-three': 'feature/a-very-long-branch-name-for-layout' } } }));
  await page.route('**/api/hosts/*/terminals', route => route.fulfill({ json: [{ id: 'one', number: 1, host: 'local', cwd: '/fixture/one' }, { id: 'two', number: 2, host: 'local', cwd: '/fixture/two' }] }));
  await page.goto(origin + base + '/hosts/local/');
  await page.getByLabel('Administrator password').fill(process.env.AELAB_TEST_PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Work', exact: true })).toBeVisible();
  const session = await (await context.request.get(origin + base + '/api/auth/session')).json();
  const snapshot = await (await context.request.get(origin + base + '/api/config')).json();
  const directory = snapshot.config.hosts[0].projects[0].directory;
  const names = ['Codex', 'Claude', 'Pi', 'opencode-with-a-very-long-name-for-grid-layout'];
  snapshot.config.tools = names.map(name => ({ name, executable: '/bin/sh', arguments: [], yoloArguments: ['-i'] }));
  snapshot.config.plugins = ['One', 'Two', 'Three', 'Four plugin with a longer title'].map(name => ({ name, executable: '/bin/true', arguments: [] }));
  snapshot.config.hosts[0].projects = ['Work', 'Work Two', 'Work Three', 'Work Four'].map(name => ({ name, directory: directory + '/a-long-project-path-that-should-wrap-without-overflowing-the-card' }));
  snapshot.config.hosts[0].services = ['One', 'Two', 'Three', 'Four'].map(name => ({ name, provider: 'systemd', target: name.toLowerCase() + '.service' }));
  snapshot.config.hosts[0].tools = ['codex', 'claude', 'pi', names[3]];
  snapshot.config.hosts[0].plugins = ['one', 'two', 'three', 'four-plugin-with-a-longer-title'];
  snapshot.config.hosts.push(...['Local Two', 'Local Three', 'Local Four', 'Local Five', 'Local Six', 'Local Seven', 'Local Eight', 'Local Nine'].map(name => ({ name, transport: 'local', projects: [], services: [], tools: [], plugins: [] })));
  const saved = await context.request.put(origin + base + '/api/config', { data: snapshot, headers: { Origin: origin, 'X-CSRF-Token': session.csrf } });
  expect(saved.status()).toBe(200);
  await page.reload();
  await expect(page.getByRole('button', { name: 'Compact layout', exact: true })).toHaveCount(0);
  const projectList = page.getByRole('region', { name: 'PROJECTS', exact: true }).locator('ul');
  const measure = list => list.locator(':scope > li').evaluateAll(rows => rows.map(row => { const { x, y, width } = row.getBoundingClientRect(); return { x, y, width, overflow: row.scrollWidth > row.clientWidth + 1 }; }));
  const assertGrid = async list => {
    await expect(list.locator(':scope > li').nth(1)).toBeVisible();
    const boxes = await measure(list);
    expect(boxes[1].x).toBeGreaterThan(boxes[0].x); expect(boxes[0].y).toBe(boxes[1].y);
    expect(boxes.every(box => !box.overflow)).toBe(true);
    if (boxes.length >= 4) { expect(boxes[2].x).toBe(boxes[0].x); expect(boxes[2].y).toBeGreaterThan(boxes[0].y); }
  };
  for (const name of ['PROJECTS', 'TOOLS', 'SERVICES', 'PLUGINS']) await assertGrid(page.getByRole('region', { name, exact: true }).locator('ul'));
  await assertGrid(page.locator('.host-shells > ul'));
  const branch = projectList.locator('li').filter({ has: page.getByRole('link', { name: 'Work', exact: true }) }).locator('.git-badge');
  await expect(branch).toHaveText('feature/Case-Sensitive');
  await expect(projectList.locator('li').filter({ has: page.getByRole('link', { name: 'Work Four', exact: true }) }).locator('.git-badge')).toHaveCount(0);
  for (const row of await page.locator('.shell-row').all()) {
    const title = await row.locator('.row-title').boundingBox(), badge = await row.locator('.badge').boundingBox();
    expect(badge.y).toBeGreaterThan(title.y + title.height);
    expect(badge.x).toBeGreaterThan(title.x);
  }
  for (const row of await page.locator('.managed-row').all()) {
    const badge = await row.locator('.managed-status .badge').boundingBox(), grip = await row.locator('.reorder-control summary').boundingBox();
    expect(Math.abs(badge.y + badge.height / 2 - grip.y - grip.height / 2)).toBeLessThan(2);
    expect(badge.x + badge.width).toBeLessThanOrEqual(grip.x);
  }
  const header = page.locator('.topbar');
  const brandBox = await header.locator('.brand').boundingBox(), hostBox = await header.locator('.host-launch').boundingBox(), actionsBox = await header.locator(':scope > .actions').boundingBox();
  expect(hostBox.x + hostBox.width / 2).toBeCloseTo((await header.boundingBox()).x + (await header.boundingBox()).width / 2, 0);
  expect(brandBox.x + brandBox.width).toBeLessThan(hostBox.x);
  expect(hostBox.x + hostBox.width).toBeLessThan(actionsBox.x);
  const editHost = await header.getByRole('button', { name: 'Edit host', exact: true }).boundingBox(), identity = await header.locator('.host-identity').boundingBox(), launch = await header.getByRole('button', { name: 'Host launch menu' }).boundingBox();
  expect(editHost.x).toBeLessThan(identity.x); expect(identity.x).toBeLessThan(launch.x);
  await header.getByRole('button', { name: 'Host launch menu' }).click();
  await expect(header.getByRole('button', { name: 'Shell', exact: true })).toBeVisible();
  await page.keyboard.press('Escape');
  await page.screenshot({ path: '/tmp/aelab-grid-layout.png', fullPage: true });
  const scriptButtons = page.getByRole('region', { name: 'PLUGINS', exact: true }).locator('.managed-actions').getByRole('button', { name: /^Edit script / });
  await expect(scriptButtons).toHaveCount(4);
  const footer = await page.locator('footer').evaluate(el => { const boxes = [...el.children].map(child => child.getBoundingClientRect()); const left = Math.min(...boxes.map(box => box.left)), right = Math.max(...boxes.map(box => box.right)); return { x: left, width: right - left }; }), section = await page.getByRole('region', { name: 'PROJECTS', exact: true }).boundingBox();
  expect(footer.x + footer.width / 2).toBeCloseTo(section.x + section.width / 2, 0);
  const edit = page.getByRole('region', { name: 'TOOLS', exact: true }).getByRole('button', { name: 'Edit', exact: true }).first();
  const remove = page.getByRole('button', { name: 'Delete tool definition', exact: true }).first();
  expect(await edit.evaluate(el => getComputedStyle(el).backgroundColor)).toBe(await remove.evaluate(el => getComputedStyle(el).backgroundColor));
  await page.getByLabel('Reorder Work', { exact: true }).click();
  await expect(page.getByRole('button', { name: 'Move Work down', exact: true })).toBeVisible();
  await page.getByLabel('Reorder Work', { exact: true }).press('Escape');
  await page.getByRole('button', { name: 'Toggle theme' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.getByRole('button', { name: 'Toggle theme' }).click();
  // Dashboard grids adapt through eight columns.
  for (const [width, columns] of [[1300, 3], [1700, 4], [2100, 5], [2400, 6], [2800, 7], [3200, 8]]) {
    await page.setViewportSize({ width, height: 1000 });
    for (const list of [...await page.locator('section > ul').all(), page.locator('.host-shells > ul')]) {
      const boxes = await measure(list);
      for (let i = 1; i < Math.min(columns, boxes.length); i++) {
        expect(boxes[i].y).toBe(boxes[0].y); expect(boxes[i].x).toBeGreaterThan(boxes[i - 1].x);
      }
      if (boxes.length > columns) { expect(boxes[columns].x).toBe(boxes[0].x); expect(boxes[columns].y).toBeGreaterThan(boxes[0].y); }
      expect(boxes.every(box => !box.overflow)).toBe(true);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
  await page.setViewportSize({ width: 1100, height: 1000 });
  // Reordering uses the same persisted order across columns and into the next grid row.
  await page.getByLabel('Reorder Work', { exact: true }).press('ArrowDown');
  await expect(projectList.locator('.row-title')).toHaveText(['Work Two', 'Work', 'Work Three', 'Work Four']);
  await page.getByLabel('Reorder Work', { exact: true }).press('ArrowDown');
  await expect(projectList.locator('.row-title')).toHaveText(['Work Two', 'Work Three', 'Work', 'Work Four']);
  await page.reload();
  await expect(projectList.locator('.row-title')).toHaveText(['Work Two', 'Work Three', 'Work', 'Work Four']);
  await page.getByRole('button', { name: 'Discovery services', exact: true }).click();
  await assertGrid(page.getByRole('region', { name: 'SERVICES', exact: true }).locator('ul'));
  await page.getByRole('button', { name: 'Add project', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Configure projects', exact: true })).toBeVisible();
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('button', { name: 'all', exact: true }).click();
  await assertGrid(page.getByRole('region', { name: 'HOSTS', exact: true }).locator('ul'));
  for (const [width, columns] of [[1100, 2], [1300, 3], [1700, 4], [2100, 5], [2400, 6], [2800, 7], [3200, 8]]) {
    await page.setViewportSize({ width, height: 1000 });
    const boxes = await measure(page.getByRole('region', { name: 'HOSTS', exact: true }).locator('ul'));
    for (let i = 1; i < columns; i++) { expect(boxes[i].y).toBe(boxes[0].y); expect(boxes[i].x).toBeGreaterThan(boxes[i - 1].x); }
    expect(boxes[columns].x).toBe(boxes[0].x); expect(boxes[columns].y).toBeGreaterThan(boxes[0].y);
  }
  await page.setViewportSize({ width: 1100, height: 1000 });
  await page.getByRole('group', { name: 'Host picker' }).getByRole('button', { name: 'Local Two', exact: true }).click();
  await page.getByRole('button', { name: 'Toggle theme' }).click();
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.getByRole('group', { name: 'Host picker' }).getByRole('button', { name: 'Local', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.setViewportSize({ width: 390, height: 844 });
  const mobile = await measure(projectList);
  const mobileBrand = await header.locator('.brand').boundingBox(), mobileHost = await header.locator('.host-launch').boundingBox();
  expect(mobileHost.y).toBeGreaterThanOrEqual(mobileBrand.y + mobileBrand.height);
  await page.screenshot({ path: '/tmp/aelab-grid-mobile.png', fullPage: true });
  expect(mobile[0].x).toBe(mobile[1].x); expect(mobile[1].y).toBeGreaterThan(mobile[0].y);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.setViewportSize({ width: 1100, height: 1000 });
  const finalConfig = await (await context.request.get(origin + base + '/api/config')).json();
  expect(finalConfig.config.layout).toBeUndefined();
  expect(errors).toEqual([]);
  console.log('PASS: responsive 1–8-column default grid across all sections/discovery, centered host header, long-label wrapping, per-host theme, two-line badges, centered footer, cross-row reordering, host switching and mobile fallback');
} finally { await browser.close(); }
