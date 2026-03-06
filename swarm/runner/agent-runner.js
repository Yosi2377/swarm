#!/usr/bin/env node
/**
 * Agent Runner v1 — Proper agent orchestration with verification loops
 * 
 * Unlike bash scripts that "hope" agents follow instructions,
 * this runner ENFORCES the workflow in code:
 * 
 * 1. Agent gets a small, specific task
 * 2. Agent works (via sessions_spawn)
 * 3. Runner INDEPENDENTLY verifies the result
 * 4. If failed → auto-retry with specific error feedback
 * 5. If passed → report with screenshot to Telegram
 * 
 * Usage: node agent-runner.js <config.json>
 * Or:    node agent-runner.js --agent koder --thread 1234 --task "fix X" --url "https://..." --test "npm test"
 */

const { execSync, exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const SWARM_DIR = path.resolve(__dirname, '..');
const CHAT_ID = '-1003815143703';
const MAX_RETRIES = 3;
const AGENT_TIMEOUT = 300; // 5 minutes per attempt

// ============================================
// VERIFICATION FUNCTIONS (run by RUNNER, not agent)
// ============================================

function takeScreenshot(url, outputPath) {
    try {
        execSync(`${SWARM_DIR}/browser-test.sh screenshot "${url}" "${outputPath}" 1920 1080`, {
            timeout: 30000, stdio: 'pipe'
        });
        return fs.existsSync(outputPath) && fs.statSync(outputPath).size > 5000;
    } catch (e) {
        console.error(`Screenshot failed: ${e.message}`);
        return false;
    }
}

function verifyScreenshot(screenshotPath) {
    // Check file exists and is not blank
    if (!fs.existsSync(screenshotPath)) return { ok: false, reason: 'no_screenshot' };
    
    const size = fs.statSync(screenshotPath).size;
    if (size < 5000) return { ok: false, reason: 'blank_screenshot' };

    // Check pixel variance (blank/white pages have low variance)
    try {
        const result = execSync(`python3 -c "
from PIL import Image
import statistics, random
img = Image.open('${screenshotPath}').convert('L')
pixels = list(img.getdata())
# Sample evenly across the entire image, not just top
sample = pixels[::max(1, len(pixels)//20000)]
variance = statistics.variance(sample) if len(sample) > 1 else 0
unique = len(set(sample))
print(f'{variance:.0f},{unique}')
"`, { timeout: 10000, stdio: 'pipe' }).toString().trim();
        
        const [variance, unique] = result.split(',').map(Number);
        if (variance < 50 && unique < 10) {
            return { ok: false, reason: 'blank_page', variance, unique };
        }
    } catch (e) {
        // PIL check failed, continue with other checks
    }

    return { ok: true };
}

function verifyUrl(url) {
    try {
        const result = execSync(`curl -s -o /dev/null -w '%{http_code}|%{redirect_url}' --max-time 10 "${url}"`, {
            timeout: 15000, stdio: 'pipe'
        }).toString().trim();
        
        const [code, redirect] = result.split('|');
        const httpCode = parseInt(code);
        
        if (httpCode >= 400) return { ok: false, reason: `http_${httpCode}` };
        if (redirect && redirect.includes('login')) return { ok: false, reason: 'redirects_to_login' };
        
        return { ok: true, httpCode };
    } catch (e) {
        return { ok: false, reason: 'url_unreachable' };
    }
}

function verifyPage(url) {
    // Use puppeteer WITH LOGIN to check pages that require auth
    const verifyScript = `
const puppeteer = require('puppeteer');
(async () => {
    const browser = await puppeteer.launch({headless: true, args:['--no-sandbox']});
    const page = await browser.newPage();
    try {
        // Step 1: Login first (BotVerse admin)
        if ('${url}'.includes('botverse')) {
            await page.goto('https://botverse.dev/admin.html', {waitUntil: 'networkidle2', timeout: 15000});
            await page.evaluate(async () => {
                await fetch('/api/v1/admin/login', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({username:'admin', password:'123456'})
                });
            });
            await new Promise(r => setTimeout(r, 2000));
        }
        
        // Step 2: Navigate to target page
        await page.goto('${url}', {waitUntil: 'networkidle2', timeout: 15000});
        const finalUrl = page.url();
        const title = await page.title();
        const bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 500) || '');
        
        const issues = [];
        if (finalUrl.includes('login') || finalUrl.includes('signin')) issues.push('redirected_to_login');
        if (title.toLowerCase().includes('error') || title.includes('404') || title.includes('500') || title.includes('502')) issues.push('error_page');
        if (bodyText.includes('Cannot GET') || bodyText.includes('Internal Server Error') || bodyText.includes('Bad Gateway')) issues.push('server_error');
        if (bodyText.length < 50) issues.push('blank_page');
        
        console.log(JSON.stringify({ok: issues.length === 0, finalUrl, title, issues, bodyLength: bodyText.length}));
    } catch(e) {
        console.log(JSON.stringify({ok: false, issues:['page_load_failed'], error: e.message}));
    }
    await browser.close();
})();
`;
    try {
        const result = execSync(`node -e "${verifyScript.replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`, 
            { timeout: 45000, stdio: 'pipe' }).toString().trim();
        return JSON.parse(result);
    } catch (e) {
        // Fallback: try with script file
        try {
            const tmpScript = '/tmp/runner-verify-page.js';
            fs.writeFileSync(tmpScript, verifyScript);
            const result = execSync(`node ${tmpScript}`, { timeout: 45000, stdio: 'pipe' }).toString().trim();
            return JSON.parse(result);
        } catch (e2) {
            return { ok: false, issues: ['puppeteer_failed'], error: e2.message?.substring(0, 200) };
        }
    }
}

function runTestCommand(testCmd, projectDir) {
    if (!testCmd) return { ok: true, skipped: true };
    
    try {
        const output = execSync(`cd "${projectDir}" && ${testCmd}`, {
            timeout: 60000, stdio: 'pipe'
        }).toString();
        
        const passed = (output.match(/✅/g) || []).length;
        const failed = (output.match(/❌/g) || []).length;
        
        return { ok: failed === 0, passed, failed, output: output.substring(0, 500) };
    } catch (e) {
        return { ok: false, error: e.message.substring(0, 300) };
    }
}

function checkGitClean(projectDir) {
    if (!projectDir || !fs.existsSync(path.join(projectDir, '.git'))) {
        return { ok: true, skipped: true };
    }
    
    try {
        const status = execSync(`cd "${projectDir}" && git status --porcelain`, {
            timeout: 5000, stdio: 'pipe'
        }).toString().trim();
        
        return { ok: status.length === 0, dirty: status.split('\n').length };
    } catch (e) {
        return { ok: true, skipped: true };
    }
}

function checkReportExists(agentId, threadId) {
    const reportPath = `${SWARM_DIR}/agent-reports/${agentId}-${threadId}.json`;
    if (!fs.existsSync(reportPath)) return { ok: false, reason: 'no_report' };
    
    try {
        const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
        if (report.status !== 'success') return { ok: false, reason: `status_${report.status}` };
        return { ok: true, report };
    } catch (e) {
        return { ok: false, reason: 'invalid_report' };
    }
}

// ============================================
// TELEGRAM FUNCTIONS
// ============================================

function sendMessage(agentId, threadId, message) {
    try {
        execSync(`${SWARM_DIR}/send.sh ${agentId} ${threadId} "${message.replace(/"/g, '\\"')}"`, {
            timeout: 10000, stdio: 'pipe'
        });
    } catch (e) {
        console.error(`Send failed: ${e.message}`);
    }
}

function sendPhoto(agentId, threadId, photoPath, caption) {
    const tokenFile = `${SWARM_DIR}/.${agentId}-token`;
    if (!fs.existsSync(tokenFile)) return;
    
    const token = fs.readFileSync(tokenFile, 'utf8').trim();
    try {
        execSync(`curl -s -X POST "https://api.telegram.org/bot${token}/sendPhoto" \
            -F "chat_id=${CHAT_ID}" \
            -F "message_thread_id=${threadId}" \
            -F "photo=@${photoPath}" \
            -F "caption=${caption.replace(/"/g, '\\"')}"`, {
            timeout: 15000, stdio: 'pipe'
        });
    } catch (e) {
        console.error(`Send photo failed: ${e.message}`);
    }
}

function createTopic(name, agentId) {
    try {
        const result = execSync(`${SWARM_DIR}/create-topic.sh "${name}" "" ${agentId}`, {
            timeout: 15000, stdio: 'pipe'
        }).toString().trim();
        const lines = result.split('\n');
        return lines[lines.length - 1];
    } catch (e) {
        console.error(`Create topic failed: ${e.message}`);
        return null;
    }
}

// ============================================
// TASK GENERATION (simplified, focused)
// ============================================

function generateTaskText(agentId, threadId, taskDesc, projectDir) {
    return `You are ${agentId}. Work in topic ${threadId}.

## Your Task
${taskDesc}

## Communication
Report progress: ${SWARM_DIR}/send.sh ${agentId} ${threadId} "message"
Need help: ${SWARM_DIR}/send.sh ${agentId} 479 "🆘 need help: ..."

## When Done — MANDATORY (all 3):
1. Git commit: cd ${projectDir || '.'} && git add -A && git commit -m "#${threadId}: done"
2. Write report:
   mkdir -p ${SWARM_DIR}/agent-reports
   cat > ${SWARM_DIR}/agent-reports/${agentId}-${threadId}.json << 'EOF'
   {"status":"success","summary":"WHAT YOU DID","files_changed":["LIST FILES"],"tests_run":true,"tests_passed":true}
   EOF
3. Screenshot proof: ${SWARM_DIR}/screenshot.sh "URL_YOU_WORKED_ON" ${threadId} ${agentId}
4. Notify: ${SWARM_DIR}/send.sh ${agentId} ${threadId} "✅ done"

Then: mkdir -p /tmp/agent-done && echo '{"status":"done"}' > /tmp/agent-done/${agentId}-${threadId}.json

## ⚠️ The runner will INDEPENDENTLY verify your work. Do not lie.`;
}

// ============================================
// MAIN RUNNER LOOP
// ============================================

async function runAgent(config) {
    const {
        agentId,
        taskDesc,
        url,           // URL to verify (optional)
        testCmd,       // test command (optional)
        projectDir,    // project directory (optional)
        threadId: existingThread,
        topicName,
    } = config;

    console.log(`\n${'='.repeat(60)}`);
    console.log(`🚀 AGENT RUNNER: ${agentId}`);
    console.log(`📋 Task: ${taskDesc.substring(0, 100)}`);
    console.log(`${'='.repeat(60)}\n`);

    // Create topic if needed
    const threadId = existingThread || createTopic(
        topicName || `${getEmoji(agentId)} ${agentId} — ${taskDesc.substring(0, 30)}`,
        agentId
    );
    
    if (!threadId) {
        console.error('❌ Failed to create topic');
        return { success: false, error: 'topic_creation_failed' };
    }

    // Save task metadata
    const metaDir = '/tmp/agent-tasks';
    fs.mkdirSync(metaDir, { recursive: true });
    fs.mkdirSync('/tmp/agent-done', { recursive: true });
    
    const metaFile = `${metaDir}/${agentId}-${threadId}.json`;
    fs.writeFileSync(metaFile, JSON.stringify({
        agent_id: agentId,
        thread_id: threadId,
        task_desc: taskDesc,
        test_cmd: testCmd || '',
        project_dir: projectDir || '',
        dispatched_at: new Date().toISOString(),
        status: 'running',
        retries: 0
    }, null, 2));

    // Send task message
    sendMessage(agentId, threadId, `📋 משימה: ${taskDesc}`);

    // RETRY LOOP
    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        console.log(`\n--- Attempt ${attempt}/${MAX_RETRIES} ---`);

        // Generate task text
        const taskText = generateTaskText(agentId, threadId, taskDesc, projectDir);

        // Spawn sub-agent (using openclaw CLI or sessions_spawn equivalent)
        const doneFile = `/tmp/agent-done/${agentId}-${threadId}.json`;
        if (fs.existsSync(doneFile)) fs.unlinkSync(doneFile);

        // Write task to a file for the spawn script
        const taskFile = `/tmp/agent-task-${agentId}-${threadId}.txt`;
        fs.writeFileSync(taskFile, taskText);

        console.log(`Spawning ${agentId}...`);
        
        try {
            // Use sessions_spawn via the gateway websocket
            execSync(`node ${__dirname}/spawn-and-wait.js "${agentId}" "${threadId}" "${taskFile}" ${AGENT_TIMEOUT}`, {
                timeout: (AGENT_TIMEOUT + 30) * 1000,
                stdio: 'inherit'
            });
        } catch (e) {
            console.log(`Agent process ended (may have completed or timed out)`);
        }

        // Wait a moment for files to be written
        await sleep(3000);

        // ═══════════════════════════════════════
        // INDEPENDENT VERIFICATION (by RUNNER)
        // ═══════════════════════════════════════
        console.log('\n🔍 INDEPENDENT VERIFICATION');
        const results = {};
        let issues = [];

        // Check 1: Report exists
        results.report = checkReportExists(agentId, threadId);
        console.log(`  Report: ${results.report.ok ? '✅' : '❌'} ${results.report.reason || ''}`);
        if (!results.report.ok) issues.push(`No structured report`);

        // Check 2: Git clean
        results.git = checkGitClean(projectDir);
        console.log(`  Git: ${results.git.ok ? '✅' : '⚠️'} ${results.git.skipped ? 'skipped' : (results.git.dirty ? `${results.git.dirty} dirty` : 'clean')}`);
        if (!results.git.ok && !results.git.skipped) issues.push(`${results.git.dirty} uncommitted files`);

        // Check 3: Tests pass
        results.tests = runTestCommand(testCmd, projectDir);
        console.log(`  Tests: ${results.tests.ok ? '✅' : '❌'} ${results.tests.skipped ? 'skipped' : `${results.tests.passed || 0}✅ ${results.tests.failed || 0}❌`}`);
        if (!results.tests.ok && !results.tests.skipped) issues.push(`Tests failed: ${results.tests.error || `${results.tests.failed} failures`}`);

        // Check 4: URL accessible (if provided)
        if (url) {
            results.url = verifyUrl(url);
            console.log(`  URL: ${results.url.ok ? '✅' : '❌'} ${results.url.reason || `HTTP ${results.url.httpCode}`}`);
            if (!results.url.ok) issues.push(`URL check failed: ${results.url.reason}`);
        }

        // Check 5: Page content (if URL provided)
        if (url && results.url?.ok) {
            results.page = verifyPage(url);
            console.log(`  Page: ${results.page.ok ? '✅' : '❌'} ${results.page.issues?.join(', ') || results.page.title}`);
            if (!results.page.ok) issues.push(`Page issues: ${results.page.issues?.join(', ')}`);
        }

        // Check 6: Take our OWN screenshot and verify
        if (url) {
            const ourScreenshot = `/tmp/runner-verify-${agentId}-${threadId}.png`;
            const screenshotTaken = takeScreenshot(url, ourScreenshot);
            
            if (screenshotTaken) {
                results.screenshot = verifyScreenshot(ourScreenshot);
                console.log(`  Screenshot: ${results.screenshot.ok ? '✅' : '❌'} ${results.screenshot.reason || 'valid'}`);
                if (!results.screenshot.ok) issues.push(`Screenshot invalid: ${results.screenshot.reason}`);
            } else {
                console.log(`  Screenshot: ⚠️ could not take screenshot`);
            }
        }

        // ═══════════════════════════════════════
        // VERDICT
        // ═══════════════════════════════════════
        console.log(`\n  Issues: ${issues.length}`);

        if (issues.length === 0) {
            console.log('✅ VERIFICATION PASSED!\n');
            
            // Update metadata
            const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
            meta.status = 'verified_pass';
            meta.verified_at = new Date().toISOString();
            meta.attempts = attempt;
            fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));

            // Send screenshot + success to General
            const proofScreenshot = `/tmp/runner-verify-${agentId}-${threadId}.png`;
            if (fs.existsSync(proofScreenshot)) {
                sendPhoto('or', 1, proofScreenshot, `✅ ${agentId}-${threadId} הושלם ואומת!\n${taskDesc.substring(0, 100)}`);
            }
            sendMessage('or', 1, `✅ ${agentId}-${threadId} הושלם ואומת (${attempt}/${MAX_RETRIES} attempts)`);

            // Save lesson
            const lesson = {
                ts: new Date().toISOString(),
                agent: agentId,
                thread: threadId,
                task: taskDesc.substring(0, 100),
                result: 'pass',
                attempts: attempt
            };
            fs.appendFileSync(`${SWARM_DIR}/learning/lessons.jsonl`, JSON.stringify(lesson) + '\n');

            return { success: true, attempts: attempt, threadId };
        }

        // FAILED — retry or escalate
        console.log(`❌ VERIFICATION FAILED (attempt ${attempt}/${MAX_RETRIES})`);
        issues.forEach(i => console.log(`  - ${i}`));

        if (attempt < MAX_RETRIES) {
            // Send specific failure feedback to agent
            const retryMsg = `❌ VERIFICATION FAILED (${attempt}/${MAX_RETRIES}):
${issues.map(i => `• ${i}`).join('\n')}

תקן ודווח שוב.`;
            sendMessage(agentId, threadId, retryMsg);
            
            // Update task for retry with specific errors
            taskDesc = `${taskDesc}\n\n⚠️ PREVIOUS ATTEMPT FAILED:\n${issues.join('\n')}\nFix these specific issues.`;
        } else {
            // Escalate
            console.log('🚨 ESCALATING — max retries reached');
            sendMessage('or', 1, `🚨 ${agentId}-${threadId} נכשל ${MAX_RETRIES} פעמים!\n${issues.join('\n')}\nדורש התערבות.`);
            
            const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
            meta.status = 'escalated';
            meta.issues = issues;
            fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));

            return { success: false, attempts: attempt, issues, threadId };
        }
    }
}

