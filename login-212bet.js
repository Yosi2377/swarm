const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/snap/bin/chromium',
    headless: 'new',
    args: ['--no-sandbox', '--disable-gpu', '--window-size=1400,900',
           '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36']
  });
  const page = await browser.newPage();
  await page.setViewport({width:1400, height:900});
  await page.goto('https://212bet.io', {waitUntil: 'networkidle2', timeout: 30000});
  await new Promise(r => setTimeout(r, 5000));
  const inputs = await page.$$('input');
  console.log('Found inputs:', inputs.length);
  if (inputs.length >= 2) {
    await inputs[0].type('Gogo');
    await inputs[1].type('1111');
    await new Promise(r => setTimeout(r, 500));
    const btns = await page.$$('button');
    if (btns.length > 0) await btns[0].click();
    await new Promise(r => setTimeout(r, 10000));
    await page.screenshot({path: '/root/.openclaw/workspace/212bet-main.png', fullPage: false});
    console.log('Main page screenshot taken');
    
    // Take scrolled screenshots
    for (let i = 1; i <= 4; i++) {
      await page.evaluate(() => window.scrollBy(0, 800));
      await new Promise(r => setTimeout(r, 2000));
      await page.screenshot({path: '/root/.openclaw/workspace/212bet-scroll' + i + '.png'});
      console.log('Scroll ' + i + ' screenshot');
    }
    
    // Try sports section
    const links = await page.$$('a');
    for (const l of links) {
      const t = await l.evaluate(el => el.textContent).catch(()=>'');
      if (t.toLowerCase().includes('sport')) { await l.click(); break; }
    }
    await new Promise(r => setTimeout(r, 5000));
    await page.screenshot({path: '/root/.openclaw/workspace/212bet-sports.png'});
    console.log('Sports screenshot');
  }
  console.log('Done');
  await browser.close();
})();
