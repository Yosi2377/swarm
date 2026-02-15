/**
 * auto-login.js — Shared login helper for all browser tools
 * Usage: require('./auto-login')(page, url)
 * 
 * Automatically detects if URL needs login and handles it.
 */

const LOGIN_CREDS = {
  '9089': { user: 'zozo', pass: '123456' },
  '8089': { user: 'zozo', pass: '123456' },
  '9088': { user: 'admin', pass: 'admin123' },
  '8088': { user: 'admin', pass: 'admin123' },
  '3000': { user: 'admin', pass: 'admin123' },
};

async function autoLogin(page, url) {
  const port = url.match(/:(\d+)/)?.[1];
  if (!port || !LOGIN_CREDS[port]) return false;
  
  const creds = LOGIN_CREDS[port];
  const baseUrl = url.match(/^https?:\/\/[^/]+/)?.[0];
  
  // Go to base URL first
  await page.goto(baseUrl, { waitUntil: 'networkidle2', timeout: 15000 });
  await new Promise(r => setTimeout(r, 2000));
  
  // Check if login form is visible
  const passInput = await page.$('input[type="password"]');
  if (!passInput) return true; // Already logged in or no auth needed
  
  // Try specific IDs first, then generic
  const userInput = await page.$('#lu') || await page.$('input[type="text"]');
  const passField = await page.$('#lp') || passInput;
  
  if (userInput && passField) {
    await userInput.type(creds.user);
    await passField.type(creds.pass);
    const btn = await page.$('button');
    if (btn) await btn.click();
    await new Promise(r => setTimeout(r, 3000));
    console.log('🔑 Logged in as ' + creds.user);
    return true;
  }
  return false;
}

module.exports = autoLogin;
