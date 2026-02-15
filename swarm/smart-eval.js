#!/usr/bin/env node
/**
 * Smart Evaluator — When tests fail, investigate WHY before giving feedback.
 * 
 * Usage: node smart-eval.js <url> [--task <file.md>] [--project <name>]
 * 
 * Flow:
 * 1. Login if needed
 * 2. Run browser tests
 * 3. If ANY test fails → investigate:
 *    a. Capture console errors
 *    b. Capture network failures (4xx, 5xx)
 *    c. Check if page redirected (auth issue?)
 *    d. Check what elements ARE on the page
 *    e. Take screenshot of current state
 * 4. Output: PASS/FAIL + detailed diagnosis
 */

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const CHROME = '/root/.cache/puppeteer/chrome/linux-145.0.7632.46/chrome-linux64/chrome';

const LOGIN_CREDS = {
  '9089': { user: 'zozo', pass: '123456' },
  '8089': { user: 'zozo', pass: '123456' },
  '9088': { user: 'admin', pass: 'admin123' },
  '8088': { user: 'admin', pass: 'admin123' },
};

function parseTaskTests(taskPath) {
  const content = fs.readFileSync(taskPath, 'utf8');
  const match = content.match(/## Browser Tests\n([\s\S]*?)(?=\n## |\n$|$)/);
  if (!match) return [];
  return match[1].split('\n')
    .filter(l => l.trim().startsWith('- '))
    .map(line => {
      const clean = line.replace(/^[\s-]+/, '');
      const parts = clean.split('→').map(s => s.trim());
      const first = parts[0];
      const colonIdx = first.indexOf(':');
      const type = colonIdx > -1 ? first.substring(0, colonIdx).trim() : first.trim();
      const selector = colonIdx > -1 ? first.substring(colonIdx + 1).trim() : '';
      const desc = parts[parts.length - 1].replace(/^"(.*)"$/, '$1');
      const test = { type, selector, desc };
      for (let i = 1; i < parts.length - 1; i++) {
        const p = parts[i].trim();
        if (p.startsWith('contains:')) test.contains = p.replace('contains:', '').trim();
        if (p.startsWith('min:')) test.min = parseInt(p.replace('min:', '').trim());
        if (p.startsWith('max:')) test.max = parseInt(p.replace('max:', '').trim());
        if (p.startsWith('waitFor:')) test.waitFor = p.replace('waitFor:', '').trim();
      }
      return test;
    });
}

async function investigate(page, failedTests) {
  const diagnosis = [];
  
  // 1. Current URL (did it redirect?)
  const currentUrl = page.url();
  diagnosis.push(`📍 Current URL: ${currentUrl}`);
  
  // 2. Page title
  const title = await page.title().catch(() => 'unknown');
  diagnosis.push(`📄 Page title: "${title}"`);
  
  // 3. Check if it's a login page
  // Check if STILL on login (not just that login inputs exist hidden in DOM)
  const bodyText2 = await page.evaluate(() => document.body?.innerText?.substring(0, 500) || '').catch(() => '');
  const isLoggedIn = bodyText2.includes('יתרה') || bodyText2.includes('balance') || bodyText2.includes('logout') || bodyText2.includes('יציאה');
  const visiblePasswordInputs = await page.$$eval('input[type="password"]', els => els.filter(el => el.offsetParent !== null).length).catch(() => 0);
  if (visiblePasswordInputs > 0 && !isLoggedIn) {
    diagnosis.push('🔒 DIAGNOSIS: Page shows a LOGIN FORM — authentication failed or session expired!');
    diagnosis.push('   FIX: Check if login credentials are correct, or if cookies are being set properly');
  } else if (isLoggedIn) {
    diagnosis.push('✅ User is logged in');
  }
  
  // 4. What elements ARE visible on page
  const bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 500) || '').catch(() => '');
  if (bodyText.length < 50) {
    diagnosis.push('⚠️ DIAGNOSIS: Page is mostly EMPTY — content not loading');
  }
  diagnosis.push(`📝 Page text (first 200 chars): "${bodyText.substring(0, 200).replace(/\n/g, ' ')}"`);
  
  // 5. Count common elements
  const elementCounts = await page.evaluate(() => {
    return {
      tr: document.querySelectorAll('tr').length,
      td: document.querySelectorAll('td').length,
      div: document.querySelectorAll('div').length,
      button: document.querySelectorAll('button').length,
      table: document.querySelectorAll('table').length,
      form: document.querySelectorAll('form').length,
      a: document.querySelectorAll('a').length,
      img: document.querySelectorAll('img').length,
      modal: document.querySelectorAll('[class*="modal"],[id*="modal"]').length,
    };
  }).catch(() => ({}));
  diagnosis.push(`📊 Elements on page: ${JSON.stringify(elementCounts)}`);
  
  // 6. For each failed test, check what's actually there
  for (const test of failedTests) {
    if (test.selector) {
      // Try broader selectors
      const exists = await page.$(test.selector).catch(() => null);
      if (!exists) {
        // Try to find similar elements
        const tag = test.selector.match(/^(\w+)/)?.[1] || '';
        const id = test.selector.match(/#([\w-]+)/)?.[1] || '';
        const cls = test.selector.match(/\.([\w-]+)/)?.[1] || '';
        
        if (id) {
          const similar = await page.evaluate((id) => {
            const all = document.querySelectorAll('[id]');
            return Array.from(all).map(e => e.id).filter(i => i.toLowerCase().includes(id.toLowerCase().substring(0, 4))).slice(0, 5);
          }, id).catch(() => []);
          if (similar.length) diagnosis.push(`   🔎 Similar IDs found: ${similar.join(', ')}`);
        }
        if (cls) {
          const similar = await page.evaluate((cls) => {
            const all = document.querySelectorAll('[class]');
            const classes = new Set();
            all.forEach(e => e.classList.forEach(c => { if (c.toLowerCase().includes(cls.toLowerCase().substring(0, 4))) classes.add(c); }));
            return Array.from(classes).slice(0, 5);
          }, cls).catch(() => []);
          if (similar.length) diagnosis.push(`   🔎 Similar classes found: ${similar.join(', ')}`);
        }
        
        diagnosis.push(`   ❌ "${test.desc}": selector "${test.selector}" not found`);
      }
    }
  }
  
  // 7. Screenshot current state
  const screenshotPath = '/tmp/eval-diagnosis.png';
  await page.screenshot({ path: screenshotPath, fullPage: false }).catch(() => {});
  diagnosis.push(`📸 Screenshot: ${screenshotPath}`);
  
  return diagnosis;
}

