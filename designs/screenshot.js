const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/snap/bin/chromium',
    headless: 'new',
    args: ['--no-sandbox', '--disable-gpu', '--window-size=1440,900']
  });
  const page = await browser.newPage();
  await page.setViewport({width:1440, height:900});
  await page.goto('http://localhost:9999/', {waitUntil: 'networkidle2'});
  await new Promise(r => setTimeout(r, 2000));
  await page.screenshot({path: '/root/.openclaw/workspace/designs/zozobet-top.png'});
  await page.evaluate(() => window.scrollBy(0, 700));
  await new Promise(r => setTimeout(r, 1000));
  await page.screenshot({path: '/root/.openclaw/workspace/designs/zozobet-mid.png'});
  await page.screenshot({path: '/root/.openclaw/workspace/designs/zozobet-full.png', fullPage: true});
  console.log('Done');
  await browser.close();
  process.exit(0);
})();
