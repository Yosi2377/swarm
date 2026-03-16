# Template: Investigation/Research/Audit

## Steps

### STEP 1: Define the question
- What exactly are we trying to find out?
- What would a GOOD answer look like? (format, depth, specifics)
- CHECK: You can state the research question in one sentence.

### STEP 2: Gather internal data
```bash
# Search codebase:
grep -rn "KEYWORD" PROJECT_DIR/ --include="*.js" --include="*.md" | head -30
# Check logs:
journalctl -u SERVICE --no-pager -n 100 | grep -i "KEYWORD"
# Check database:
mongosh DB_NAME --eval "db.COLLECTION.find({QUERY}).limit(5).toArray()"
```
- CHECK: Note all relevant findings. Write them down.

### STEP 3: Gather external data
```bash
web_search query="TOPIC best practices 2024"
web_fetch url="RELEVANT_URL"
```
- CHECK: Found at least 2-3 relevant sources. Note key points from each.

### STEP 4: Query past lessons
```bash
swarm/learn.sh query "KEYWORD"
```

### STEP 5: Analyze findings
- Compare sources. Note agreements and conflicts.
- Identify: what's certain, what's uncertain, what needs more investigation
- CHECK: You can list 3-5 concrete findings.

### STEP 6: Write the report
Create a structured report:
```markdown
## Investigation: TOPIC
### Question: ...
### Findings:
1. Finding 1 — evidence: ...
2. Finding 2 — evidence: ...
### Recommendation: ...
### Risks/Unknowns: ...
```
- Save to: `swarm/memory/investigation-THREAD_ID.md`

### STEP 7: Report
```bash
swarm/send.sh AGENT_ID THREAD_ID "🔍 Investigation complete: SUMMARY"
```

## Common Failures
- **Too vague** → Always include specific evidence (file paths, line numbers, URLs)
- **Only one source** → Cross-reference. One source can be wrong.
- **No actionable conclusion** → End with a clear recommendation, not "it depends"
- **Outdated info** → Check dates on sources. Prefer 2024+ results.