async function main() {
  const args = process.argv.slice(2);
  let url = args[0];
  let tests = [];
  let taskFile = null;
  
  for (let i = 1; i < args.length; i++) {
    if (args[i] === '--task' && args[i + 1]) {
      taskFile = args[i + 1];
      tests = parseTaskTests(taskFile);
      i++;
    }
  }
  
  if (!url) { console.error('Usage: smart-eval.js <url> [--task <file.md>]'); process.exit(1); }
  
  // Collect console errors and network failures
  const consoleErrors = [];
  const networkFailures = [];
  
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: CHROME,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });
  
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 900 });
  
  // Monitor console
  page.on('console', msg => {
    if (msg.type() === 'error') {
      const text = msg.text();
      // Ignore known noise: COOP headers, pre-login 401, blocked aggregator 502
      if (text.includes('Cross-Origin-Opener-Policy') ||
          text.includes('origin-keyed agent cluster') ||
          text.includes('Password field is not contained') ||
          text.includes('Failed to load resource') ||
          text.includes('net::ERR_')) return;
      consoleErrors.push(text);
    }
  });
  
  // Monitor network
  page.on('response', response => {
    const status = response.status();
    if (status >= 400) {
      networkFailures.push({ url: response.url(), status });
    }
  });
  
  // Auto-login
  const port = url.match(/:(\d+)/)?.[1];
  if (port && LOGIN_CREDS[port]) {
    const creds = LOGIN_CREDS[port];
    const parsedUrl = new URL(url);
    const loginUrl = `${parsedUrl.protocol}//${parsedUrl.host}`;
    console.log(`  🔑 Auto-login to ${loginUrl}`);
    await page.goto(loginUrl, { waitUntil: 'networkidle2', timeout: 15000 }).catch(() => {});
    await new Promise(r => setTimeout(r, 2000));
    // Try specific IDs first, then fall back to generic inputs
    const userInput = await page.$('#lu') || await page.$('input[type="text"]');
    const passInput = await page.$('#lp') || await page.$('input[type="password"]');
    if (userInput && passInput) {
      await userInput.type(creds.user);
      await passInput.type(creds.pass);
      const loginBtn = await page.$('button');
      if (loginBtn) await loginBtn.click();
    }
    await new Promise(r => setTimeout(r, 3000));
  }
  
  // Navigate to target
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 15000 }).catch(() => {});
  await new Promise(r => setTimeout(r, 3000));
  
  // Run tests
  let passed = 0;
  let failed = 0;
  const failedTests = [];
  
  for (const test of tests) {
    try {
      if (test.type === 'exists') {
        const el = await page.$(test.selector);
        if (el) { console.log(`  ✅ ${test.desc}`); passed++; }
        else { console.log(`  ❌ ${test.desc} — selector "${test.selector}" not found`); failed++; failedTests.push(test); }
      } else if (test.type === 'count') {
        const els = await page.$$(test.selector);
        const ok = (test.min == null || els.length >= test.min) && (test.max == null || els.length <= test.max);
        if (ok) { console.log(`  ✅ ${test.desc} (${els.length})`); passed++; }
        else { console.log(`  ❌ ${test.desc} — found ${els.length}, expected min:${test.min} max:${test.max}`); failed++; failedTests.push(test); }
      } else if (test.type === 'text') {
        const text = await page.$eval(test.selector, el => el.textContent).catch(() => '');
        if (test.contains && text.includes(test.contains)) { console.log(`  ✅ ${test.desc}`); passed++; }
        else { console.log(`  ❌ ${test.desc} — expected "${test.contains}", got "${text.substring(0, 50)}"`); failed++; failedTests.push(test); }
      } else if (test.type === 'click') {
        const el = await page.$(test.selector);
        if (el) {
          await page.evaluate(e => e.click(), el);
          if (test.waitFor) await page.waitForSelector(test.waitFor, { timeout: 5000 }).catch(() => {});
          await new Promise(r => setTimeout(r, 2000));
          console.log(`  ✅ ${test.desc}`); passed++;
        } else { console.log(`  ❌ ${test.desc} — button "${test.selector}" not found`); failed++; failedTests.push(test); }
      } else if (test.type === 'noErrors') {
        if (consoleErrors.length === 0) { console.log(`  ✅ ${test.desc}`); passed++; }
        else { console.log(`  ❌ ${test.desc} — ${consoleErrors.length} errors`); failed++; failedTests.push(test); }
      } else if (test.type === 'screenshot') {
        await page.screenshot({ path: test.path || '/tmp/eval-screenshot.png', fullPage: true });
        console.log(`  ✅ Screenshot saved: ${test.path || '/tmp/eval-screenshot.png'}`); passed++;
      }
    } catch (err) {
      console.log(`  ❌ ${test.desc} — Error: ${err.message}`);
      failed++;
      failedTests.push(test);
    }
  }
  
  // Results
  const total = passed + failed;
  console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'}: ${passed}/${total} browser tests passed`);
  
  // If failures, investigate
  if (failed > 0) {
    console.log('\n🔍 ========== INVESTIGATION ==========');
    
    // Console errors
    if (consoleErrors.length > 0) {
      console.log(`\n🚨 Console Errors (${consoleErrors.length}):`);
      consoleErrors.slice(0, 5).forEach(e => console.log(`   ${e.substring(0, 200)}`));
    }
    
    // Network failures
    const realFailures = networkFailures.filter(f => 
      !f.url.includes('favicon') && 
      !f.url.includes('agg/socket.io') &&  // blocked sandbox aggregator
      !(f.status === 401 && f.url.includes('/auth/me'))  // pre-login check, normal
    );
    if (realFailures.length > 0) {
      console.log(`\n🌐 Network Failures (${realFailures.length}):`);
      realFailures.slice(0, 5).forEach(f => console.log(`   ${f.status} ${f.url.replace(/https?:\/\/[^/]+/, '')}`));
    }
    
    // Deep investigation
    const diagnosis = await investigate(page, failedTests);
    console.log('\n🩺 Diagnosis:');
    diagnosis.forEach(d => console.log(`   ${d}`));
    
    // Generate actionable feedback
    console.log('\n💡 ========== SUGGESTED FIXES ==========');
    
    const currentUrl = page.url();
    if (currentUrl.includes('login') || currentUrl === url.replace(/\/[^/]*$/, '/')) {
      console.log('   → Authentication failed. Check login flow and cookie handling.');
    }
    
    if (consoleErrors.some(e => e.includes('404') || e.includes('Not Found'))) {
      console.log('   → API endpoint returning 404. Check route registration and URL paths.');
    }
    
    if (consoleErrors.some(e => e.includes('401') || e.includes('Unauthorized'))) {
      console.log('   → Authentication error on API calls. Check token/cookie passing.');
    }
    
    if (consoleErrors.some(e => e.includes('500') || e.includes('Internal'))) {
      console.log('   → Server error. Check backend logs: journalctl -u <service> --since "5 min ago"');
    }
    
    for (const test of failedTests) {
      if (test.type === 'exists' && test.selector) {
        console.log(`   → Selector "${test.selector}" not found. Check: is the element rendered? Is the ID/class name correct? Is it hidden (display:none)?`);
      }
      if (test.type === 'count' && test.min) {
        console.log(`   → Expected ${test.min}+ elements but found fewer. Check: is data loading? Is the API returning results? Is the DOM being populated?`);
      }
    }
  }
  
  await browser.close();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => { console.error('Fatal:', err.message); process.exit(1); });
