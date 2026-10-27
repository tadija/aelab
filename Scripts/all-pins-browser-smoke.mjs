import { chromium } from '../Frontend/node_modules/playwright/index.mjs';
import { expect } from '../Frontend/node_modules/@playwright/test/index.mjs';
const browser = await chromium.launch({headless:true,...(process.env.AELAB_TEST_BROWSER ? {executablePath:process.env.AELAB_TEST_BROWSER} : {})});
try {
const page = await browser.newPage(); const errors=[]; page.on('pageerror',e=>errors.push(e.message));
const hosts=['Alpha','Beta'].map(name=>({name,tint:name === 'Alpha' ? '#22aa66' : '#bb55cc',transport:'local',projects:[],services:[],tools:[],plugins:[]}));
const pins={alpha:[{host:'alpha',id:'same',number:1,cwd:'/home/alpha',programStatus:{id:'root',state:'working'}}],beta:[{host:'beta',id:'same',number:1,cwd:'/home/beta',programStatus:{id:'root',state:'blocked',kind:'question'}}]};
let deleted='';
await page.route('**/api/**',async route=>{
 const p=new URL(route.request().url()).pathname;
 let data={};
 if(p.endsWith('/auth/session'))data={csrf:'test'};
 else if(p.endsWith('/config'))data={revision:'1',config:{version:1,hosts,tools:[],plugins:[],paths:[],ttyButtons:[]}};
 else if(p.endsWith('/terminals'))data=pins[p.split('/')[3]];
 else if(route.request().method()==='DELETE'){deleted=p; pins.beta=[];}
 else if(p.endsWith('/status'))data={reachable:true,checked:new Date().toISOString(),staleAfterSeconds:60,connection:{status:0},tmux:{status:0,output:''},curated:{},discovered:[]};
 else if(p.endsWith('/tools'))data={tools:[]};
 else if(p.endsWith('/plugins'))data=[];
 await route.fulfill({json:data});
});
await page.goto(process.env.AELAB_TEST_ORIGIN ?? 'http://127.0.0.1:5173');
const section=page.getByRole('region',{name:'SHELLS',exact:true});
await expect(section.locator('.pinned-row')).toHaveCount(2);
await expect(section.locator('.row-title')).toHaveText(['shell@alpha','shell@beta']);
await expect(section.locator('.shell-badges a')).toHaveText(['Alpha','Beta']);
await expect(section.locator('.pinned-badge')).toHaveCount(0);
await expect(section.locator('.pin-number')).toHaveText(['1','2']);
await expect(section.locator('.pin-number').first()).toHaveCSS('color','rgb(34, 170, 102)');
await expect(section.locator('.pin-number').nth(1)).toHaveCSS('color','rgb(187, 85, 204)');
await expect(section.locator('.host-badge').first()).toHaveCSS('color','rgb(34, 170, 102)');
expect(await section.locator('.host-badge').first().evaluate(el => getComputedStyle(el).backgroundColor)).not.toBe('rgba(0, 0, 0, 0)');
await page.locator('body').click({position:{x:5,y:5}});
const opened = page.waitForEvent('popup'); await page.keyboard.press('2');
const popup = await opened;
await expect.poll(() => popup.url()).toContain('/hosts/beta/tty/pinned/same/');
await popup.close();

await expect(section.locator('.row-title').nth(1)).toHaveAttribute('href','/hosts/beta/tty/pinned/same/');
await expect(section.locator('.pin-program-status').nth(1)).toHaveText('answer needed');
await expect(section.locator('.pin-program-status').first()).toHaveAttribute('data-tone','warning');
await section.getByRole('button',{name:'SHELLS',exact:true}).click();
await expect(section.locator('.pinned-row')).toHaveCount(0);
await section.getByRole('button',{name:'SHELLS',exact:true}).click();
page.on('dialog',d=>d.accept());
await section.locator('.shell-actions button').nth(1).click();
await expect(section.locator('.pinned-row')).toHaveCount(1);
expect(deleted).toBe('/api/hosts/beta/terminals/same');
pins.alpha[0].programStatus={id:'root',state:'done'};
await expect(section.locator('.pin-program-status')).toHaveText('done',{timeout:4000});
await page.getByRole('group',{name:'Host picker'}).getByRole('button',{name:'Alpha',exact:true}).click();
await expect(page.locator('.host-shells .pinned-row')).toHaveCount(1);
await expect(page.locator('.host-shells .pinned-badge')).toHaveText('pinned');
expect(errors).toEqual([]);
console.log('All-host pins: badges, links, collapse, host-specific delete, live status, and host cards passed');
}finally{await browser.close()}
