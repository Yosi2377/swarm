// Failure Taxonomy — classify failures and determine retry strategies

const FAILURE_CATEGORIES = {
  build_failure:          { shouldRetry: true,  maxRetries: 3, delayMs: 1000,  escalateAfter: 3 },
  auth_failure:           { shouldRetry: false, maxRetries: 0, delayMs: 0,     escalateAfter: 0 },
  test_failure:           { shouldRetry: true,  maxRetries: 2, delayMs: 2000,  escalateAfter: 2 },
  timeout:                { shouldRetry: true,  maxRetries: 2, delayMs: 5000,  escalateAfter: 2 },
  missing_requirement:    { shouldRetry: false, maxRetries: 0, delayMs: 0,     escalateAfter: 0 },
  partial_implementation: { shouldRetry: true,  maxRetries: 2, delayMs: 1000,  escalateAfter: 2 },
  flaky_test:             { shouldRetry: true,  maxRetries: 3, delayMs: 500,   escalateAfter: 3 },
  dependency_failure:     { shouldRetry: true,  maxRetries: 4, delayMs: 30000, escalateAfter: 4 },
  regression:             { shouldRetry: true,  maxRetries: 2, delayMs: 2000,  escalateAfter: 2 },
};

// Classification patterns — order matters (first match wins)
const CLASSIFIERS = [
  {
    category: 'auth_failure',
    test: (v, _c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /permission denied|unauthorized|403|401|auth|credentials|forbidden|access denied/i.test(text);
    }
  },
  {
    category: 'timeout',
    test: (v, _c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /timeout|timed out|took too long|deadline exceeded/i.test(text);
    }
  },
  {
    category: 'dependency_failure',
    test: (v, _c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /econnrefused|enotfound|service unavailable|503|502|connection refused|dns|network/i.test(text);
    }
  },
  {
    category: 'missing_requirement',
    test: (v, _c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /unclear|ambiguous|missing requirement|not specified|need clarification|what do you mean/i.test(text);
    }
  },
  {
    category: 'build_failure',
    test: (v, _c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /syntax error|compilation|cannot find module|unexpected token|reference error|type error|build failed|compile/i.test(text);
    }
  },
  {
    category: 'flaky_test',
    test: (v, c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /flaky|intermittent|sometimes fails|race condition|timing/i.test(text);
    }
  },
  {
    category: 'regression',
    test: (v, c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /regression|broke|breaking|previously passing|was working/i.test(text);
    }
  },
  {
    category: 'partial_implementation',
    test: (v, c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      if (/partial|incomplete|some .* missing|not all|remaining|todo|still need/i.test(text)) return true;
      // Check if some acceptance criteria passed but not all
      if (v.criteriaResults && Array.isArray(v.criteriaResults)) {
        const passed = v.criteriaResults.filter(r => r.passed).length;
        const total = v.criteriaResults.length;
        return passed > 0 && passed < total;
      }
      return false;
    }
  },
  {
    category: 'test_failure',
    test: (v, _c, out) => {
      const text = `${v.reason || ''} ${out || ''}`.toLowerCase();
      return /test fail|assertion|expect|assert|test.* fail|failing test|spec fail/i.test(text);
    }
  },
];

/**
 * Classify a failure into a category.
 */
function classifyFailure(verifyResults, taskContract, agentOutput) {
  const v = verifyResults || {};
  const c = taskContract || {};
  const out = agentOutput || '';

  for (const cls of CLASSIFIERS) {
    if (cls.test(v, c, out)) {
      return {
        category: cls.category,
        confidence: 0.8,
        details: extractDetails(cls.category, v, out),
      };
    }
  }

  // Default: treat as build_failure (most common, retryable)
  return { category: 'build_failure', confidence: 0.3, details: v.reason || 'Unclassified failure' };
}

function extractDetails(category, verifyResults, agentOutput) {
  const reason = verifyResults.reason || '';
  switch (category) {
    case 'partial_implementation': {
      const missing = (verifyResults.criteriaResults || [])
        .filter(r => !r.passed)
        .map(r => r.description || r.criterion || 'unknown');
      return missing.length ? `Missing: ${missing.join(', ')}` : reason;
    }
    case 'regression':
      return `Regression detected: ${reason}`;
    default:
      return reason || agentOutput?.slice?.(0, 500) || 'No details';
  }
}

/**
 * Get retry strategy for a failure category.
 */
function getRetryStrategy(failureCategory) {
  const strategy = FAILURE_CATEGORIES[failureCategory];
  if (!strategy) {
    return { shouldRetry: false, maxRetries: 0, delayMs: 0, contextToAdd: '', escalateAfter: 0 };
  }

  const contextMap = {
    build_failure: 'Fix the following build/compilation errors',
    test_failure: 'The following tests failed. Fix them while keeping existing functionality',
    timeout: 'Previous attempt timed out. Reduce scope or optimize approach',
    partial_implementation: 'Complete the remaining unfinished items',
    flaky_test: 'Retry — previous failure appears intermittent',
    dependency_failure: 'Previous attempt failed due to external service. Try again',
    regression: 'Fix the original task AND the regression introduced',
  };

  return {
    ...strategy,
    contextToAdd: contextMap[failureCategory] || '',
  };
}

/**
 * Build an enhanced retry prompt with failure context.
 */
function buildRetryPrompt(originalTask, failureInfo, attempt) {
  const strategy = getRetryStrategy(failureInfo.category);
  const parts = [`## Retry Attempt ${attempt}`];

  if (strategy.contextToAdd) {
    parts.push(`**Context:** ${strategy.contextToAdd}`);
  }

  parts.push(`**Original Task:** ${originalTask}`);

  if (failureInfo.details) {
    parts.push(`**Previous Failure (${failureInfo.category}):**\n${failureInfo.details}`);
  }

  if (failureInfo.category === 'partial_implementation') {
    parts.push(`**Instructions:** Finish these remaining items: ${failureInfo.details}`);
  }

  if (failureInfo.category === 'regression') {
    parts.push(`**Instructions:** Complete the original task AND also fix: ${failureInfo.details}`);
  }

  return parts.join('\n\n');
}

/**
 * Determine if we should escalate based on failure history.
 */
function shouldEscalate(failureHistory) {
  if (!failureHistory || failureHistory.length === 0) {
    return { escalate: false, reason: '' };
  }

  const latest = failureHistory[failureHistory.length - 1];
  const strategy = getRetryStrategy(latest.category);

  // Immediate escalation categories
  if (!strategy.shouldRetry) {
    return { escalate: true, reason: `${latest.category}: cannot be resolved by retry — ${latest.details}` };
  }

  // Check if max retries exceeded
  if (failureHistory.length >= strategy.escalateAfter) {
    return {
      escalate: true,
      reason: `${latest.category}: failed ${failureHistory.length} times (max ${strategy.escalateAfter}) — ${latest.details}`,
    };
  }

  return { escalate: false, reason: '' };
}

module.exports = {
  FAILURE_CATEGORIES,
  classifyFailure,
  getRetryStrategy,
  buildRetryPrompt,
  shouldEscalate,
};
