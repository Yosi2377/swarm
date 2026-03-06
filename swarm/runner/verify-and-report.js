#!/usr/bin/env node
/**
 * verify-and-report.js — Run independent verification on a completed agent task
 * Called by the orchestrator after agent reports done.
 * 
 * Usage: node verify-and-report.js <agentId> <threadId> [--url URL] [--test "cmd"] [--project /path]
 * 
 * Returns exit code:
 *   0 = PASS
 *   1 = FAIL (retryable)
 *   2 = ESCALATE (max retries)
 */

const { verifyUrl, verifyPage, verifyScreenshot, takeScreenshot, runTestCommand, checkGitClean, checkReportExists } = require('./agent-runner.js');
const fs = require('fs');
const path = require('path');

const SWARM_DIR = path.resolve(__dirname, '..');
const CHAT_ID = '-1003815143703';

function sendMessage(agentId, threadId, message) {
    const { execSync } = require('child_process');
    try {
        execSync(`${SWARM_DIR}/send.sh ${agentId} ${threadId} "${message.replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`, {
            timeout: 10000, stdio: 'pipe'
        });
    } catch (e) {}
}

function sendPhoto(threadId, photoPath, caption) {
    const { execSync } = require('child_process');
    const tokenFile = `${SWARM_DIR}/.bot-token`;
    if (!fs.existsSync(tokenFile) || !fs.existsSync(photoPath)) return;
    const token = fs.readFileSync(tokenFile, 'utf8').trim();
    try {
        execSync(`curl -s -X POST "https://api.telegram.org/bot${token}/sendPhoto" \
            -F "chat_id=${CHAT_ID}" -F "message_thread_id=${threadId}" \
            -F "photo=@${photoPath}" -F "caption=${caption.replace(/"/g, '\\"')}"`, {
            timeout: 15000, stdio: 'pipe'
        });
    } catch (e) {}
}

async function main() {
    const args = process.argv.slice(2);
    const agentId = args[0];
    const threadId = args[1];
    
    // Parse optional args
    let url = '', testCmd = '', projectDir = '', expect = '';
    for (let i = 2; i < args.length; i += 2) {
        if (args[i] === '--url') url = args[i + 1];
        if (args[i] === '--test') testCmd = args[i + 1];
        if (args[i] === '--project') projectDir = args[i + 1];
        if (args[i] === '--expect') expect = args[i + 1];
    }

    // Load from meta if not provided
    const metaFile = `/tmp/agent-tasks/${agentId}-${threadId}.json`;
    if (fs.existsSync(metaFile)) {
        const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
        if (!url) url = meta.url || '';
        if (!testCmd) testCmd = meta.test_cmd || '';
        if (!projectDir) projectDir = meta.project_dir || '';
        if (!expect) expect = meta.expect || '';
    }

    console.log(`\n🔍 VERIFICATION: ${agentId}-${threadId}`);
    console.log(`URL: ${url || 'none'} | Test: ${testCmd || 'none'} | Project: ${projectDir || 'none'}\n`);

    const issues = [];

    // 1. Report exists
    const report = checkReportExists(agentId, threadId);
    console.log(`1. Report: ${report.ok ? '✅' : '❌'}`);
    if (!report.ok) issues.push('No structured report');

    // 2. Tests
    if (testCmd && projectDir) {
        const tests = runTestCommand(testCmd, projectDir);
        console.log(`2. Tests: ${tests.ok ? '✅' : '❌'} ${tests.skipped ? 'skipped' : ''}`);
        if (!tests.ok && !tests.skipped) issues.push(`Tests failed: ${tests.error || ''}`);
    }

    // 3. URL check
    if (url) {
        const urlCheck = verifyUrl(url);
        console.log(`3. URL: ${urlCheck.ok ? '✅' : '❌'} ${urlCheck.reason || ''}`);
        if (!urlCheck.ok) issues.push(`URL: ${urlCheck.reason}`);
    }

    // 4. Page check (with login)
    if (url) {
        const page = verifyPage(url);
        console.log(`4. Page: ${page.ok ? '✅' : '❌'} ${page.title || ''} ${page.issues?.join(', ') || ''}`);
        if (!page.ok) issues.push(`Page: ${page.issues?.join(', ')}`);
    }

    // 4b. Content expectation check
    if (url && expect) {
        try {
            const { execSync } = require('child_process');
            const pageContent = execSync(`curl -s --max-time 10 "${url}"`, { timeout: 15000, stdio: 'pipe' }).toString();
            const found = pageContent.toLowerCase().includes(expect.toLowerCase());
            console.log(`4b. Expect "${expect}": ${found ? '✅' : '❌'}`);
            if (!found) issues.push(`Expected text not found: "${expect}"`);
        } catch (e) {
            console.log(`4b. Expect check failed: ${e.message}`);
            issues.push(`Expect check error: ${e.message}`);
        }
    }

    // 5. Runner's own screenshot
    if (url) {
        const screenshotPath = `/tmp/runner-verify-${agentId}-${threadId}.png`;
        const took = takeScreenshot(url, screenshotPath);
        if (took) {
            const valid = verifyScreenshot(screenshotPath);
            console.log(`5. Screenshot: ${valid.ok ? '✅' : '❌'}`);
            if (!valid.ok) issues.push(`Screenshot: ${valid.reason}`);
        }
    }

    // 6. Git
    const git = checkGitClean(projectDir);
    console.log(`6. Git: ${git.ok ? '✅' : '⚠️'} ${git.skipped ? 'skipped' : ''}`);

    // VERDICT
    console.log(`\nIssues: ${issues.length}`);
    
    // Get retry count
    let retries = 0;
    if (fs.existsSync(metaFile)) {
        const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
        retries = meta.retries || 0;
    }

    if (issues.length === 0) {
        console.log('✅ PASS');
        
        // Update meta
        if (fs.existsSync(metaFile)) {
            const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
            meta.status = 'verified_pass';
            meta.verified_at = new Date().toISOString();
            fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));
        }

        // Send proof to General
        const proofPath = `/tmp/runner-verify-${agentId}-${threadId}.png`;
        if (fs.existsSync(proofPath)) {
            sendPhoto(1, proofPath, `✅ ${agentId}-${threadId} verified!`);
        }

        // Output for orchestrator
        console.log(`RESULT=PASS`);
        process.exit(0);
    } else {
        retries++;
        
        if (fs.existsSync(metaFile)) {
            const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
            meta.retries = retries;
            meta.status = retries >= 3 ? 'escalated' : `retry_${retries}`;
            meta.last_issues = issues;
            fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));
        }

        if (retries >= 3) {
            console.log('🚨 ESCALATE');
            console.log(`RESULT=ESCALATE`);
            console.log(`ISSUES=${JSON.stringify(issues)}`);
            process.exit(2);
        } else {
            console.log(`❌ FAIL (retry ${retries}/3)`);
            // Send feedback to agent's topic
            sendMessage(agentId, threadId, `❌ Verification failed (${retries}/3):\n${issues.map(i => '• ' + i).join('\n')}\n\nFix and report done again.`);
            console.log(`RESULT=RETRY`);
            console.log(`ISSUES=${JSON.stringify(issues)}`);
            process.exit(1);
        }
    }
}

main().catch(e => { console.error(e); process.exit(1); });