// ============================================
// HELPERS
// ============================================

function getEmoji(agentId) {
    const emojis = {
        shomer: '🔒', koder: '⚙️', tzayar: '🎨', worker: '🤖',
        researcher: '🔍', bodek: '🧪', data: '📊', debugger: '🐛',
        docker: '🐳', front: '🖥️', back: '⚡', tester: '🧪',
        refactor: '♻️', monitor: '📡', optimizer: '🚀', integrator: '🔗'
    };
    return emojis[agentId] || '🤖';
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ============================================
// CLI
// ============================================

if (require.main === module) {
    const args = process.argv.slice(2);
    
    let config;
    
    if (args[0] && args[0].endsWith('.json')) {
        config = JSON.parse(fs.readFileSync(args[0], 'utf8'));
    } else {
        // Parse CLI args
        config = {};
        for (let i = 0; i < args.length; i += 2) {
            const key = args[i].replace(/^--/, '');
            config[key] = args[i + 1];
        }
        config.agentId = config.agent || config.agentId;
        config.taskDesc = config.task || config.taskDesc;
        config.threadId = config.thread || config.threadId;
        config.testCmd = config.test || config.testCmd;
        config.projectDir = config.project || config.projectDir;
    }

    if (!config.agentId || !config.taskDesc) {
        console.error('Usage: node agent-runner.js --agent <id> --task "description" [--url URL] [--test "cmd"] [--project /path]');
        process.exit(1);
    }

    runAgent(config).then(result => {
        console.log('\n' + JSON.stringify(result, null, 2));
        process.exit(result.success ? 0 : 1);
    }).catch(e => {
        console.error(e);
        process.exit(1);
    });
}

module.exports = { runAgent, verifyUrl, verifyPage, verifyScreenshot, takeScreenshot };
