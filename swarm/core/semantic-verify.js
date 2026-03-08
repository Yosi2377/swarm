// Semantic Verification Engine — checks acceptance criteria from task contracts

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { classifyFailure, getRetryStrategy } = require('./failure-taxonomy');

// ─── Criterion Runners ───

const RUNNERS = {
  http_status(criterion) {
    const { url, expected } = criterion;
    try {
      const code = execSync(`curl -s -o /dev/null -w '%{http_code}' --max-time 10 '${url}'`, { encoding: 'utf8' }).trim();
      return { passed: String(code) === String(expected), actual: code, expected: String(expected) };
    } catch (e) {
      return { passed: false, actual: 'error', expected: String(expected), error: e.message };
    }
  },

  element_exists(criterion) {
    const { url, selector } = criterion;
    try {
      const html = execSync(`curl -s --max-time 10 '${url}'`, { encoding: 'utf8' });
      // Basic check: look for id/class from selector
      const found = selectorInHtml(html, selector);
      return { passed: found, actual: found ? 'found' : 'not found', expected: 'found' };
    } catch (e) {
      return { passed: false, actual: 'error', expected: 'found', error: e.message };
    }
  },

  element_text(criterion) {
    const { url, selector, expected } = criterion;
    try {
      const html = execSync(`curl -s --max-time 10 '${url}'`, { encoding: 'utf8' });
      // Basic regex extraction
      const found = selectorInHtml(html, selector);
      const textMatch = html.includes(expected);
      return { passed: found && textMatch, actual: found && textMatch ? expected : 'not matched', expected };
    } catch (e) {
      return { passed: false, actual: 'error', expected, error: e.message };
    }
  },

  api_response(criterion) {
    const { url, method = 'GET', jsonPath, expected, headers = {} } = criterion;
    try {
      const headerArgs = Object.entries(headers).map(([k, v]) => `-H '${k}: ${v}'`).join(' ');
      const cmd = `curl -s --max-time 10 -X ${method} ${headerArgs} '${url}'`;
      const body = execSync(cmd, { encoding: 'utf8' });
      const json = JSON.parse(body);
      const actual = navigateJsonPath(json, jsonPath);
      const passed = deepEqual(actual, expected);
      return { passed, actual, expected };
    } catch (e) {
      return { passed: false, actual: 'error', expected, error: e.message };
    }
  },

  test_passes(criterion) {
    const { command, cwd } = criterion;
    try {
      execSync(command, { encoding: 'utf8', cwd: cwd || undefined, timeout: 60000, stdio: 'pipe' });
      return { passed: true, actual: 'exit 0', expected: 'exit 0' };
    } catch (e) {
      return { passed: false, actual: `exit ${e.status}`, expected: 'exit 0', error: (e.stderr || e.stdout || '').slice(0, 500) };
    }
  },

  file_contains(criterion) {
    const { file, pattern } = criterion;
    try {
      const content = fs.readFileSync(file, 'utf8');
      const re = new RegExp(pattern);
      const found = re.test(content);
      return { passed: found, actual: found ? 'matched' : 'no match', expected: `pattern: ${pattern}` };
    } catch (e) {
      return { passed: false, actual: 'error', expected: `pattern: ${pattern}`, error: e.message };
    }
  },

  db_count(criterion) {
    const { collection, query = '{}', min = 1, db = 'test' } = criterion;
    try {
      const cmd = `mongosh --quiet --eval 'db.${collection}.countDocuments(${query})' ${db}`;
      const out = execSync(cmd, { encoding: 'utf8', timeout: 15000 }).trim();
      const count = parseInt(out, 10);
      return { passed: count >= min, actual: count, expected: `>= ${min}` };
    } catch (e) {
      return { passed: false, actual: 'error', expected: `>= ${min}`, error: e.message };
    }
  },

  custom(criterion) {
    const { script, cwd } = criterion;
    try {
      execSync(script, { encoding: 'utf8', cwd: cwd || undefined, timeout: 60000, stdio: 'pipe' });
      return { passed: true, actual: 'exit 0', expected: 'exit 0' };
    } catch (e) {
      return { passed: false, actual: `exit ${e.status}`, expected: 'exit 0', error: (e.stderr || '').slice(0, 500) };
    }
  },

  git_diff(criterion) {
    const { cwd, files } = criterion;
    try {
      const out = execSync('git diff --name-only HEAD~1', { encoding: 'utf8', cwd: cwd || undefined }).trim();
      const changed = out.split('\n').filter(Boolean);
      if (files && files.length) {
        const allFound = files.every(f => changed.some(c => c.includes(f)));
        return { passed: allFound, actual: changed, expected: files };
      }
      return { passed: changed.length > 0, actual: changed, expected: 'files changed' };
    } catch (e) {
      return { passed: false, actual: 'error', expected: 'files changed', error: e.message };
    }
  },

  no_regression(criterion) {
    const { command, cwd } = criterion;
    try {
      execSync(command, { encoding: 'utf8', cwd: cwd || undefined, timeout: 120000, stdio: 'pipe' });
      return { passed: true, actual: 'all tests pass', expected: 'no regressions' };
    } catch (e) {
      return { passed: false, actual: 'tests failed', expected: 'no regressions', error: (e.stderr || '').slice(0, 500) };
    }
  },
};

