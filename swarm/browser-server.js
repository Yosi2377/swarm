#!/usr/bin/env node
// browser-server.js — Persistent Puppeteer server with WebSocket control
// Sessions keep browser contexts alive between commands

const http = require('http');
const WebSocket = require('ws');
const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const PORT = process.env.BROWSER_SERVER_PORT || 9222;
const SCREENSHOT_DIR = '/tmp';

let browser = null;
const sessions = new Map(); // sessionId -> { context, page }

async function ensureBrowser(width = 1280, height = 720) {
  if (!browser || !browser.connected) {
    browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        `--window-size=${width},${height}`,
      ],
      defaultViewport: { width, height },
    });
    console.log(`Browser launched ${width}x${height}`);
  }
  return browser;
}

async function getSession(sessionId, width, height) {
  if (sessions.has(sessionId)) return sessions.get(sessionId);
  const b = await ensureBrowser(width, height);
  const context = await b.createBrowserContext();
  const page = await context.newPage();
  await page.setViewport({ width: width || 1280, height: height || 720 });
  sessions.set(sessionId, { context, page });
  return { context, page };
}

async function takeScreenshot(page, name) {
  const file = path.join(SCREENSHOT_DIR, `browser-${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  return file;
}

async function handleCommand(cmd) {
  const { action, session: sessionId = 'default', args = [] } = cmd;

  try {
    switch (action) {
      case 'start': {
        const w = parseInt(args[0]) || 1280;
        const h = parseInt(args[1]) || 720;
        await ensureBrowser(w, h);
        await getSession(sessionId, w, h);
        return { ok: true, msg: `Browser started ${w}x${h}, session=${sessionId}` };
      }

      case 'goto': {
        const url = args[0];
        if (!url) return { ok: false, msg: 'URL required' };
        const { page } = await getSession(sessionId);
        await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 }).catch(() =>
          page.goto(url, { waitUntil: 'load', timeout: 30000 })
        );
        const file = await takeScreenshot(page, `${sessionId}-goto`);
        return { ok: true, msg: `Navigated to ${url}`, screenshot: file };
      }

      case 'login': {
        const [url, user, pass, userSel, passSel, submitSel] = args;
        if (!url || !user || !pass) return { ok: false, msg: 'Usage: login URL user pass [userSelector passSelector submitSelector]' };
        const { page } = await getSession(sessionId);
        await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 }).catch(() =>
          page.goto(url, { waitUntil: 'load', timeout: 30000 })
        );
        // Smart selectors with fallbacks
        const uSel = userSel || 'input[type="text"], input[type="email"], input[name="username"], input[name="user"], input[name="email"], #username, #email';
        const pSel = passSel || 'input[type="password"], #password';
        const sSel = submitSel || 'button[type="submit"], input[type="submit"], button:has-text("Login"), button:has-text("Sign in"), .login-btn, .submit-btn';

        await page.waitForSelector(uSel, { timeout: 5000 });
        await page.click(uSel);
        await page.type(uSel, user, { delay: 30 });
        await page.click(pSel);
        await page.type(pSel, pass, { delay: 30 });

        // Try to find submit button
        try {
          await page.click(sSel);
        } catch {
          // Fallback: press Enter
          await page.keyboard.press('Enter');
        }
        await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 10000 }).catch(() => {});
        await new Promise(r => setTimeout(r, 1000));
        const file = await takeScreenshot(page, `${sessionId}-login`);
        return { ok: true, msg: `Logged in to ${url}`, screenshot: file };
      }

      case 'click': {
        const selector = args[0];
        if (!selector) return { ok: false, msg: 'Selector required' };
        const { page } = await getSession(sessionId);
        await page.waitForSelector(selector, { timeout: 5000 });
        await page.click(selector);
        await new Promise(r => setTimeout(r, 1000));
        const file = await takeScreenshot(page, `${sessionId}-click`);
        return { ok: true, msg: `Clicked ${selector}`, screenshot: file };
      }

      case 'type': {
        const selector = args[0];
        const text = args.slice(1).join(' ');
        if (!selector || !text) return { ok: false, msg: 'Selector and text required' };
        const { page } = await getSession(sessionId);
        await page.waitForSelector(selector, { timeout: 5000 });
        await page.click(selector, { clickCount: 3 }); // select all
        await page.type(selector, text, { delay: 30 });
        const file = await takeScreenshot(page, `${sessionId}-type`);
        return { ok: true, msg: `Typed in ${selector}`, screenshot: file };
      }

      case 'wait': {
        const seconds = parseFloat(args[0]) || 1;
        const { page } = await getSession(sessionId);
        await new Promise(r => setTimeout(r, seconds * 1000));
        const file = await takeScreenshot(page, `${sessionId}-wait`);
        return { ok: true, msg: `Waited ${seconds}s`, screenshot: file };
      }

      case 'screenshot': {
        const name = args[0] || `${sessionId}-manual`;
        const { page } = await getSession(sessionId);
        const file = await takeScreenshot(page, name);
        return { ok: true, msg: `Screenshot saved`, screenshot: file };
      }

      case 'scroll': {
        const pixels = parseInt(args[0]) || 500;
        const { page } = await getSession(sessionId);
        await page.evaluate(px => window.scrollBy(0, px), pixels);
        await new Promise(r => setTimeout(r, 500));
        const file = await takeScreenshot(page, `${sessionId}-scroll`);
        return { ok: true, msg: `Scrolled ${pixels}px`, screenshot: file };
      }

      case 'text': {
        const selector = args[0];
        if (!selector) return { ok: false, msg: 'Selector required' };
        const { page } = await getSession(sessionId);
        await page.waitForSelector(selector, { timeout: 5000 });
        const text = await page.$eval(selector, el => el.innerText);
        return { ok: true, msg: text };
      }

      case 'exists': {
        const selector = args[0];
        if (!selector) return { ok: false, msg: 'Selector required' };
        const { page } = await getSession(sessionId);
        const el = await page.$(selector);
        return { ok: true, msg: el ? 'true' : 'false' };
      }

      case 'eval': {
        const code = args.join(' ');
        if (!code) return { ok: false, msg: 'Code required' };
        const { page } = await getSession(sessionId);
        const result = await page.evaluate(code);
        return { ok: true, msg: String(result) };
      }

      case 'stop': {
        if (sessions.has(sessionId)) {
          const { context } = sessions.get(sessionId);
          await context.close();
          sessions.delete(sessionId);
        }
        if (sessions.size === 0 && browser) {
          await browser.close();
          browser = null;
        }
        return { ok: true, msg: `Session ${sessionId} closed` };
      }

      case 'stop-all': {
        for (const [id, { context }] of sessions) {
          await context.close();
        }
        sessions.clear();
        if (browser) { await browser.close(); browser = null; }
        return { ok: true, msg: 'All sessions closed' };
      }

      default:
        return { ok: false, msg: `Unknown action: ${action}` };
    }
  } catch (err) {
    return { ok: false, msg: err.message };
  }
}

// HTTP + WebSocket server
const server = http.createServer((req, res) => {
  if (req.method === 'POST') {
    let body = '';
    req.on('data', d => body += d);
    req.on('end', async () => {
      try {
        const cmd = JSON.parse(body);
        const result = await handleCommand(cmd);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (e) {
        res.writeHead(400);
        res.end(JSON.stringify({ ok: false, msg: e.message }));
      }
    });
  } else {
    res.writeHead(200);
    res.end('browser-server running');
  }
});

const wss = new WebSocket.Server({ server });
wss.on('connection', ws => {
  ws.on('message', async data => {
    try {
      const cmd = JSON.parse(data);
      const result = await handleCommand(cmd);
      ws.send(JSON.stringify(result));
    } catch (e) {
      ws.send(JSON.stringify({ ok: false, msg: e.message }));
    }
  });
});

server.listen(PORT, () => console.log(`browser-server on port ${PORT}`));

process.on('SIGTERM', async () => {
  if (browser) await browser.close();
  process.exit(0);
});
