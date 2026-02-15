const puppeteer = require('puppeteer');
const fs = require('fs');

const url = process.argv[2];
const testFile = process.argv[3];
const tests = JSON.parse(fs.readFileSync(testFile, 'utf8'));

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: '/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome',
    args: ['--no-sandbox']
  });
  const page = await browser.newPage();
  await page.setViewport({width: 1400, height: 900});
  
  // Collect JS errors
  const jsErrors = [];
  const ignorePat = /favicon|stylesheet|Cross-Origin-Opener-Policy|status of 40[134]/i;
  page.on('pageerror', err => { if (!ignorePat.test(err.message)) jsErrors.push(err.message); });
  page.on('console', msg => { if (msg.type() === 'error' && !ignorePat.test(msg.text())) jsErrors.push(msg.text()); });
  
  await page.goto(url, {waitUntil: 'networkidle2', timeout: 15000});
  await new Promise(r => setTimeout(r, 2000));
  
  let passed = 0, failed = 0, results = [];
  
  for (const test of tests.tests) {
    try {
      switch(test.type) {
        case 'exists':
          const el = await page.$(test.selector);
          if (el) { passed++; results.push(`✅ ${test.desc}`); }
          else { failed++; results.push(`❌ ${test.desc} — selector "${test.selector}" not found`); }
          break;
        case 'text':
          const text = await page.$eval(test.selector, el => el.textContent);
          if (text.includes(test.contains)) { passed++; results.push(`✅ ${test.desc}`); }
          else { failed++; results.push(`❌ ${test.desc} — expected "${test.contains}", got "${text.substring(0,50)}"`); }
          break;
        case 'count':
          const els = await page.$$(test.selector);
          if (els.length >= test.min) { passed++; results.push(`✅ ${test.desc} (found ${els.length})`); }
          else { failed++; results.push(`❌ ${test.desc} — expected min ${test.min}, found ${els.length}`); }
          break;
        case 'click':
          const btn = await page.$(test.selector);
          if (btn) { await btn.click(); await new Promise(r => setTimeout(r, 1000)); passed++; results.push(`✅ ${test.desc}`); }
          else { failed++; results.push(`❌ ${test.desc} — button "${test.selector}" not found`); }
          break;
        case 'noErrors':
          if (jsErrors.length === 0) { passed++; results.push(`✅ ${test.desc}`); }
          else { failed++; results.push(`❌ ${test.desc} — ${jsErrors.length} errors: ${jsErrors.slice(0,3).join('; ')}`); }
          break;
        case 'screenshot':
          await page.screenshot({path: test.path, fullPage: true});
          passed++; results.push(`✅ Screenshot saved: ${test.path}`);
          break;
      }
    } catch(e) {
      failed++; results.push(`❌ ${test.desc} — ${e.message}`);
    }
  }
  
  await browser.close();
  
  const total = passed + failed;
  results.forEach(r => console.log('  ' + r));
  if (failed === 0) {
    console.log(`\nPASS: ${passed}/${total} browser tests passed`);
    process.exit(0);
  } else {
    console.log(`\nFAIL: ${passed}/${total} browser tests passed`);
    process.exit(1);
  }
})();
