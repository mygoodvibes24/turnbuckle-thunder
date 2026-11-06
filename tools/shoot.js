// Usage: node shoot.js <url> <outdir> [seconds]
const { chromium } = require('playwright');
(async () => {
  const url = process.argv[2], out = process.argv[3], secs = +(process.argv[4] || 25);
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const logs = [];
  page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
  await page.goto(url, { waitUntil: 'load', timeout: 120000 });
  await page.mouse.click(640, 360);
  for (let t = 0; t < secs; t += 5) {
    await page.waitForTimeout(5000);
    await page.screenshot({ path: `${out}/t${String(t + 5).padStart(2, '0')}.png` });
  }
  // Walk toward the opponent and grab to see a lock-up
  await page.keyboard.down('KeyD'); await page.waitForTimeout(1500); await page.keyboard.up('KeyD');
  await page.screenshot({ path: `${out}/walk.png` });
  await page.keyboard.press('KeyK'); await page.waitForTimeout(700);
  await page.screenshot({ path: `${out}/grab.png` });
  await page.keyboard.press('KeyJ'); await page.waitForTimeout(900);
  await page.screenshot({ path: `${out}/move.png` });
  require('fs').writeFileSync(`${out}/console.log`, logs.join('\n'));
  await browser.close();
})();
