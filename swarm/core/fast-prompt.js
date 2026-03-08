// Fast Prompt — generate minimal, focused prompts for simple tasks

const COMPLEXITY = { simple: 'simple', medium: 'medium', complex: 'complex' };

const SIMPLE_KEYWORDS = [
  'change', 'update', 'fix typo', 'rename', 'replace', 'set', 'add line',
  'שנה', 'עדכן', 'תקן', 'החלף', 'הוסף שורה'
];

const COMPLEX_KEYWORDS = [
  'architecture', 'redesign', 'migrate', 'new feature', 'implement',
  'refactor entire', 'rewrite', 'build', 'create system',
  'ארכיטקטורה', 'מערכת חדשה', 'שכתוב', 'מיגרציה', 'בנה'
];

/**
 * Classify task complexity.
 */
function classifyComplexity(description, contract) {
  const lower = (description || '').toLowerCase();
  const critCount = (contract?.acceptance_criteria || []).length;

  // Complex indicators
  for (const kw of COMPLEX_KEYWORDS) {
    if (lower.includes(kw)) return COMPLEXITY.complex;
  }
  if (critCount > 5) return COMPLEXITY.complex;

  // Simple indicators
  const isSimple = SIMPLE_KEYWORDS.some(kw => lower.includes(kw));
  const shortDesc = description.length < 200;
  const fewCriteria = critCount <= 2;
  const singleFile = (lower.match(/\.\w{1,5}\b/g) || []).length <= 1;

  if (isSimple && shortDesc && fewCriteria && singleFile) return COMPLEXITY.simple;
  if (singleFile && shortDesc && fewCriteria) return COMPLEXITY.simple;

  return COMPLEXITY.medium;
}

/**
 * Generate minimal, focused prompt for simple tasks.
 * Full prompt for complex ones.
 */
function generateFastPrompt(agentId, threadId, taskDescription, contract, projectConfig) {
  const complexity = classifyComplexity(taskDescription, contract);
  const taskId = `${agentId}-${threadId}`;
  const sendCmd = `/root/.openclaw/workspace/swarm/send.sh ${agentId} ${threadId}`;
  const doneCmd = `bash /root/.openclaw/workspace/swarm/done-marker.sh "${taskId}" "${threadId}" "Task complete"`;

  if (complexity === 'simple') {
    // Lean prompt — essentials only
    const criteria = (contract?.acceptance_criteria || [])
      .slice(0, 3)
      .map((c, i) => `${i + 1}. ${c.description}`)
      .join('\n');

    const projectPath = projectConfig?.path || projectConfig?.basePath || '';
    const prompt = [
      `Task: ${taskDescription}`,
      projectPath ? `Dir: ${projectPath}` : '',
      criteria ? `\nVerify:\n${criteria}` : '',
      `\nWhen done:\n${sendCmd} "✅ Done"\n${doneCmd}`
    ].filter(Boolean).join('\n');

    return { prompt, isSimple: true, complexity };
  }

  // Medium/Complex — full prompt with contract details
  const criteriaBlock = (contract?.acceptance_criteria || [])
    .map((c, i) => `${i + 1}. [${c.type}] ${c.description}`)
    .join('\n');

  const projectPath = projectConfig?.path || projectConfig?.basePath || '';
  const projectUrl = projectConfig?.sandboxUrl || projectConfig?.url || '';

  const prompt = [
    `## Task for ${agentId} (thread ${threadId})`,
    ``,
    `### Description`,
    taskDescription,
    ``,
    projectPath ? `### Project\nPath: ${projectPath}` : '',
    projectUrl ? `URL: ${projectUrl}` : '',
    ``,
    `### Contract: ${contract?.type || 'unknown'} (${contract?.id || 'no-id'})`,
    `Priority: ${contract?.metadata?.priority || 'normal'}`,
    contract?.rollback?.strategy !== 'none' ? `Rollback: ${contract?.rollback?.strategy}` : '',
    ``,
    `### Acceptance Criteria`,
    criteriaBlock || 'None specified',
    ``,
    `### Communication`,
    `Progress: ${sendCmd} "message"`,
    ``,
    `### When done`,
    `${sendCmd} "✅ Done"`,
    doneCmd,
  ].filter(Boolean).join('\n');

  return { prompt, isSimple: false, complexity };
}

module.exports = { generateFastPrompt, classifyComplexity, COMPLEXITY };
