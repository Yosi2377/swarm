#!/usr/bin/env node
/**
 * gemini-call.js — Call Gemini API for collab agent responses
 * Usage: node gemini-call.js <prompt-file>
 * Reads prompt from file, outputs response to stdout
 */
const https = require('https');
const fs = require('fs');

const promptFile = process.argv[2];
if (!promptFile || !fs.existsSync(promptFile)) {
  process.stderr.write('Usage: node gemini-call.js <prompt-file>\n');
  process.exit(1);
}

const prompt = fs.readFileSync(promptFile, 'utf8');
const apiKey = process.env.GEMINI_API_KEY;

if (!apiKey) {
  process.stderr.write('GEMINI_API_KEY not set\n');
  process.exit(1);
}

const data = JSON.stringify({
  contents: [{ role: 'user', parts: [{ text: prompt }] }],
  generationConfig: { maxOutputTokens: 250, temperature: 0.9, thinkingConfig: { thinkingBudget: 0 } }
});

const opts = {
  hostname: 'generativelanguage.googleapis.com',
  path: `/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
};

const req = https.request(opts, res => {
  let body = '';
  res.on('data', c => body += c);
  res.on('end', () => {
    try {
      const j = JSON.parse(body);
      const text = j.candidates?.[0]?.content?.parts?.[0]?.text || '';
      process.stdout.write(text);
    } catch (e) {
      process.stderr.write('Parse error: ' + e.message + '\n');
      process.exit(1);
    }
  });
});

req.on('error', e => {
  process.stderr.write('Request error: ' + e.message + '\n');
  process.exit(1);
});

req.write(data);
req.end();
