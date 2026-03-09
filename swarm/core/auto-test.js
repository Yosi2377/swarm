// auto-test.js — Automatically test code artifacts after agent completion
// This is the missing piece: don't just check "does code exist" — run it.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

/**
 * Test a JavaScript function/module by actually executing it
 * Returns { pass: bool, output: string, error: string|null }
 */
function testJsCode(code, testInput, timeoutMs = 5000) {
  if (!code || code.trim().length < 10) {
    return { pass: false, output: '', error: 'Code is empty or too short' };
  }

  // Write code to temp file and execute
  const tmpFile = `/tmp/auto-test-${Date.now()}.js`;
  const wrapper = `
    const startTime = Date.now();
    try {
      ${code}
      if (typeof module.exports === 'function') {
        const result = module.exports(${JSON.stringify(testInput)});
        const output = JSON.stringify(result);
        if (!result && result !== 0 && result !== false && result !== '') {
          console.error('AUTOTEST_FAIL: Function returned null/undefined');
          process.exit(1);
        }
        console.log('AUTOTEST_PASS:', output.substring(0, 500));
      } else {
        console.error('AUTOTEST_FAIL: module.exports is not a function');
        process.exit(1);
      }
    } catch(e) {
      console.error('AUTOTEST_FAIL:', e.message);
      process.exit(1);
    }
  `;

  try {
    fs.writeFileSync(tmpFile, wrapper);
    const output = execSync(`node "${tmpFile}"`, {
      timeout: timeoutMs,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    fs.unlinkSync(tmpFile);
    
    if (output.includes('AUTOTEST_PASS:')) {
      return { 
        pass: true, 
        output: output.replace('AUTOTEST_PASS:', '').trim(),
        error: null 
      };
    }
    return { pass: false, output, error: 'No AUTOTEST_PASS marker' };
  } catch (e) {
    try { fs.unlinkSync(tmpFile); } catch(_) {}
    const stderr = e.stderr ? e.stderr.toString() : e.message;
    return { 
      pass: false, 
      output: '', 
      error: stderr.includes('AUTOTEST_FAIL:') 
        ? stderr.split('AUTOTEST_FAIL:')[1].trim()
        : stderr.substring(0, 200)
    };
  }
}

/**
 * Test a shell command / script
 */
function testCommand(command, expectedOutput, timeoutMs = 10000) {
  try {
    const output = execSync(command, {
      timeout: timeoutMs,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    
    if (expectedOutput) {
      const pass = output.includes(expectedOutput);
      return { pass, output: output.substring(0, 500), error: pass ? null : `Expected "${expectedOutput}" not found` };
    }
    return { pass: true, output: output.substring(0, 500), error: null };
  } catch(e) {
    return { pass: false, output: '', error: (e.stderr || e.message).substring(0, 200) };
  }
}

/**
 * Test a URL endpoint
 */
function testEndpoint(url, expectedStatus = 200, expectedContent = null, timeoutMs = 10000) {
  try {
    const cmd = `curl -s -o /tmp/autotest-response.txt -w "%{http_code}" "${url}"`;
    const statusCode = execSync(cmd, { timeout: timeoutMs, encoding: 'utf8' }).trim();
    const body = fs.existsSync('/tmp/autotest-response.txt') 
      ? fs.readFileSync('/tmp/autotest-response.txt', 'utf8') : '';
    
    const statusPass = parseInt(statusCode) === expectedStatus;
    const contentPass = !expectedContent || body.includes(expectedContent);
    
    return {
      pass: statusPass && contentPass,
      output: `HTTP ${statusCode} | ${body.substring(0, 200)}`,
      error: !statusPass ? `Expected HTTP ${expectedStatus}, got ${statusCode}` 
           : !contentPass ? `Expected content "${expectedContent}" not found`
           : null
    };
  } catch(e) {
    return { pass: false, output: '', error: e.message.substring(0, 200) };
  }
}

/**
 * Run a batch of auto-tests and return summary
 */
function runTestSuite(tests) {
  const results = [];
  for (const test of tests) {
    let result;
    switch (test.type) {
      case 'js':
        result = testJsCode(test.code, test.input, test.timeout);
        break;
      case 'command':
        result = testCommand(test.command, test.expected, test.timeout);
        break;
      case 'endpoint':
        result = testEndpoint(test.url, test.status, test.content, test.timeout);
        break;
      default:
        result = { pass: false, output: '', error: `Unknown test type: ${test.type}` };
    }
    results.push({ ...test, ...result });
  }
  
  const passed = results.filter(r => r.pass).length;
  const failed = results.filter(r => !r.pass).length;
  
  return {
    total: results.length,
    passed,
    failed,
    passRate: results.length > 0 ? Math.round(passed / results.length * 100) : 0,
    results
  };
}

module.exports = { testJsCode, testCommand, testEndpoint, runTestSuite };
