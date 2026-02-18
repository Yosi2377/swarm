# Supervisor Instructions

Every minute, check active sub-agents and report to Yossi in General.

## What to do:
1. Run `subagents list` 
2. Compare with previous state (read from /tmp/supervisor-state.json)
3. Report ONLY changes:
   - 🟢 "סוכן X התחיל task Y" — when new active agent appears
   - ✅ "סוכן X סיים task Y (Xm)" — when agent moves from active to done
   - ⚠️ "סוכן X רץ כבר X דקות על task Y" — if running > 5 min
   - 🔴 "סוכן X תקוע כבר X דקות" — if running > 10 min
4. When agent finishes: take screenshot if applicable, send to General
5. Save current state to /tmp/supervisor-state.json

## Report format (send.sh or 1):
Brief, one line per change. Don't spam if nothing changed.
