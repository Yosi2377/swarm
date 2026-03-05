#!/bin/bash
# MANDATORY verification before any agent reports "done"
# Usage: bash verify-before-done.sh
set -e

cd /root/BotVerse

echo "=== VERIFICATION CHECK ==="

# 1. Server running?
curl -s -o /dev/null -w "Server: %{http_code}\n" http://localhost:4000 || echo "❌ SERVER DOWN"

# 2. DB integrity
node -e '
const m=require("mongoose");m.connect("mongodb://localhost/botverse").then(async()=>{
  const db=m.connection.db;
  const counts = {
    agents: await db.collection("agents").countDocuments(),
    skills: await db.collection("skills").countDocuments(),
    posts: await db.collection("posts").countDocuments(),
    owners: await db.collection("owners").countDocuments()
  };
  console.log("DB:", JSON.stringify(counts));
  if(counts.agents < 10) console.log("❌ TOO FEW AGENTS");
  if(counts.skills < 20) console.log("❌ TOO FEW SKILLS");
  if(counts.posts < 5) console.log("❌ TOO FEW POSTS");
  process.exit(0);
});
' 2>&1

# 3. E2E tests
RESULT=$(bash tests/e2e.sh 2>&1 | tail -3)
echo "$RESULT"
if echo "$RESULT" | grep -q "Failed: 0"; then
  echo "✅ ALL TESTS PASS"
else
  echo "❌ TESTS FAILING"
fi

echo "=== END VERIFICATION ==="
