#!/usr/bin/env node
/**
 * Take screenshot with login — logs into BotVerse first, then screenshots
 * Usage: node screenshot-with-login.js <url> <output.png>
 */
const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const url = process.argv[2];
const output = process.argv[3] || '/tmp/screenshot.png';
const scrollTo = process.argv[4] || '';  // CSS selector to scroll to

(async () => {
    const browser = await puppeteer.launch({headless: true, args: ['--no-sandbox']});
    const page = await browser.newPage();
    await page.setViewport({width: 1920, height: 1080});
    
    // Login if BotVerse URL
    if (url.includes('botverse')) {
        await page.goto('https://botverse.dev/admin.html', {waitUntil: 'networkidle2', timeout: 15000});
        await page.evaluate(async () => {
            await fetch('/api/v1/admin/login', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({username: 'admin', password: '123456'})
            });
        });
        await new Promise(r => setTimeout(r, 2000));
    }
    
    await page.goto(url, {waitUntil: 'networkidle2', timeout: 15000});
    await new Promise(r => setTimeout(r, 3000));
    
    // Scroll to specific element if requested
    if (scrollTo) {
        try {
            await page.evaluate((sel) => {
                const el = document.querySelector(sel);
                if (el) el.scrollIntoView({ behavior: 'instant', block: 'center' });
            }, scrollTo);
            await new Promise(r => setTimeout(r, 1000));
        } catch (e) {
            console.error(`Scroll-to "${scrollTo}" failed: ${e.message}`);
        }
    }
    
    // Take full page screenshot so nothing is missed
    await page.screenshot({path: output, fullPage: !scrollTo});
    
    const size = fs.statSync(output).size;
    console.log(`✅ Screenshot: ${output} (${size} bytes)`);
    
    await browser.close();
})().catch(e => {
    console.error('Screenshot failed:', e.message);
    process.exit(1);
});
