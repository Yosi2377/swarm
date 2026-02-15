const { chromium } = require('playwright');
const path = '/root/.openclaw/workspace/swarm/screenshots';

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--ignore-certificate-errors'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();

  await page.goto('https://zozobet.duckdns.org', { timeout: 15000 });
  await page.waitForTimeout(1000);
  await page.fill('input[placeholder*="שם משתמש"]', 'zozo');
  await page.fill('input[placeholder*="סיסמה"]', '123456');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(3000);

  // Click on a visible odds button in the main table
  console.log('=== PLACE BET ===');
  // The main table has odds with class "odds" - click one that's visible
  const visibleOdds = await page.$$('.odds:visible');
  console.log('Visible odds:', visibleOdds.length);
  
  // Use evaluate to click a visible odds
  await page.evaluate(() => {
    const odds = document.querySelectorAll('.odds');
    for (const o of odds) {
      if (o.offsetParent !== null && o.textContent.trim().match(/^\d+\.\d+$/)) {
        o.click();
        return o.textContent;
      }
    }
  });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${path}/21-bet-slip-open.png` });
  
  // Now click 10₪ button
  await page.evaluate(() => {
    const btns = document.querySelectorAll('button, div');
    for (const b of btns) {
      if (b.textContent.trim() === '10₪') { b.click(); return; }
    }
  });
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${path}/22-bet-10.png` });

  // Click "המר עכשיו"
  await page.evaluate(() => {
    const btns = document.querySelectorAll('button');
    for (const b of btns) {
      if (b.textContent.includes('המר עכשיו')) { b.click(); return; }
    }
  });
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${path}/23-bet-placed.png` });
  console.log('Bet placed check done');

  // Check balance
  const balText = await page.evaluate(() => {
    const el = document.querySelector('.user-balance, .balance');
    return el ? el.textContent : document.body.textContent.match(/יתרה[\s\n]*([0-9,.]+)/)?.[1] || 'N/A';
  });
  console.log('Balance after bet:', balText);

  // Navigate to ניהול
  console.log('\n=== ADMIN ===');
  await page.evaluate(() => {
    const links = document.querySelectorAll('a, div, span');
    for (const l of links) {
      if (l.textContent.trim() === '⚙️ ניהול' || l.textContent.trim() === 'ניהול') { l.click(); return; }
    }
  });
  await page.waitForTimeout(2000);
  await page.screenshot({ path: `${path}/24-admin.png`, fullPage: true });
  console.log('Admin page text (200):', (await page.textContent('body')).substring(0, 200));

  // Navigate to ההימורים שלי
  console.log('\n=== MY BETS ===');
  await page.evaluate(() => {
    const links = document.querySelectorAll('a, div, span');
    for (const l of links) {
      if (l.textContent.includes('ההימורים שלי')) { l.click(); return; }
    }
  });
  await page.waitForTimeout(2000);
  await page.screenshot({ path: `${path}/25-my-bets-admin.png`, fullPage: true });
  
  // Check for admin features
  const betsInfo = await page.evaluate(() => {
    const text = document.body.textContent;
    const totalMatch = text.match(/סה"כ\s*(\d+)/);
    const editBtns = document.querySelectorAll('[class*="edit"], [class*="cancel"], button');
    const adminBtns = Array.from(editBtns).filter(b => 
      b.textContent.includes('ערוך') || b.textContent.includes('בטל') || b.textContent.includes('ביטול')
    );
    return {
      total: totalMatch ? totalMatch[1] : 'N/A',
      adminButtons: adminBtns.length,
      hasFilter: !!document.querySelector('select, [class*="filter"]'),
      hasUserFilter: text.includes('סינון לפי משתמש')
    };
  });
  console.log('Bets info:', JSON.stringify(betsInfo));

  await browser.close();
  console.log('\n=== ALL DONE ===');
})();
