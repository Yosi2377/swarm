#!/bin/bash
# safety-wrapper.sh — Pre-task backup + DB count logging before spawning an agent
# Usage: bash safety-wrapper.sh <agent_id> <topic> "task description"

set -euo pipefail

AGENT_ID="${1:?Usage: safety-wrapper.sh <agent_id> <topic> \"task\"}"
TOPIC="${2:?Missing topic}"
TASK="${3:?Missing task description}"

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${SWARM_DIR}/logs/safety"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${AGENT_ID}-${TOPIC}-${TIMESTAMP}.log"

echo "=== Safety Wrapper — $(date) ===" | tee "$LOG_FILE"
echo "Agent: ${AGENT_ID} | Topic: ${TOPIC}" | tee -a "$LOG_FILE"
echo "Task: ${TASK}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Step 1: Pre-task backup
echo "📦 Running pre-agent backup..." | tee -a "$LOG_FILE"
if bash /root/BotVerse/scripts/pre-agent-backup.sh 2>&1 | tee -a "$LOG_FILE"; then
    echo "✅ Backup completed" | tee -a "$LOG_FILE"
else
    echo "⚠️ Backup script not found or failed — proceeding with mongodump fallback" | tee -a "$LOG_FILE"
    BACKUP_DIR="/root/backups/safety-wrapper-${TIMESTAMP}"
    mkdir -p "$BACKUP_DIR"
    mongodump --db botverse --out "$BACKUP_DIR" 2>&1 | tee -a "$LOG_FILE"
    echo "✅ Fallback mongodump → ${BACKUP_DIR}" | tee -a "$LOG_FILE"
fi

# Step 2: Log pre-task DB counts
echo "" | tee -a "$LOG_FILE"
echo "📊 Pre-task DB counts:" | tee -a "$LOG_FILE"
node -e "
const m = require('mongoose');
m.connect('mongodb://localhost/botverse').then(async () => {
    const db = m.connection.db;
    const collections = ['agents', 'skills', 'posts', 'owners', 'users', 'bets', 'events'];
    for (const c of collections) {
        try {
            const count = await db.collection(c).countDocuments();
            console.log('  ' + c + ': ' + count);
        } catch(e) {
            console.log('  ' + c + ': N/A');
        }
    }
    process.exit(0);
});
" 2>&1 | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "✅ Safety wrapper complete. Generating agent task..." | tee -a "$LOG_FILE"

# Step 3: Output the spawn-agent task (pipe this to sessions_spawn)
echo "---TASK-START---"
bash "${SWARM_DIR}/spawn-agent.sh" "$AGENT_ID" "$TOPIC" "$TASK"
