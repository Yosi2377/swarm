#!/bin/bash
# auto-schema.sh <project-path> <output-file>
# Scans a project and generates schema documentation automatically.
# Usage: ./auto-schema.sh /root/TexasPokerGame ./skills/poker-schema-auto.md

set -euo pipefail

PROJECT="${1:?Usage: auto-schema.sh <project-path> <output-file>}"
OUTPUT="${2:?Usage: auto-schema.sh <project-path> <output-file>}"
PROJECT_NAME=$(basename "$PROJECT")

echo "# ${PROJECT_NAME} — Auto-Generated Schema" > "$OUTPUT"
echo "" >> "$OUTPUT"
echo "> Generated: $(date -Iseconds)" >> "$OUTPUT"
echo "> Source: ${PROJECT}" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# --- 1. Mongoose/MongoDB Models ---
echo "## MongoDB Models" >> "$OUTPUT"
MONGOOSE_FILES=$(grep -rl "mongoose\|Schema\|new Schema\|model(" "$PROJECT" --include="*.js" --include="*.ts" 2>/dev/null | grep -v node_modules | grep -v dist | grep -v .min. || true)
if [ -n "$MONGOOSE_FILES" ]; then
  echo "" >> "$OUTPUT"
  for f in $MONGOOSE_FILES; do
    REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    echo "### \`$REL\`" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    # Extract schema definitions (lines with field definitions)
    grep -A 50 "new Schema\|mongoose.Schema\|= {" "$f" 2>/dev/null | head -60 || true
    echo '```' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
  done
else
  echo "No Mongoose models found." >> "$OUTPUT"
  echo "" >> "$OUTPUT"
fi

# --- 1b. MySQL tables (look for .sql files or mysql2/knex) ---
echo "## SQL Schema" >> "$OUTPUT"
SQL_FILES=$(find "$PROJECT" -name "*.sql" -not -path "*/node_modules/*" 2>/dev/null || true)
if [ -n "$SQL_FILES" ]; then
  for f in $SQL_FILES; do
    REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    echo "### \`$REL\`" >> "$OUTPUT"
    echo '```sql' >> "$OUTPUT"
    grep -i "CREATE TABLE\|ALTER TABLE\|INT\|VARCHAR\|TEXT\|DECIMAL\|ENUM\|PRIMARY KEY\|INDEX" "$f" 2>/dev/null | head -80 || true
    echo '```' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
  done
else
  echo "No SQL files found." >> "$OUTPUT"
  echo "" >> "$OUTPUT"
fi

# --- 2. Express Routes ---
echo "## API Routes" >> "$OUTPUT"
ROUTE_FILES=$(grep -rl "router\.\|app\.\(get\|post\|put\|delete\|patch\)" "$PROJECT" --include="*.js" --include="*.ts" 2>/dev/null | grep -v node_modules | grep -v dist | grep -v .min. || true)
if [ -n "$ROUTE_FILES" ]; then
  echo "" >> "$OUTPUT"
  for f in $ROUTE_FILES; do
    REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    echo "### \`$REL\`" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    grep -n "router\.\(get\|post\|put\|delete\|patch\)\|app\.\(get\|post\|put\|delete\|patch\)" "$f" 2>/dev/null | head -30 || true
    echo '```' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
  done
else
  echo "No Express routes found." >> "$OUTPUT"
  echo "" >> "$OUTPUT"
fi

# --- 3. Socket.IO Events ---
echo "## Socket.IO Events" >> "$OUTPUT"
SOCKET_FILES=$(grep -rl "socket\.on\|io\.on\|\.route(" "$PROJECT" --include="*.js" --include="*.ts" 2>/dev/null | grep -v node_modules | grep -v dist || true)
if [ -n "$SOCKET_FILES" ]; then
  for f in $SOCKET_FILES; do
    REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    echo "### \`$REL\`" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    grep "socket\.on\|io\.on\|\.route(" "$f" 2>/dev/null | head -20 || true
    echo '```' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
  done
else
  echo "No Socket.IO events found." >> "$OUTPUT"
  echo "" >> "$OUTPUT"
fi

# --- 4. Environment Config ---
echo "## Configuration" >> "$OUTPUT"
ENV_FILES=$(find "$PROJECT" -maxdepth 2 -name ".env" -o -name ".env.example" -o -name ".env.production" 2>/dev/null | grep -v node_modules || true)
if [ -n "$ENV_FILES" ]; then
  for f in $ENV_FILES; do
    REL=$(realpath --relative-to="$PROJECT" "$f" 2>/dev/null || echo "$f")
    echo "### \`$REL\`" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    # Show keys but mask values (keep only key names)
    sed 's/=.*/=***/' "$f" 2>/dev/null | head -30 || true
    echo '```' >> "$OUTPUT"
  done
else
  echo "No .env files found. Check config files manually." >> "$OUTPUT"
fi
echo "" >> "$OUTPUT"

# --- 5. File Structure ---
echo "## File Structure" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
find "$PROJECT" -maxdepth 3 -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -name "*.lock" | sort | head -80
echo '```' >> "$OUTPUT"
echo "" >> "$OUTPUT"

# --- 6. Package Info ---
echo "## Dependencies" >> "$OUTPUT"
PKG="$PROJECT/package.json"
if [ -f "$PKG" ]; then
  echo '```json' >> "$OUTPUT"
  grep -A 30 '"dependencies"' "$PKG" 2>/dev/null | head -35 || true
  echo '```' >> "$OUTPUT"
else
  echo "No package.json found." >> "$OUTPUT"
fi
echo "" >> "$OUTPUT"

# --- 7. Git Recent ---
echo "## Recent Git History" >> "$OUTPUT"
if [ -d "$PROJECT/.git" ]; then
  echo '```' >> "$OUTPUT"
  git -C "$PROJECT" log --oneline -10 2>/dev/null || echo "git log failed"
  echo '```' >> "$OUTPUT"
else
  echo "Not a git repository." >> "$OUTPUT"
fi

echo ""
echo "✅ Schema generated: $OUTPUT"
