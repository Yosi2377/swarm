#!/bin/bash
# pipeline.sh — Chain agents: A finishes → B starts → C starts
# Usage: bash pipeline.sh <pipeline-definition-file>
#
# Pipeline file format (YAML-like, one step per block):
# ---
# step: 1
# agent: koder
# label: fix-auth
# task: Fix auth bugs in /root/myproject
# eval: cd /root/myproject && npm test
# timeout: 180
# ---
# step: 2
# agent: shomer
# label: security-review
# task: Review security of /root/myproject auth changes
# eval: Check for SQL injection, XSS, missing validation
# timeout: 120
# depends: 1
# ---
#
# For now, the ORCHESTRATOR handles pipelines by:
# 1. Spawning step 1
# 2. smart-eval monitors step 1
# 3. When step 1 passes → orchestrator spawns step 2
# 4. Etc.
#
# This file documents the pattern. Implementation is in the orchestrator's
# sessions_spawn + smart-eval flow, not a standalone script,
# because the orchestrator needs to use sessions_spawn (not bash).

echo "Pipeline support is built into the orchestrator flow."
echo "Use this pattern in ORCHESTRATOR.md:"
echo ""
echo "1. sessions_spawn step 1"
echo "2. spawn-task.sh attaches smart-eval"
echo "3. smart-eval reports PASS → orchestrator gets notification"
echo "4. Orchestrator reads /tmp/agent-reports/<label>.json"
echo "5. If pass → sessions_spawn step 2"
echo "6. Repeat"
echo ""
echo "For automated chaining without orchestrator, use:"
echo "  nohup bash smart-eval.sh ... && bash trigger-next.sh ..."
