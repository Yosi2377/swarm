# Template: Add Feature

## Steps

### STEP 1: Understand the requirement
- Read the feature description. List: what inputs, what outputs, what behavior.
- CHECK: Can you describe the feature in 2-3 sentences without jargon?

### STEP 2: Research existing code
- Find where similar features live: `grep -rn "SIMILAR_FEATURE" PROJECT_DIR/`
- Read the existing pattern (routes, controllers, views)
- CHECK: You know which files to create/modify. List them.

### STEP 3: Query past lessons
```bash
swarm/learn.sh query "add feature KEYWORD"
swarm/learn.sh inject AGENT_ID "adding feature DESCRIPTION"
```
- CHECK: Note any relevant lessons or pitfalls.

### STEP 4: Plan implementation
Write a concrete plan:
1. Which files to create (with full paths)
2. Which files to modify (with what changes)
3. What the API/UI contract looks like
- CHECK: Does the plan cover frontend AND backend if needed?

### STEP 5: Implement backend (if applicable)
- Add route/controller/model following existing patterns
- CHECK: Run `node -c FILE` to verify syntax
- CHECK: `systemctl restart SERVICE && sleep 2 && curl -s http://localhost:PORT/NEW_ENDPOINT`

### STEP 6: Implement frontend (if applicable)
- Add HTML/CSS/JS following existing patterns
- CHECK: `browser action=navigate url="URL"` → `browser action=snapshot` → verify element exists

### STEP 7: Test the full flow
- Simulate user journey: navigate → click → input → submit → verify result
- CHECK: Does the feature work end-to-end? Not just "code compiles"

### STEP 8: Edge cases
- Test with empty input, very long input, special characters
- CHECK: No crashes or ugly errors for bad input

### STEP 9: Screenshot and report
```bash
browser action=screenshot
swarm/send.sh AGENT_ID THREAD_ID "📸 Feature added: DESCRIPTION"
```

## Common Failures
- **Not following existing patterns** → Copy the style of similar features, don't invent new patterns
- **Backend works but frontend doesn't call it** → Always test the full stack
- **Missing error handling** → Always wrap new endpoints in try/catch
- **Forgot to register route** → Check that the route is included in the main router
