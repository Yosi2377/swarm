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
  console.log('Logged in. Balance:', await page.$eval('.balance, [class*="balance"]', e => e.textContent).catch(() => 'N/A'));

  // Click on HK Rangers match
  const matchRow = await page.$('.live-row');
  if (matchRow) {
    await matchRow.click();
    await page.waitForTimeout(2000);
  }

  // Click odds value to add to slip
  const oddsEl = await page.locator('.odds').first();
  await oddsEl.click({ timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(1000);

  // Click 10₪ quick amount button
  const btn10 = await page.$('button:has-text("10₪"), div:has-text("10₪")');
  if (btn10) {
    await btn10.click();
    await page.waitForTimeout(500);
    console.log('Clicked 10₪');
  } else {
    // Fill input directly
    const amtInput = await page.$('input[placeholder*="סכום"]');
    if (amtInput) {
      await amtInput.fill('10');
      console.log('Filled 10 in input');
    }
  }
  await page.screenshot({ path: `${path}/16-bet-with-amount.png` });

  // Submit bet
  const submitBtn = await page.$('button:has-text("המר עכשיו"), button:has-text("שלח"), button:has-text("Place")');
  if (submitBtn) {
    await submitBtn.click();
    await page.waitForTimeout(3000);
    await page.screenshot({ path: `${path}/17-bet-result.png` });
    console.log('Bet submitted');
    // Check new balance
    console.log('New balance:', await page.$eval('[class*="balance"]', e => e.textContent).catch(() => 'N/A'));
  }

  // Navigate to admin (ניהול)
  console.log('\n=== ADMIN ===');
  const adminNav = await page.$('a:has-text("ניהול"), [class*="nav"] :has-text("ניהול")');
  if (adminNav) {
    await adminNav.click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/18-admin-panel.png`, fullPage: true });
    console.log('Admin URL:', page.url());
    
    // Check for user table, balance history
    const tables = await page.$$('table');
    console.log('Tables found:', tables.length);
    
    const historyBtns = await page.$$('button:has-text("📊"), [class*="history"]');
    console.log('History buttons:', historyBtns.length);
    
    // Click first history button if exists
    if (historyBtns.length > 0) {
      await historyBtns[0].click();
      await page.waitForTimeout(1000);
      await page.screenshot({ path: `${path}/19-balance-history.png` });
    }
  }

  // My bets with admin view
  console.log('\n=== MY BETS (ADMIN) ===');
  const myBetsNav = await page.$('a:has-text("ההימורים שלי"), [class*="nav"] :has-text("ההימורים שלי")');
  if (myBetsNav) {
    await myBetsNav.click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/20-my-bets-admin.png`, fullPage: true });
    
    // Check for edit/cancel buttons on bets
    const actionBtns = await page.$$('button:has-text("ערוך"), button:has-text("בטל"), button:has-text("ביטול")');
    console.log('Action buttons on bets:', actionBtns.length);
    
    // Check filter dropdown
    const filters = await page.$$('select, [class*="filter"]');
    console.log('Filters:', filters.length);
    
    // Get summary stats
    const summaryText = await page.textContent('body');
    const statsMatch = summaryText.match(/סה"כ.*?(\d+)/);
    console.log('Total bets:', statsMatch ? statsMatch[1] : 'N/A');
  }

  await browser.close();
  console.log('\n=== DONE ===');
})();
