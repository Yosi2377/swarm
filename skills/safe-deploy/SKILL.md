---
name: safe-deploy
description: Safe deployment pipeline with immutable file protection, sandbox-first workflow, and rollback. Use when deploying code to production, managing sandbox/production sync, or setting up deployment safeguards for web applications.
---

# Safe Deploy Pipeline

Production-safe deployment with file immutability, sandbox testing, and approval gates.

## Flow

```
Sandbox → Test → Approve → Deploy → Lock
```

1. **Develop in sandbox** — never touch production directly
2. **Run evaluator** — automated browser + API tests
3. **Screenshot results** — visual proof before approval
4. **Get approval** — human must explicitly approve
5. **Deploy** — `deploy.sh` handles unlock → copy → restart → lock

## File Protection (chattr)

Production files are locked with `chattr +i` (immutable flag):

```bash
# Lock files (after deploy)
find /root/BettingPlatform -type f -name "*.js" -o -name "*.html" | xargs chattr +i

# Unlock files (before deploy) 
find /root/BettingPlatform -type f -name "*.js" -o -name "*.html" | xargs chattr -i

# Check status
lsattr /root/BettingPlatform/backend/public/index.html
```

Direct `cp` to production → "Operation not permitted" ✅

## deploy.sh

```bash
deploy.sh [component]
# Components: backend, aggregator, frontend, all
# 1. Validates sandbox tests passed
# 2. Removes immutable flags
# 3. Copies sandbox → production  
# 4. Restarts services
# 5. Re-applies immutable flags
# 6. Verifies services running
```

## Sandbox Setup

```bash
# Sync sandbox from production
rsync -a /root/BettingPlatform/ /root/sandbox/BettingPlatform/

# Sandbox service
systemctl restart sandbox-betting-backend  # port 9301

# Sandbox shares production DB
MONGO_URI=mongodb://localhost:27017/betting  # same DB!
```

## Git Protection

Pre-commit hook blocks direct commits. Only `deploy.sh` sets `DEPLOY_MODE=1` to allow:

```bash
# .git/hooks/pre-commit
[ "$DEPLOY_MODE" != "1" ] && echo "Use deploy.sh!" && exit 1
```

## Rollback

```bash
# Backups created automatically by deploy.sh
ls /root/BettingPlatform/backups/
# Restore: cp backup files → production, restart services
```
