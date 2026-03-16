# Template: Code Fix

## Steps

### STEP 1: Understand the bug
- Read the bug description carefully
- Identify: which file, which function, what's the expected vs actual behavior
- CHECK: Can you state the bug in one sentence? If not, re-read.

### STEP 2: Find the relevant code
- Run: `grep -rn "KEYWORD" PROJECT_DIR/` to locate the file
- Read the file: focus on the function mentioned in the bug
- CHECK: Did you find the exact line(s) causing the bug? Write them down.

### STEP 3: Query past lessons
```bash
swarm/learn.sh query "bug fix KEYWORD"
swarm/learn.sh inject AGENT_ID "fixing bug in FILE"
```
- CHECK: Read any lessons returned. Note pitfalls to avoid.

### STEP 4: Plan the fix
- Write exactly what you will change (old code → new code)
- CHECK: Does your fix address the ROOT CAUSE, not just symptoms?

### STEP 5: Apply the fix
- Edit the file using precise edits (not full rewrites)
- CHECK: Run `diff` or review the edit to confirm only intended changes were made

### STEP 6: Restart and test
```bash
systemctl restart SERVICE_NAME && sleep 2
curl -s http://localhost:PORT/ENDPOINT | head -20
```
- CHECK: Does the endpoint return expected data? No errors in output?

### STEP 7: Check logs for errors
```bash
journalctl -u SERVICE_NAME --no-pager -n 30
```
- CHECK: No crash, no unhandled errors, no warnings related to your change

### STEP 8: Browser verification (if UI-related)
```bash
browser action=navigate url="URL"
browser action=snapshot
```
- CHECK: Does the page render correctly? Is the bug visually fixed?

### STEP 9: Screenshot and report
```bash
browser action=screenshot
swarm/send.sh AGENT_ID THREAD_ID "📸 Fix applied: DESCRIPTION"
```

## Common Failures
- **Editing wrong file** → Always verify file path with `ls` first
- **Fix breaks other things** → Check logs after restart, test related endpoints
- **Syntax error in edit** → Use `node -c FILE` or `python3 -c "import ast; ast.parse(open('FILE').read())"` to check syntax
- **Service won't restart** → Check `journalctl -u SERVICE --no-pager -n 50` for the error