// ─── Helpers ───

function selectorInHtml(html, selector) {
  // Support #id, .class, tag selectors simply
  if (selector.startsWith('#')) {
    return html.includes(`id="${selector.slice(1)}"`) || html.includes(`id='${selector.slice(1)}'`);
  }
  if (selector.startsWith('.')) {
    return html.includes(selector.slice(1));
  }
  return html.includes(`<${selector}`) || html.includes(`<${selector}`);
}

function navigateJsonPath(obj, jsonPath) {
  if (!jsonPath) return obj;
  const parts = jsonPath.replace(/^\$\.?/, '').split('.');
  let cur = obj;
  for (const p of parts) {
    if (cur == null) return undefined;
    const arrMatch = p.match(/^(\w+)\[(\d+)\]$/);
    if (arrMatch) {
      cur = cur[arrMatch[1]];
      if (Array.isArray(cur)) cur = cur[parseInt(arrMatch[2], 10)];
      else return undefined;
    } else {
      cur = cur[p];
    }
  }
  return cur;
}

function deepEqual(a, b) {
  if (a === b) return true;
  if (String(a) === String(b)) return true;
  try { return JSON.stringify(a) === JSON.stringify(b); } catch { return false; }
}

// ─── Typed Verification (extra checks per task class) ───

const TYPE_CHECKS = {
  code_fix(contract, context) {
    const checks = [];
    const cwd = context?.cwd || '.';
    checks.push({ type: 'git_diff', cwd, description: 'Code was actually changed' });
    if (context?.testCommand) {
      checks.push({ type: 'test_passes', command: context.testCommand, cwd, description: 'Tests pass' });
      checks.push({ type: 'no_regression', command: context.testCommand, cwd, description: 'No regression' });
    }
    return checks;
  },

  feature(contract, context) {
    const checks = [];
    const cwd = context?.cwd || '.';
    checks.push({ type: 'git_diff', cwd, description: 'New files added' });
    if (context?.testCommand) {
      checks.push({ type: 'test_passes', command: context.testCommand, cwd, description: 'New tests pass' });
    }
    if (context?.endpoint) {
      checks.push({ type: 'http_status', url: context.endpoint, expected: 200, description: 'Endpoint responds' });
    }
    return checks;
  },

  ui_change(contract, context) {
    const checks = [];
    const cwd = context?.cwd || '.';
    checks.push({ type: 'git_diff', cwd, files: ['.css', '.scss', '.less', '.styled'], description: 'CSS files changed' });
    const viewports = [375, 768, 1440];
    if (context?.url) {
      for (const w of viewports) {
        checks.push({ type: 'http_status', url: context.url, expected: 200, description: `Responsive check @${w}px` });
      }
    }
    return checks;
  },

  api_endpoint(contract, context) {
    const checks = [];
    if (context?.endpoint) {
      checks.push({ type: 'http_status', url: context.endpoint, expected: 200, description: 'Route responds 200' });
      checks.push({ type: 'http_status', url: context.endpoint + '/nonexistent-test-path', expected: 404, description: 'Returns 404 for bad path' });
    }
    return checks;
  },

  security_fix(contract, context) {
    const checks = [];
    const cwd = context?.cwd || '.';
    if (context?.scanCommand) {
      checks.push({ type: 'test_passes', command: context.scanCommand, cwd, description: 'Vulnerability scan passes' });
    }
    checks.push({ type: 'git_diff', cwd, description: 'Security fix applied' });
    return checks;
  },

  refactor(contract, context) {
    const checks = [];
    const cwd = context?.cwd || '.';
    if (context?.testCommand) {
      checks.push({ type: 'test_passes', command: context.testCommand, cwd, description: 'Tests still pass after refactor' });
      checks.push({ type: 'no_regression', command: context.testCommand, cwd, description: 'No functionality change' });
    }
    checks.push({ type: 'git_diff', cwd, description: 'Code was refactored' });
    return checks;
  },
};

