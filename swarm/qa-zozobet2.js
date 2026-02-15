const { chromium } = require('playwright');
const fs = require('fs');
const path = '/root/.openclaw/workspace/swarm/screenshots';

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--ignore-certificate-errors'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();

  // Login
  await page.goto('https://zozobet.duckdns.org', { timeout: 15000 });
  await page.waitForTimeout(1000);
  await page.fill('input[placeholder*="שם משתמש"]', 'zozo');
  await page.fill('input[placeholder*="סיסמה"]', '123456');
  await page.click('button:has-text("כניסה"), .login-btn');
  await page.waitForTimeout(3000);

  // Step 3 detailed: Check game rows structure
  console.log('=== GAMES ANALYSIS ===');
  // The page uses RTL, check the actual DOM structure
  const html = await page.content();
  
  // Find event rows by looking at odds buttons
  const oddsButtons = await page.$$('.odd-btn, .odds-btn, [class*="odd"], [data-odd]');
  console.log('Odds buttons:', oddsButtons.length);
  
  // Check time display
  const liveIndicators = await page.$$eval('*', els => {
    return els.filter(e => e.textContent.match(/^\d+['′]/) || e.classList.contains('live') || e.classList.contains('minute'))
      .slice(0, 5).map(e => ({ text: e.textContent.substring(0, 50), cls: e.className }));
  }).catch(() => []);
  console.log('Live indicators:', JSON.stringify(liveIndicators));

  // Find HK Rangers match (it was live at 70')
  const matchText = await page.$$eval('*', els => {
    return els.filter(e => e.textContent.includes('HK Rangers') && e.textContent.length < 200)
      .slice(0, 3).map(e => ({ tag: e.tagName, text: e.textContent.substring(0, 150), class: e.className }));
  });
  console.log('HK Rangers elements:', JSON.stringify(matchText));

  // Step 4: Click on a match to open modal
  console.log('\n=== CLICK MATCH ===');
  // Try clicking the match name
  const matchNameEl = await page.$('text=HK Rangers');
  if (matchNameEl) {
    await matchNameEl.click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/10-match-modal.png`, fullPage: false });
    console.log('Clicked HK Rangers');
    
    // Check modal content
    const modal = await page.$('.modal, .event-modal, [class*="modal"]:visible, .overlay');
    if (modal) {
      console.log('Modal found');
      const modalText = await modal.textContent();
      console.log('Modal text (first 500):', modalText.substring(0, 500));
    } else {
      console.log('No modal found - checking page change');
      console.log('Current URL:', page.url());
    }
  } else {
    console.log('HK Rangers not found, trying first odds button');
    const firstOdd = await page.$('[class*="odd"]');
    if (firstOdd) {
      console.log('Clicking first odd element');
      await firstOdd.click();
      await page.waitForTimeout(2000);
      await page.screenshot({ path: `${path}/10-match-modal.png`, fullPage: false });
    }
  }

  // Check for bet slip after clicking odds
  console.log('\n=== BET SLIP ===');
  // Try clicking an odds value
  const oddValues = await page.$$eval('[class*="odd"]', els => 
    els.filter(e => /^\d+\.\d+$/.test(e.textContent.trim())).slice(0, 5).map(e => ({ text: e.textContent.trim(), class: e.className }))
  ).catch(() => []);
  console.log('Odd value elements:', JSON.stringify(oddValues));
  
  // Click first odds value
  const firstOddValue = await page.locator('text=/^\\d+\\.\\d+$/').first();
  if (firstOddValue) {
    try {
      await firstOddValue.click({ timeout: 3000 });
      await page.waitForTimeout(1000);
      await page.screenshot({ path: `${path}/11-after-odds-click.png`, fullPage: false });
      console.log('Clicked odds value');
      
      // Check bet slip
      const betSlipText = await page.$eval('[class*="slip"], [class*="betslip"], [class*="bet-form"]', e => e.textContent).catch(() => 'not found');
      console.log('Bet slip:', betSlipText.substring(0, 200));
      
      // Try to fill amount
      const amountInput = await page.$('input[type="number"], input[placeholder*="סכום"]');
      if (amountInput) {
        await amountInput.fill('10');
        await page.screenshot({ path: `${path}/12-bet-filled.png`, fullPage: false });
        console.log('Filled 10₪');
        
        // Submit
        const submitBtn = await page.$('button:has-text("שלח"), button:has-text("הימור"), button:has-text("Place")');
        if (submitBtn) {
          await submitBtn.click();
          await page.waitForTimeout(2000);
          await page.screenshot({ path: `${path}/13-bet-submitted.png`, fullPage: false });
          console.log('Bet submitted!');
        }
      }
    } catch(e) {
      console.log('Odds click failed:', e.message);
    }
  }

  // Step 6: Admin panel - try /admin.html or management page
  console.log('\n=== ADMIN ===');
  // The nav shows "ניהול" - click it
  const mgmtLink = await page.$('text=ניהול');
  if (mgmtLink) {
    await mgmtLink.click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/14-admin-panel.png`, fullPage: true });
    console.log('Admin panel URL:', page.url());
    const adminText = (await page.textContent('body')).substring(0, 1000);
    console.log('Admin text:', adminText);
  }

  // Back to main, check "ההימורים שלי"
  console.log('\n=== MY BETS ===');
  const myBetsTab = await page.$('text=ההימורים שלי');
  if (myBetsTab) {
    await myBetsTab.click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/15-my-bets-detail.png`, fullPage: true });
    
    // Check admin features (edit/cancel)
    const editBtns = await page.$$('button:has-text("ערוך"), button:has-text("בטל"), .edit-btn, .cancel-btn');
    console.log('Edit/Cancel buttons:', editBtns.length);
    
    // Check stats boxes
    const statsText = await page.$$eval('[class*="stat"], [class*="summary"]', els => els.map(e => e.textContent.trim()).join(' | ')).catch(() => '');
    console.log('Stats:', statsText);
  }

  await browser.close();
  console.log('\n=== DONE ===');
})();
