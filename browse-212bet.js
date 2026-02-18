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
  
  // Fill all inputs
  const inputs = await page.$$('input');
  console.log('Inputs found:', inputs.length);
  for (let i = 0; i < inputs.length; i++) {
    const type = await inputs[i].evaluate(el => ({type: el.type, name: el.name, placeholder: el.placeholder}));
    console.log('Input', i, JSON.stringify(type));
  }
  
  // Clear and type username
  for (const inp of inputs) {
    const ph = await inp.evaluate(el => el.placeholder.toLowerCase());
    if (ph.includes('login') || ph.includes('user') || ph.includes('id')) {
      await inp.click({clickCount: 3});
      await inp.type('Gogo');
      console.log('Typed username in:', ph);
    }
    if (ph.includes('pass') || ph.includes('סיסמ')) {
      await inp.click({clickCount: 3});
      await inp.type('1111');
      console.log('Typed password in:', ph);
    }
  }
  
  // If no placeholders matched, try by index
  if (inputs.length >= 2) {
    const v0 = await inputs[0].evaluate(el => el.value);
    const v1 = await inputs[1].evaluate(el => el.value);
    if (!v0) { await inputs[0].click({clickCount:3}); await inputs[0].type('Gogo'); }
    if (!v1) { await inputs[1].click({clickCount:3}); await inputs[1].type('1111'); }
  }
  
  await page.screenshot({path: '/root/.openclaw/workspace/212bet-pre-login.png'});
  
  // Click submit
  await page.evaluate(() => {
    const btns = document.querySelectorAll('button, input[type=submit], .login-btn, [type=button]');
    btns.forEach(b => console.log('BTN:', b.tagName, b.textContent, b.className));
    for (const b of btns) {
      if (b.textContent.toLowerCase().includes('login') || b.textContent.includes('כניסה') || b.querySelector('svg')) {
        b.click();
        return;
      }
    }
    if (btns.length) btns[btns.length-1].click();
  });
  
  await new Promise(r => setTimeout(r, 10000));
  console.log('URL after login:', page.url());
  await page.screenshot({path: '/root/.openclaw/workspace/212bet-dashboard.png', fullPage: false});
  
  // Scroll through dashboard
  for (let i = 1; i <= 5; i++) {
    await page.evaluate(() => window.scrollBy(0, 700));
    await new Promise(r => setTimeout(r, 2000));
    await page.screenshot({path: '/root/.openclaw/workspace/212bet-dash-' + i + '.png'});
  }
  
  // Try clicking on Sports / Casino sections
  const navLinks = await page.$$('a, [role=tab], nav *');
  for (const link of navLinks.slice(0, 30)) {
    const text = await link.evaluate(el => el.textContent.trim()).catch(()=>'');
    if (text.toLowerCase().match(/sport|casino|live|slot/)) {
      console.log('Clicking nav:', text);
      await link.click().catch(()=>{});
      await new Promise(r => setTimeout(r, 5000));
      await page.screenshot({path: '/root/.openclaw/workspace/212bet-section.png'});
      break;
    }
  }
  
  console.log('DONE');
  await browser.close();
})();
