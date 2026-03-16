#!/bin/bash
# pretrain.sh — Scan a project codebase and generate a knowledge file
# Inspired by Ruflo's pretrain hooks
# Usage: pretrain.sh <project_dir> [--force]
# Output: swarm/knowledge/<project-name>.json

set -uo pipefail

PROJECT_DIR="${1:?Usage: pretrain.sh <project_dir> [--force]}"
FORCE="${2:-}"

SWARM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KNOWLEDGE_DIR="${SWARM_DIR}/knowledge"
mkdir -p "$KNOWLEDGE_DIR"

# Derive project name from directory
PROJECT_NAME=$(basename "$(realpath "$PROJECT_DIR")")
KNOWLEDGE_FILE="${KNOWLEDGE_DIR}/${PROJECT_NAME}.json"

# Check if already exists (skip unless --force or code changed)
if [ -f "$KNOWLEDGE_FILE" ] && [ "$FORCE" != "--force" ]; then
  # Check if code changed since last pretrain
  LAST_PRETRAIN=$(jq -r '.pretrained_at // "1970-01-01"' "$KNOWLEDGE_FILE" 2>/dev/null)
  NEWEST_FILE=$(find "$PROJECT_DIR" -maxdepth 3 -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.sh" -o -name "*.json" \) -newer "$KNOWLEDGE_FILE" 2>/dev/null | head -1)
  if [ -z "$NEWEST_FILE" ]; then
    echo "$KNOWLEDGE_FILE"
    exit 0
  fi
fi

cd "$PROJECT_DIR" || exit 1

# 1. File structure — key files and entry points
ENTRY_POINTS=""
for f in index.js index.ts main.js main.ts app.js app.ts server.js server.ts src/index.js src/index.ts src/main.js src/main.ts src/app.js src/app.ts; do
  [ -f "$f" ] && ENTRY_POINTS="${ENTRY_POINTS}\"${f}\","
done
ENTRY_POINTS="[${ENTRY_POINTS%,}]"

# Key directories
KEY_DIRS=$(find . -maxdepth 2 -type d ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/dist/*' ! -path '*/.next/*' 2>/dev/null | head -30 | jq -R . | jq -s .)

# File count by extension
FILE_STATS=$(find . -maxdepth 4 -type f ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/dist/*' 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 | awk '{print "\"." $2 "\": " $1}' | paste -sd, | sed 's/^/{/;s/$/}/')
[ -z "$FILE_STATS" ] && FILE_STATS="{}"

# 2. Stack detection
STACK="[]"
STACK_ITEMS=""
[ -f "package.json" ] && STACK_ITEMS="${STACK_ITEMS}\"node\","
[ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ] && STACK_ITEMS="${STACK_ITEMS}\"python\","
[ -f "Gemfile" ] && STACK_ITEMS="${STACK_ITEMS}\"ruby\","
[ -f "go.mod" ] && STACK_ITEMS="${STACK_ITEMS}\"go\","
[ -f "Cargo.toml" ] && STACK_ITEMS="${STACK_ITEMS}\"rust\","
[ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "Dockerfile" ] && STACK_ITEMS="${STACK_ITEMS}\"docker\","

# Framework detection from package.json
if [ -f "package.json" ]; then
  grep -q '"next"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"nextjs\","
  grep -q '"express"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"express\","
  grep -q '"react"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"react\","
  grep -q '"vue"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"vue\","
  grep -q '"angular' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"angular\","
  grep -q '"mongoose\|mongodb"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"mongodb\","
  grep -q '"pg\|postgres\|sequelize\|prisma"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"postgres\","
  grep -q '"redis\|ioredis"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"redis\","
  grep -q '"typescript"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"typescript\","
  grep -q '"jest"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"jest\","
  grep -q '"mocha"' package.json 2>/dev/null && STACK_ITEMS="${STACK_ITEMS}\"mocha\","
fi
STACK="[${STACK_ITEMS%,}]"

# 3. DB detection
DB="unknown"
if [ -f "package.json" ]; then
  grep -q '"mongoose\|mongodb"' package.json && DB="mongodb"
  grep -q '"pg\|sequelize\|prisma"' package.json && DB="postgres"
  grep -q '"mysql"' package.json && DB="mysql"
  grep -q '"sqlite"' package.json && DB="sqlite"
fi

# 4. Known issues (TODO/FIXME/HACK)
ISSUES=$(grep -rn 'TODO\|FIXME\|HACK\|XXX\|WORKAROUND' --include='*.js' --include='*.ts' --include='*.py' --include='*.sh' . 2>/dev/null | grep -v node_modules | grep -v '.git' | head -20 | jq -R . | jq -s .) || ISSUES="[]"

# 5. Test commands
TEST_CMD="unknown"
BUILD_CMD="unknown"
if [ -f "package.json" ]; then
  TEST_CMD=$(jq -r '.scripts.test // "unknown"' package.json 2>/dev/null)
  BUILD_CMD=$(jq -r '.scripts.build // "unknown"' package.json 2>/dev/null)
fi
[ -f "Makefile" ] && {
  grep -q '^test:' Makefile && TEST_CMD="make test"
  grep -q '^build:' Makefile && BUILD_CMD="make build"
}

# 6. Common patterns
PATTERNS="[]"
PATTERN_ITEMS=""
grep -rl 'async.*await' --include='*.js' --include='*.ts' . 2>/dev/null | grep -v node_modules | head -1 >/dev/null && PATTERN_ITEMS="${PATTERN_ITEMS}\"async-await\","
grep -rl 'class.*extends' --include='*.js' --include='*.ts' . 2>/dev/null | grep -v node_modules | head -1 >/dev/null && PATTERN_ITEMS="${PATTERN_ITEMS}\"class-inheritance\","
grep -rl 'module.exports\|export default\|export {' --include='*.js' --include='*.ts' . 2>/dev/null | grep -v node_modules | head -1 >/dev/null && PATTERN_ITEMS="${PATTERN_ITEMS}\"module-exports\","
grep -rl 'app\.\(get\|post\|put\|delete\)' --include='*.js' --include='*.ts' . 2>/dev/null | grep -v node_modules | head -1 >/dev/null && PATTERN_ITEMS="${PATTERN_ITEMS}\"rest-routes\","
grep -rl 'useEffect\|useState\|useRef' --include='*.js' --include='*.ts' --include='*.jsx' --include='*.tsx' . 2>/dev/null | grep -v node_modules | head -1 >/dev/null && PATTERN_ITEMS="${PATTERN_ITEMS}\"react-hooks\","
PATTERNS="[${PATTERN_ITEMS%,}]"

# 7. Total file count
TOTAL_FILES=$(find . -maxdepth 4 -type f ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/dist/*' 2>/dev/null | wc -l)

# Generate JSON
cat > "$KNOWLEDGE_FILE" <<EOF
{
  "project": "$PROJECT_NAME",
  "project_dir": "$(realpath "$PROJECT_DIR")",
  "pretrained_at": "$(date -Iseconds)",
  "entry_points": $ENTRY_POINTS,
  "key_directories": $KEY_DIRS,
  "file_stats": $FILE_STATS,
  "total_files": $TOTAL_FILES,
  "stack": $STACK,
  "database": "$DB",
  "test_command": "$TEST_CMD",
  "build_command": "$BUILD_CMD",
  "patterns": $PATTERNS,
  "known_issues": $ISSUES
}
EOF

echo "$KNOWLEDGE_FILE"
