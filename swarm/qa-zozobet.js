const { chromium } = require('playwright');
const fs = require('fs');
const path = '/root/.openclaw/workspace/swarm/screenshots';
fs.mkdirSync(path, { recursive: true });

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--ignore-certificate-errors'] });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();

  // Step 1: Open site
  console.log('=== STEP 1: Opening site ===');
  try {
    await page.goto('https://zozobet.duckdns.org', { timeout: 15000 });
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/01-homepage.png`, fullPage: true });
    console.log('Homepage loaded. Title:', await page.title());
    console.log('URL:', page.url());
  } catch(e) {
    console.log('ERROR loading site:', e.message);
  }

  // Step 2: Login
  console.log('\n=== STEP 2: Login ===');
  try {
    // Check if there's a login form or link
    const bodyText = await page.textContent('body');
    console.log('Body text (first 500):', bodyText.substring(0, 500));
    
    // Try to find login elements
    const loginInputs = await page.$$('input');
    console.log('Input fields found:', loginInputs.length);
    for (const inp of loginInputs) {
      const type = await inp.getAttribute('type');
      const name = await inp.getAttribute('name');
      const placeholder = await inp.getAttribute('placeholder');
      console.log(`  Input: type=${type} name=${name} placeholder=${placeholder}`);
    }

    // Try filling login
    const usernameField = await page.$('input[name="username"], input[name="user"], input[type="text"]:first-of-type, #username');
    const passwordField = await page.$('input[name="password"], input[type="password"], #password');
    
    if (usernameField && passwordField) {
      await usernameField.fill('zozo');
      await passwordField.fill('123456');
      await page.screenshot({ path: `${path}/02-login-filled.png` });
      
      // Find and click submit
      const submitBtn = await page.$('button[type="submit"], input[type="submit"], .login-btn, .btn-login, button:has-text("Login"), button:has-text("כניסה"), button:has-text("התחבר")');
      if (submitBtn) {
        await submitBtn.click();
        await page.waitForTimeout(3000);
        await page.screenshot({ path: `${path}/03-after-login.png`, fullPage: true });
        console.log('After login URL:', page.url());
        console.log('After login text (first 500):', (await page.textContent('body')).substring(0, 500));
      } else {
        console.log('No submit button found');
        // Try pressing Enter
        await passwordField.press('Enter');
        await page.waitForTimeout(3000);
        await page.screenshot({ path: `${path}/03-after-login.png`, fullPage: true });
        console.log('After Enter URL:', page.url());
      }
    } else {
      console.log('Login fields not found. Maybe already logged in or different page structure.');
      // Check for login link
      const loginLink = await page.$('a:has-text("Login"), a:has-text("כניסה"), a[href*="login"]');
      if (loginLink) {
        console.log('Found login link, clicking...');
        await loginLink.click();
        await page.waitForTimeout(2000);
        await page.screenshot({ path: `${path}/02-login-page.png` });
      }
    }
  } catch(e) {
    console.log('Login error:', e.message);
  }

  // Step 3: Games list
  console.log('\n=== STEP 3: Games list ===');
  try {
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/04-games-list.png`, fullPage: true });
    
    // Count games/events
    const rows = await page.$$('.event-row, .match-row, .game-row, tr[data-event], .event, .match');
    console.log('Game rows found:', rows.length);
    
    // Check for leagues
    const leagues = await page.$$('.league-header, .league-name, .competition, .tournament');
    console.log('League headers found:', leagues.length);
    
    // Check for times
    const times = await page.$$('.event-time, .match-time, .time, .minute');
    console.log('Time elements found:', times.length);
    
    // Get full page text for analysis
    const fullText = await page.textContent('body');
    console.log('Full page text (first 2000):', fullText.substring(0, 2000));
  } catch(e) {
    console.log('Games list error:', e.message);
  }

  // Step 4: Click on a game to open modal
  console.log('\n=== STEP 4: Game modal ===');
  try {
    // Try clicking first event/game
    const firstGame = await page.$('.event-row, .match-row, .game-row, tr[data-event], .event, .match, .odds-row');
    if (firstGame) {
      await firstGame.click();
      await page.waitForTimeout(2000);
      await page.screenshot({ path: `${path}/05-game-modal.png`, fullPage: true });
      console.log('Modal opened');
      
      // Check for tabs/markets
      const tabs = await page.$$('.market-tab, .tab, [role="tab"], .nav-tab');
      console.log('Market tabs found:', tabs.length);
      for (const tab of tabs) {
        console.log('  Tab:', await tab.textContent());
      }
    } else {
      console.log('No clickable game found. Trying links...');
      // Try any link or clickable element with odds
      const oddsBtn = await page.$('.odd, .odds, [data-odd], .bet-btn, .coefficient');
      if (oddsBtn) {
        console.log('Found odds button');
        await oddsBtn.click();
        await page.waitForTimeout(2000);
        await page.screenshot({ path: `${path}/05-odds-click.png`, fullPage: true });
      }
    }
  } catch(e) {
    console.log('Modal error:', e.message);
  }

  // Step 5: Try to place a bet
  console.log('\n=== STEP 5: Place bet ===');
  try {
    // Look for bet slip, amount input
    const amountInput = await page.$('input[name="amount"], input[name="stake"], #stake, #amount, .bet-amount input');
    if (amountInput) {
      await amountInput.fill('10');
      await page.screenshot({ path: `${path}/06-bet-amount.png` });
      
      const placeBetBtn = await page.$('button:has-text("Place"), button:has-text("הימור"), button:has-text("שלח"), .place-bet-btn, .submit-bet');
      if (placeBetBtn) {
        await placeBetBtn.click();
        await page.waitForTimeout(2000);
        await page.screenshot({ path: `${path}/07-bet-placed.png`, fullPage: true });
        console.log('Bet placed');
      }
    } else {
      console.log('No amount input found - bet slip may not be open');
    }
  } catch(e) {
    console.log('Bet error:', e.message);
  }

  // Step 6: Admin panel
  console.log('\n=== STEP 6: Admin panel ===');
  try {
    await page.goto('https://zozobet.duckdns.org/admin', { timeout: 15000 });
    await page.waitForTimeout(2000);
    await page.screenshot({ path: `${path}/08-admin.png`, fullPage: true });
    console.log('Admin URL:', page.url());
    console.log('Admin text (first 1000):', (await page.textContent('body')).substring(0, 1000));
  } catch(e) {
    console.log('Admin error:', e.message);
  }

  // Step 7: My bets
  console.log('\n=== STEP 7: My bets ===');
  try {
    await page.goto('https://zozobet.duckdns.org', { timeout: 15000 });
    await page.waitForTimeout(2000);
    const myBetsLink = await page.$('a:has-text("ההימורים שלי"), a:has-text("My Bets"), .my-bets, a[href*="bets"]');
    if (myBetsLink) {
      await myBetsLink.click();
      await page.waitForTimeout(2000);
      await page.screenshot({ path: `${path}/09-my-bets.png`, fullPage: true });
      console.log('My bets page loaded');
    } else {
      console.log('My bets link not found');
      // Try navigating directly
      await page.goto('https://zozobet.duckdns.org/bets', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(2000);
      await page.screenshot({ path: `${path}/09-my-bets.png`, fullPage: true });
    }
  } catch(e) {
    console.log('My bets error:', e.message);
  }

  await browser.close();
  console.log('\n=== DONE ===');
  console.log('Screenshots saved to:', path);
})();
