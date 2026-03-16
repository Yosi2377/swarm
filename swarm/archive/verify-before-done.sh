#!/bin/bash
# MANDATORY verification before any agent reports "done"
# Usage: bash verify-before-done.sh [project_dir]
# Generic — works with any project

PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR" 2>/dev/null || { echo "❌ Cannot cd to $PROJECT_DIR"; exit 1; }

echo "=== VERIFICATION CHECK ==="
echo "Project: $PROJECT_DIR"

# 1. If there's a running server, check it
for port in 3000 4000 5000 8000 8080 9000; do
  if curl -s -o /dev/null -w "" "http://localhost:$port" 2>/dev/null; then
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port")
    echo "Server on port $port: $CODE"
  fi
done

# 2. If there are tests, run them
if [ -f "tests/e2e.sh" ]; then
  echo "Running E2E tests..."
  RESULT=$(bash tests/e2e.sh 2>&1 | tail -5)
  echo "$RESULT"
elif [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
  echo "Running npm test..."
  npm test 2>&1 | tail -10
else
  echo "⚠️ No tests found"
fi

# 3. Git status
if [ -d ".git" ]; then
  DIRTY=$(git status --porcelain | wc -l)
  if [ "$DIRTY" -gt 0 ]; then
    echo "⚠️ $DIRTY uncommitted changes"
  else
    echo "✅ Git clean"
  fi
fi

echo "=== END VERIFICATION ==="
