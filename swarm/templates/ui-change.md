# Template: UI Change

## Steps

### STEP 1: Understand the visual requirement
- What element to change? (button, layout, color, text, animation)
- What should it look like AFTER? (reference image, description, style guide)
- CHECK: You can describe the before and after states clearly.

### STEP 2: Find the element in code
```bash
grep -rn "CLASS_OR_ID" PROJECT_DIR/public/ PROJECT_DIR/views/
```
- Identify: HTML file, CSS file, any JS that controls this element
- CHECK: You found the exact selector/element. Write the file path and line number.

### STEP 3: Screenshot BEFORE
```bash
browser action=navigate url="URL"
browser action=screenshot
```
- Save/send this as the "before" state
- CHECK: Screenshot clearly shows the element you're about to change

### STEP 4: Query past lessons
```bash
swarm/learn.sh query "UI CSS KEYWORD"
```
- CHECK: Note any UI-specific pitfalls from past tasks.

### STEP 5: Make the CSS/HTML change
- Edit the specific file(s)
- Keep changes minimal — only touch what's needed
- CHECK: No syntax errors (`grep -c '{' FILE` should match `grep -c '}' FILE` approximately)

### STEP 6: Verify the change
```bash
systemctl restart SERVICE && sleep 2
browser action=navigate url="URL"
browser action=snapshot
```
- CHECK: Does the snapshot show the expected change? Compare with requirement.

### STEP 7: Check responsiveness
```bash
# Desktop (already checked in step 6)
# Tablet
browser action=act request={"kind":"resize","width":768,"height":1024}
browser action=screenshot
# Mobile
browser action=act request={"kind":"resize","width":375,"height":667}
browser action=screenshot
```
- CHECK: Element looks correct at all 3 breakpoints

### STEP 8: Screenshot AFTER and compare
```bash
browser action=screenshot
swarm/send.sh AGENT_ID THREAD_ID "📸 UI change — BEFORE vs AFTER"
```
- CHECK: BEFORE and AFTER look DIFFERENT. If they look the same, your change didn't work.

## Common Failures
- **CSS specificity** → Your new rule might be overridden. Use browser devtools/snapshot to verify computed styles
- **Cache** → Hard refresh or restart service to clear cached CSS
- **Wrong element** → Always verify you're editing the right selector by checking the snapshot
- **Before/After identical** → Change didn't apply. Check file path, CSS specificity, cache
- **Breaks on mobile** → Always check responsive. Many CSS changes break at small widths