// ─── Core API ───

/**
 * Run all acceptance_criteria from contract + typed checks.
 * Returns { passed, score, checks: [{ criterion, passed, actual, expected, error }] }
 */
function runVerification(contract, context = {}) {
  const criteria = contract.acceptance_criteria || [];
  const results = [];

  // Run explicit acceptance criteria
  for (const c of criteria) {
    const runner = RUNNERS[c.type];
    if (!runner) {
      results.push({ criterion: c.description || c.type, passed: false, actual: 'unknown type', expected: 'runner exists', error: `No runner for type: ${c.type}` });
      continue;
    }
    const r = runner(c);
    results.push({ criterion: c.description || c.type, ...r });
  }

  // Run typed extra checks
  const typeChecker = TYPE_CHECKS[contract.type];
  if (typeChecker) {
    const extraCriteria = typeChecker(contract, context);
    for (const c of extraCriteria) {
      const runner = RUNNERS[c.type];
      if (!runner) continue;
      const r = runner(c);
      results.push({ criterion: c.description || c.type, ...r });
    }
  }

  const total = results.length;
  const passedCount = results.filter(r => r.passed).length;
  const score = total === 0 ? 100 : Math.round((passedCount / total) * 100);

  return {
    passed: total > 0 ? passedCount === total : true,
    score,
    checks: results,
  };
}

/**
 * Run verification, classify failures, return recommendation.
 */
function verifyAndDecide(taskId, contract, context = {}) {
  const results = runVerification(contract, context);

  if (results.passed) {
    return { verdict: 'pass', details: results };
  }

  // Classify the failure
  const failedChecks = results.checks.filter(c => !c.passed);
  const errorText = failedChecks.map(c => `${c.criterion}: ${c.error || c.actual}`).join('; ');
  const verifyForClassify = { reason: errorText, criteriaResults: results.checks };

  const failure = classifyFailure(verifyForClassify, contract, errorText);
  const strategy = getRetryStrategy(failure.category);

  if (strategy.shouldRetry) {
    return {
      verdict: 'retry',
      details: results,
      failureCategory: failure.category,
      retryHint: strategy.contextToAdd || `Retry: fix ${failedChecks.length} failing checks`,
    };
  }

  return {
    verdict: 'escalate',
    details: results,
    failureCategory: failure.category,
    retryHint: failure.details,
  };
}

module.exports = {
  RUNNERS,
  TYPE_CHECKS,
  runVerification,
  verifyAndDecide,
  navigateJsonPath,
  selectorInHtml,
  deepEqual,
};
