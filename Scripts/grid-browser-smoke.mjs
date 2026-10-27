import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const origin = process.env.AELAB_TEST_ORIGIN, base = '/lab/aelab';
const browser = await chromium.launch({ headless: true, ...(process.env.AELAB_TEST_BROWSER ? { executablePath: process.env.AELAB_TEST_BROWSER } : {}) });
try {
  const context = await browser.newContext({ viewport: { width: 900, height: 1000 } });
  const page = await context.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  // Display fixtures keep this layout check independent of machine services and sessions.
  const result = { status: 0, output: '', error: '', truncated: false };
  await page.route('**/api/hosts/*/status', route => route.fulfill({ json: { host: 'local', hostname: 'layout-fixture', platform: 'linux', reachable: true, checked: new Date().toISOString(), staleAfterSeconds: 60, connection: result, tmux: { ...result, output: 'one|1|0\ntwo|1|0' }, discovered: [{ provider: 'systemd', target: 'discovered-one.service', state: 'running' }, { provider: 'systemd', target: 'discovered-two.service', state: 'running' }], curated: {}, projectBranches: { work: 'feature/Case-Sensitive', 'work-two': 'main', 'work-three': 'feature/a-very-long-branch-name-for-layout' } } }));
  await page.route('**/api/hosts/*/terminals', route => route.fulfill({ json: [{ id: 'one', number: 1, host: 'local', tool: 'codex', project: 'work', cwd: '/fixture/one' }, { id: 'two', number: 2, host: 'local', project: 'work', cwd: '/fixture/two' }] }));
  await page.goto(origin + base + '/hosts/local/');
  await page.getByLabel('Administrator password').fill(process.env.AELAB_TEST_PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await expect(page.getByRole('link', { name: 'Work', exact: true })).toBeVisible();
  const session = await (await context.request.get(origin + base + '/api/auth/session')).json();
  const snapshot = await (await context.request.get(origin + base + '/api/config')).json();
  const directory = snapshot.config.hosts[0].projects[0].dir;
  const names = ['Codex', 'Claude', 'Pi', 'opencode-with-a-very-long-name-for-grid-layout'];
  snapshot.config.tools = names.map(name => ({ name, executable: '/bin/sh', arguments: [], yoloArguments: ['-i'] }));
  snapshot.config.plugins = ['One', 'Two', 'Three', 'Four plugin with a longer title'].map(name => ({ name, executable: '/bin/true', arguments: [] }));
  snapshot.config.hosts[0].projects = ['Work', 'Work Two', 'Work Three', 'Work Four'].map(name => ({ name, dir: directory + '/a-long-project-path-that-should-wrap-without-overflowing-the-card' }));
  snapshot.config.hosts[0].services = ['One', 'Two', 'Three', 'Four'].map(name => ({ name, provider: 'systemd', target: name.toLowerCase() + '.service' }));
  snapshot.config.hosts[0].tools = ['codex', 'claude', 'pi', names[3]];
  snapshot.config.hosts[0].plugins = ['one', 'two', 'three', 'four-plugin-with-a-longer-title'];
  snapshot.config.hosts.push(...['Local Two', 'Local Three', 'Local Four', 'Local Five', 'Local Six', 'Local Seven', 'Local Eight', 'Local Nine', 'Local Ten', 'Local Eleven', 'Local Twelve', 'Local Thirteen'].map(name => ({ name, transport: 'local', projects: [], services: [], tools: [], plugins: [] })));
  const saved = await context.request.put(origin + base + '/api/config', { data: snapshot, headers: { Origin: origin, 'X-CSRF-Token': session.csrf } });
  expect(saved.status()).toBe(200);
  const resolvedToolPath = '/opt/aelab/tools/bin/codex';
  await page.route('**/api/hosts/*/tools', route => route.fulfill({ json: {
    host: 'local', checked: new Date().toISOString(), staleAfterSeconds: 300,
    tools: snapshot.config.tools.map(tool => ({ tool: { ...tool, id: tool.name.toLowerCase() }, enabled: true, state: 'installed', path: tool.name === 'Codex' ? resolvedToolPath : '/bin/sh' })),
  } }));
  await page.reload();
  await expect(page.getByRole('button', { name: 'Compact layout', exact: true })).toHaveCount(0);
  const projectList = page.getByRole('region', { name: 'PROJECTS', exact: true }).locator('ul');
  await expect(page.locator('.dashboard')).toHaveCSS('padding-left', '36px');
  await expect(page.locator('.dashboard')).toHaveCSS('padding-right', '36px');
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
  await expect(page.locator('.pinned-row .row-title')).toHaveText(['Codex@Work', 'shell@Work']);
  for (const chip of [
    projectList.locator('.path-chip').first(),
    page.locator('.pinned-row .path-chip').first(),
    page.getByRole('region', { name: 'TOOLS', exact: true }).locator('.path-chip').first(),
  ]) {
    const full = await chip.getAttribute('title'), short = full.split('/').filter(Boolean).slice(-2).join('/');
    await expect(chip).toHaveText(short); await expect(chip).toHaveAttribute('aria-expanded', 'false');
    const card = chip.locator('xpath=ancestor::li[1]');
    const before = await card.boundingBox(), pathBefore = await chip.boundingBox();
    await chip.click(); await expect(chip).toHaveText(full); await expect(chip).toHaveAttribute('aria-expanded', 'true');
    expect((await card.boundingBox()).height).toBeCloseTo(before.height, 1);
    expect((await chip.boundingBox()).height).toBeCloseTo(pathBefore.height, 1);
    await chip.press('Enter'); await expect(chip).toHaveText(short); await expect(chip).toHaveAttribute('aria-expanded', 'false');
  }
  const branch = projectList.locator('li').filter({ has: page.getByRole('link', { name: 'Work', exact: true }) }).locator('.git-badge');
  await expect(branch).toHaveText('feature/Case-Sensitive');
  const singleLine = badge => badge.evaluate(element => {
    const style = getComputedStyle(element);
    return element.getBoundingClientRect().height <= parseFloat(style.lineHeight) + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom) + 1;
  });
  expect(await singleLine(branch)).toBe(true);
  const longBranch = projectList.locator('li').filter({ has: page.getByRole('link', { name: 'Work Three', exact: true }) }).locator('.git-badge');
  await page.setViewportSize({ width: 2400, height: 1000 });
  expect(await singleLine(longBranch)).toBe(true);
  const metadataCard = longBranch.locator('xpath=ancestor::li[1]'), metadataPath = metadataCard.locator('.path-chip');
  const metadataHeight = (await metadataCard.boundingBox()).height;
  await metadataPath.click(); expect((await metadataCard.boundingBox()).height).toBeCloseTo(metadataHeight, 1);
  expect(await singleLine(longBranch)).toBe(true);
  await metadataPath.click();
  await page.setViewportSize({ width: 900, height: 1000 });
  await expect(projectList.locator('li').filter({ has: page.getByRole('link', { name: 'Work Four', exact: true }) }).locator('.git-badge')).toHaveCount(0);
  for (const row of await page.locator('.shell-row').all()) {
    const title = await row.locator('.row-title').boundingBox(), badge = await row.locator('.shell-badges .badge').boundingBox();
    expect(badge.y).toBeGreaterThan(title.y + title.height);
    expect(badge.x).toBeGreaterThan(title.x);
  }
  for (const row of await page.locator('.managed-row').all()) {
    const badge = await row.locator('.managed-status .badge').boundingBox(), grip = await row.locator('.reorder-control summary').boundingBox();
    expect(Math.abs(badge.y + badge.height / 2 - grip.y - grip.height / 2)).toBeLessThan(2);
    expect(badge.x + badge.width).toBeLessThanOrEqual(grip.x);
  }
  const filters = page.getByRole('group', { name: 'Shell filter', exact: true });
  await expect(filters.getByRole('button', { name: 'all', exact: true })).toHaveText('all');
  await expect(page.getByLabel('Shell count', { exact: true })).toHaveText('4');
  await filters.getByRole('button', { name: 'pinned', exact: true }).click();
  await expect(filters.getByRole('button', { name: 'pinned', exact: true })).toHaveText('pinned');
  await expect(page.getByLabel('Shell count', { exact: true })).toHaveText('2');
  await expect(filters.getByRole('button', { name: 'all', exact: true })).toHaveText('all');
  await expect(page.locator('.host-shells > ul > li')).toHaveCount(2);
  await filters.getByRole('button', { name: 'tmux', exact: true }).click();
  await expect(filters.getByRole('button', { name: 'tmux', exact: true })).toHaveText('tmux');
  await expect(page.getByLabel('Shell count', { exact: true })).toHaveText('2');
  await expect(page.locator('.host-shells .pinned-row')).toHaveCount(0);
  await expect(page.locator('.host-shells .shell-row')).toHaveCount(2);
  await filters.getByRole('button', { name: 'all', exact: true }).click();
  await expect(page.locator('.host-shells > ul > li')).toHaveCount(4);
  const hostPicker = page.getByRole('group', { name: 'Host picker' });
  const expandedTop = (await hostPicker.boundingBox()).y;
  const headingTop = (await page.locator('.dashboard-content > .picker-heading').boundingBox()).y;
  await page.getByRole('button', { name: 'Hide shells', exact: true }).click();
  await expect(page.getByLabel('Pinned shell shortcuts', { exact: true })).toBeVisible();
  const shortcuts = page.getByLabel('Pinned shell shortcuts', { exact: true });
  const shortcutsBox = await shortcuts.boundingBox(), navBox = await hostPicker.locator('nav').boundingBox(), collapseBox = await page.getByRole('button', { name: 'Show shells', exact: true }).boundingBox();
  expect(shortcutsBox.x).toBeGreaterThanOrEqual(navBox.x + navBox.width);
  expect(shortcutsBox.x + shortcutsBox.width).toBeLessThanOrEqual(collapseBox.x);
  expect(shortcutsBox.y + shortcutsBox.height / 2).toBeCloseTo(collapseBox.y + collapseBox.height / 2, 0);

  expect((await hostPicker.boundingBox()).y).toBe(expandedTop);
  expect((await page.locator('.dashboard-content > .picker-heading').boundingBox()).y).toBe(headingTop);
  await page.getByRole('button', { name: 'Show shells', exact: true }).click();
  expect((await hostPicker.boundingBox()).y).toBe(expandedTop);
  const header = page.locator('.topbar');
  const brandBox = await header.locator('.brand').boundingBox(), hostBox = await header.locator('.host-launch').boundingBox(), actionsBox = await header.locator(':scope > .actions').boundingBox();
  expect(hostBox.x - brandBox.x - brandBox.width).toBeLessThan(60);
  expect(brandBox.x + brandBox.width).toBeLessThan(hostBox.x);
  expect(hostBox.x + hostBox.width).toBeLessThan(actionsBox.x);
  const hostname = header.getByRole('button', { name: 'layout-fixture', exact: true });
  const platform = await header.locator('.host-platform').boundingBox(), hostnameBox = await hostname.boundingBox(), launch = await header.getByRole('button', { name: 'Host launch menu' }).boundingBox();
  expect(platform.x).toBeLessThan(hostnameBox.x); expect(hostnameBox.x).toBeLessThan(launch.x);
  await hostname.click();
  await expect(page.getByRole('dialog', { name: 'Configure host', exact: true })).toBeVisible();
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  await header.getByRole('button', { name: 'Host launch menu' }).click();
  await expect(header.getByRole('button', { name: 'Shell', exact: true })).toBeVisible();
  await page.keyboard.press('Escape');
  await page.screenshot({ path: '/tmp/aelab-grid-layout.png', fullPage: true });
  const scriptButtons = page.getByRole('region', { name: 'PLUGINS', exact: true }).locator('.managed-actions').getByRole('button', { name: /^Edit script / });
  await expect(scriptButtons).toHaveCount(4);
  const footer = await page.locator('footer').evaluate(el => { const boxes = [...el.children].map(child => child.getBoundingClientRect()); const left = Math.min(...boxes.map(box => box.left)), right = Math.max(...boxes.map(box => box.right)); return { x: left, width: right - left }; }), section = await page.getByRole('region', { name: 'PROJECTS', exact: true }).boundingBox();
  expect(footer.x + footer.width / 2).toBeCloseTo(section.x + section.width / 2, 0);
  const servicesSection = page.getByRole('region', { name: 'SERVICES', exact: true });
  await expect(servicesSection.getByRole('button', { name: 'Refresh services', exact: true })).toHaveCount(0);
  await servicesSection.getByRole('button', { name: 'Discovery services', exact: true }).click();
  await expect(servicesSection.locator('h2').getByRole('button', { name: 'Refresh services', exact: true })).toBeVisible();
  await expect(servicesSection.locator('.discovery-filter').getByRole('button', { name: 'Refresh services', exact: true })).toHaveCount(0);
  await servicesSection.getByRole('button', { name: 'Discovery services', exact: true }).click();
  const toolsSection = page.getByRole('region', { name: 'TOOLS', exact: true });
  await expect(toolsSection.getByRole('button', { name: 'Refresh tools', exact: true })).toHaveCount(0);
  const toolPath = toolsSection.locator('.path-chip').first();
  await expect(toolPath).toHaveText('bin/codex');
  await toolPath.click(); await expect(toolPath).toHaveText(resolvedToolPath);

  await toolsSection.getByRole('button', { name: 'Discovery tools', exact: true }).click();
  const refreshTools = toolsSection.locator('h2').getByRole('button', { name: 'Refresh tools', exact: true });
  await expect(refreshTools).toBeVisible();
  await expect(toolPath).toHaveText(resolvedToolPath);
  await toolPath.click(); await expect(toolPath).toHaveText('bin/codex');

  await expect(toolsSection).not.toContainText('cached for');
  await expect(refreshTools).toBeEnabled(); await refreshTools.click();
  await toolsSection.getByRole('button', { name: 'Discovery tools', exact: true }).click();
  await expect(refreshTools).toHaveCount(0);
  await expect(toolPath).toHaveText('bin/codex');
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
  for (const [width, columns] of [[1000, 2], [1340, 3], [1800, 4], [2200, 5], [2600, 6], [3000, 7], [3400, 8], [3900, 9], [4300, 10]]) {
    await page.setViewportSize({ width, height: 1000 });
    if (width >= 1200) {
      await expect(page.locator('.dashboard')).toHaveCSS('padding-left', '48px');
      await expect(page.locator('.dashboard')).toHaveCSS('padding-right', '48px');
    }
    for (const list of [...await page.locator('section > ul').all(), page.locator('.host-shells > ul')]) {
      const boxes = await measure(list);
      for (let i = 1; i < Math.min(columns, boxes.length); i++) {
        expect(boxes[i].y).toBe(boxes[0].y); expect(boxes[i].x).toBeGreaterThan(boxes[i - 1].x);
      }
      if (boxes.length > columns) { expect(boxes[columns].x).toBe(boxes[0].x); expect(boxes[columns].y).toBeGreaterThan(boxes[0].y); }
      expect(boxes.every(box => !box.overflow)).toBe(true);
      for (const box of boxes) expect(box.width).toBeGreaterThanOrEqual(384);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
  await page.setViewportSize({ width: 900, height: 1000 });
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
  await expect(page.getByRole('dialog', { name: 'Configure project', exact: true })).toBeVisible();
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.getByRole('group', { name: 'Host picker' }).getByRole('button', { name: 'all', exact: true }).click();
  await assertGrid(page.getByRole('region', { name: 'HOSTS', exact: true }).locator('ul'));
  for (const [width, columns] of [[390, 1], [740, 1], [900, 2], [1340, 3], [1800, 4], [2200, 5], [2600, 6], [3000, 7], [3400, 8], [3900, 9], [4300, 10]]) {
    await page.setViewportSize({ width, height: 1000 });
    if (width >= 1200) {
      await expect(page.locator('.dashboard')).toHaveCSS('padding-left', '48px');
      await expect(page.locator('.dashboard')).toHaveCSS('padding-right', '48px');
    }
    const boxes = await measure(page.getByRole('region', { name: 'HOSTS', exact: true }).locator('ul'));
    const grid = page.getByRole('region', { name: 'HOSTS', exact: true }).locator('ul');
    const geometry = await grid.evaluate(element => ({ width: element.clientWidth, gap: parseFloat(getComputedStyle(element).columnGap) }));
    const expectedWidth = (geometry.width - geometry.gap * (columns - 1)) / columns;
    for (const box of boxes) expect(box.width).toBeCloseTo(expectedWidth, 0);
    for (let i = 1; i < columns; i++) { expect(boxes[i].y).toBe(boxes[0].y); expect(boxes[i].x).toBeGreaterThan(boxes[i - 1].x); }
    expect(boxes[columns].x).toBe(boxes[0].x); expect(boxes[columns].y).toBeGreaterThan(boxes[0].y);
    if (width === 3900) await page.screenshot({ path: '/tmp/aelab-fixed-card-grid.png' });
  }
  await page.setViewportSize({ width: 900, height: 1000 });
  await page.getByRole('group', { name: 'Host picker' }).getByRole('button', { name: 'Local Two', exact: true }).click();
  await page.getByRole('button', { name: 'Toggle theme' }).click();
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.getByRole('group', { name: 'Host picker' }).getByRole('button', { name: 'Local', exact: true }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.setViewportSize({ width: 390, height: 844 });
  const mobile = await measure(projectList);
  await expect(page.locator('.dashboard')).toHaveCSS('padding-left', '24px');
  await expect(page.locator('.dashboard')).toHaveCSS('padding-right', '24px');
  const mobileBrand = await header.locator('.brand').boundingBox(), mobileHost = await header.locator('.host-launch').boundingBox();
  expect(mobileHost.y).toBeGreaterThanOrEqual(mobileBrand.y + mobileBrand.height);
  await page.getByRole('button', { name: 'Hide shells', exact: true }).click();
  const mobilePins = await page.getByLabel('Pinned shell shortcuts', { exact: true }).boundingBox(), mobileExpand = await page.getByRole('button', { name: 'Show shells', exact: true }).boundingBox();
  expect(mobilePins.x + mobilePins.width).toBeLessThanOrEqual(mobileExpand.x);
  expect(mobilePins.y + mobilePins.height / 2).toBeCloseTo(mobileExpand.y + mobileExpand.height / 2, 0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({ path: '/tmp/aelab-host-shortcuts-mobile.png' });
  await page.getByRole('button', { name: 'Show shells', exact: true }).click();
  await page.screenshot({ path: '/tmp/aelab-grid-mobile.png', fullPage: true });
  expect(mobile[0].x).toBe(mobile[1].x); expect(mobile[1].y).toBeGreaterThan(mobile[0].y);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.setViewportSize({ width: 900, height: 1000 });
  await expect(servicesSection.locator('.macos-service-discovery')).toHaveCount(0);
  await page.route('**/api/hosts/local/status', route => route.fulfill({ json: {
    host: 'local', hostname: 'layout-fixture', platform: 'macos', reachable: true, checked: new Date().toISOString(), staleAfterSeconds: 60,
    connection: result, tmux: result, discovered: [
      { provider: 'launchd', target: 'short', state: 'running' },
      { provider: 'launchd', target: 'com.example.a-very-long-macos-service-name-that-wraps-across-multiple-lines', state: 'running' },
    ], curated: {},
  } }));
  const macFilter = servicesSection.getByRole('button', { name: 'Discovery services', exact: true });
  if (await macFilter.getAttribute('aria-pressed') !== 'true') await macFilter.click();
  await page.getByRole('button', { name: 'Refresh services', exact: true }).click();
  const macRows = servicesSection.locator('.macos-service-discovery');
  await expect(macRows).toHaveCount(2);
  const bottoms = [];
  for (const row of await macRows.all()) {
    const card = await row.boundingBox(), pin = await row.getByRole('button', { name: /^Pin service / }).boundingBox();
    expect(card.x + card.width - pin.x - pin.width).toBeCloseTo(17, 0);
    expect(card.y + card.height - pin.y - pin.height).toBeCloseTo(15, 0);
    const subtitle = await row.locator('small').boundingBox();
    expect(subtitle.x + subtitle.width).toBeLessThanOrEqual(pin.x);
    expect(subtitle.y + subtitle.height / 2).toBeCloseTo(pin.y + pin.height / 2, 0);
    bottoms.push(pin.y + pin.height);
  }
  expect(bottoms[0]).toBeCloseTo(bottoms[1], 0);
  const finalConfig = await (await context.request.get(origin + base + '/api/config')).json();
  expect(finalConfig.config.layout).toBeUndefined();
  expect(errors).toEqual([]);
  console.log('PASS: stretching cards with a 384px minimum, responsive 1–10 columns with no cap across all sections/discovery, left-aligned host header, shell counts and inline pinned shortcuts, discovery refresh, long-label wrapping, per-host theme, two-line badges, centered footer, cross-row reordering, host switching and mobile fallback');
} finally { await browser.close(); }
