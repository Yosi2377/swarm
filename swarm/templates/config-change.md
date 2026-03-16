# Template: Config/Environment Change

## Steps

### STEP 1: Understand what to change
- Which config file or env variable?
- Current value → New value
- Why the change? What behavior should differ?
- CHECK: You know the exact file path and key name.

### STEP 2: Find the config file
```bash
find PROJECT_DIR -name "*.env" -o -name "*.config*" -o -name "config.*" | head -20
cat PROJECT_DIR/.env 2>/dev/null || echo "No .env file"
```
- CHECK: You found the file. You can see the current value.

### STEP 3: Backup current config
```bash
cp CONFIG_FILE CONFIG_FILE.bak.$(date +%s)
```
- CHECK: Backup file exists. `ls -la CONFIG_FILE.bak.*`

### STEP 4: Query past lessons
```bash
swarm/learn.sh query "config env KEYWORD"
```

### STEP 5: Make the change
- Edit the specific key/value. Do NOT rewrite the entire file.
- CHECK: `diff CONFIG_FILE CONFIG_FILE.bak.*` shows ONLY your intended change.

### STEP 6: Verify config is valid
```bash
# For JSON configs:
python3 -m json.tool CONFIG_FILE > /dev/null
# For .env:
grep -c '=' CONFIG_FILE  # should be same count as before
# For YAML:
python3 -c "import yaml; yaml.safe_load(open('CONFIG_FILE'))"
```
- CHECK: Config file parses without errors.

### STEP 7: Restart and test
```bash
systemctl restart SERVICE && sleep 2
systemctl is-active SERVICE
```
- CHECK: Service is running (active). If not, restore backup immediately:
```bash
cp CONFIG_FILE.bak.* CONFIG_FILE && systemctl restart SERVICE
```

### STEP 8: Verify the effect
- Test that the config change has the expected effect
- CHECK: Behavior matches what was requested.

### STEP 9: Report
```bash
swarm/send.sh AGENT_ID THREAD_ID "✅ Config updated: KEY changed from OLD to NEW. Service restarted and verified."
```

## Common Failures
- **Typo in key name** → Copy-paste the key from the existing file, don't type it
- **Service crashes after change** → Restore backup immediately, then investigate
- **Change has no effect** → Service might cache config. Full restart, not just reload
- **Wrong file** → Some projects have multiple .env files (dev, prod, test). Check which one is active
- **Permissions** → `chmod` if the file permissions changed during edit
