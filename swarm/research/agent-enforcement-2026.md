# 🔬 מחקר: איך לגרום לסוכני AI באמת להשתמש בכלים
**תאריך:** 2026-03-02  
**סטטוס:** מחקר מבוסס קוד אמיתי מפרויקטים חיים

---

## 1. סיכום מנהלים — מה הפתרון

**הבעיה המרכזית:** אנחנו סומכים על הסוכן שיקרא לכלים מרצונו. זה לא עובד. אף פרויקט רציני לא עושה את זה ככה.

**הפתרון בשלוש מילים: אל תסמוך על הסוכן.**

כל הפרויקטים המצליחים (CrewAI, SWE-agent, LangGraph) משתמשים באותו עיקרון:
> **הקוד שעוטף את הסוכן מבצע את הפעולות החובה — לא הסוכן עצמו.**

זה אומר:
1. **Pre-hooks** — קוד שרץ *לפני* שהסוכן מתחיל (inject lessons, load memory)
2. **Post-hooks** — קוד שרץ *אחרי* שהסוכן סיים (save lessons, update memory, notify)  
3. **Guardrails** — קוד שמוודא שהפלט תקין *לפני* שהוא עובר הלאה
4. **State machine** — הסוכן לא שולט על ה-flow. ה-flow שולט על הסוכן.

**המלצה ספציפית למערכת שלנו:** לבנות **agent wrapper** ב-bash שעוטף כל `sessions_spawn` / `sessions_send` ומבצע pre/post actions אוטומטית, בלי תלות בסוכן.

---

## 2. דפוסים שעובדים (עם קוד אמיתי)

### דפוס A: Hook System (SWE-agent) ⭐⭐⭐

SWE-agent (Princeton) משתמש ב-**hook system מפורש** — הקוד האמיתי:

```python
# sweagent/agent/hooks/abstract.py — הקובץ המלא
class AbstractAgentHook:
    def on_init(self, *, agent): ...
    def on_run_start(self): ...
    def on_step_start(self): ...
    def on_actions_generated(self, *, step): ...
    def on_action_started(self, *, step): ...
    def on_action_executed(self, *, step): ...
    def on_step_done(self, *, step, info): ...
    def on_run_done(self, *, trajectory, info): ...
    def on_model_query(self, *, messages, agent): ...
```

**CombinedAgentHook** — מריץ את כל ה-hooks ברצף:
```python
class CombinedAgentHook(AbstractAgentHook):
    def on_step_done(self, *, step, info):
        for hook in self.hooks:
            hook.on_step_done(step=step, info=info)
```

**בקוד של ה-agent עצמו** (agents.py) — ה-hooks נקראים ע"י הקוד, לא ע"י ה-LLM:
```python
# שורה 959 - לפני הפעולה
self._chook.on_action_started(step=step)
# שורה 992 - אחרי הפעולה
self._chook.on_action_executed(step=step)
# שורה 1051 - אחרי שהמודל החזיר תשובה
self._chook.on_actions_generated(step=step)
```

**למה זה עובד:** ה-LLM לא יכול "לשכוח" לקרוא ל-hook. ה-hook רץ כי ה-**קוד** קורא לו, לא כי ה-LLM החליט.

**מקור:** `github.com/princeton-nlp/SWE-agent` — `/sweagent/agent/hooks/abstract.py`, `/sweagent/agent/agents.py`

---

### דפוס B: Guardrails + Callbacks (CrewAI) ⭐⭐⭐

CrewAI משתמש ב-3 מנגנוני אכיפה:

#### B1. Task Guardrails — validation אחרי כל task
```python
# crewai/task.py — שורה 193
guardrail: GuardrailType | None = Field(
    description="Function to validate task output before proceeding"
)
guardrail_max_retries: int = Field(default=3)
```

GuardRail יכול להיות **פונקציה** (validation code) או **string** (LLM בודק):
```python
# אם זה string, נוצר LLMGuardrail אוטומטית
if isinstance(self.guardrail, str):
    self._guardrail = LLMGuardrail(description=self.guardrail, llm=self.agent.llm)
```

**דוגמה לשימוש:**
```python
task = Task(
    description="Write code",
    guardrail="Verify the output includes error handling and tests",
    guardrail_max_retries=3  # ינסה שוב 3 פעמים אם נכשל
)
```

#### B2. Crew Callbacks — before/after כל crew run
```python
# crewai/crew.py — שורה 226-238
before_kickoff_callbacks: list[Callable]  # רצים לפני הכל
after_kickoff_callbacks: list[Callable[[CrewOutput], CrewOutput]]  # רצים אחרי
step_callback: Any  # אחרי כל צעד של כל agent
task_callback: Any  # אחרי כל task
```

**בקוד של _execute_tasks:**
```python
# שורה 1241 — אחרי כל task
task_output = task.execute_sync(agent=exec_data.agent, context=context, tools=exec_data.tools)
self._process_task_result(task, task_output)    # ← callback
self._store_execution_log(task, task_output)    # ← logging אוטומטי
```

#### B3. Event System — event bus לכל אירוע
```python
# crewai/events — מערכת events מלאה
CrewKickoffStartedEvent
CrewKickoffCompletedEvent
AgentExecutionCompletedEvent
MemorySaveStartedEvent / CompletedEvent / FailedEvent
MemoryQueryStartedEvent / CompletedEvent / FailedEvent
```

**מקור:** `github.com/crewAIInc/crewAI` — `/lib/crewai/src/crewai/`

---

### דפוס C: Memory כ-Infrastructure (CrewAI Unified Memory) ⭐⭐⭐

זה המפתח: **Memory לא תלוי בסוכן. Memory הוא infrastructure שרץ מתחת.**

```python
# crewai/memory/unified_memory.py — Memory class עצמאי
class Memory:
    def remember(self, content, scope=None, categories=None, importance=None):
        """Store item — LLM analyzes scope/categories/importance automatically"""
        # EncodingFlow:
        # 1. Batch embed (ONE embedder call)
        # 2. Intra-batch dedup (cosine similarity)
        # 3. Find similar in storage (concurrent searches)
        # 4. LLM analyzes: scope, categories, importance, consolidation
        # 5. Execute: insert/update/delete in storage
        
    def recall(self, query, depth="deep"):
        """Retrieve — RecallFlow with adaptive depth"""
        # 1. LLM distills query into sub-queries
        # 2. Parallel multi-scope search
        # 3. Confidence routing: shallow vs deep
        # 4. If low confidence: LLM explores deeper
        # 5. Composite scoring: semantic + recency + importance
```

**הנקודה הקריטית — Memory רץ ב-background:**
```python
# remember_many — non-blocking, רץ ב-background thread
self._save_pool = ThreadPoolExecutor(max_workers=1)

def remember_many(self, contents, ...):
    """Non-blocking — returns immediately, saves in background"""
    self._submit_save(self._background_encode_batch, contents, ...)
    return []  # returns empty, save happens async

def recall(self, query, ...):
    self.drain_writes()  # ← READ BARRIER: waits for pending saves
    # then searches...
```

**Consolidation אוטומטי** — כשזוכרים משהו דומה:
```python
consolidation_threshold: float = 0.85  # אם similarity >= 85%
# LLM decides: merge / update / delete existing + insert new
```

**מקור:** `crewai/memory/unified_memory.py`, `crewai/memory/encoding_flow.py`, `crewai/memory/recall_flow.py`

---

### דפוס D: State Machine (LangGraph) ⭐⭐

LangGraph מגדיר **graph** שבו ה-agent הוא **node**, לא ה-controller:

```python
from langgraph.graph import StateGraph, START, END

graph = StateGraph(AgentState)
graph.add_node("load_lessons", load_lessons_fn)    # ← code node, not LLM
graph.add_node("agent", call_llm)                   # ← LLM node
graph.add_node("save_results", save_results_fn)     # ← code node
graph.add_node("validate", validate_fn)             # ← code node

# FORCED edges — agent MUST go through these
graph.add_edge(START, "load_lessons")     # 1. תמיד load lessons קודם
graph.add_edge("load_lessons", "agent")   # 2. אז agent עובד
graph.add_edge("agent", "validate")       # 3. תמיד validate
graph.add_conditional_edges("validate", 
    should_retry,                          # 4. אם validation נכשל — חזור
    {"retry": "agent", "pass": "save_results"})
graph.add_edge("save_results", END)       # 5. תמיד save בסוף
```

**למה זה עובד:** ה-agent לא יכול לדלג על "load_lessons" או "save_results" כי הם **edges בגרף**, לא הוראות בפרומפט.

**מקור:** `github.com/langchain-ai/langgraph` — `/libs/langgraph/langgraph/graph/state.py`

---

### דפוס E: Anthropic's Recommendation — Simplicity ⭐⭐⭐

מתוך "Building Effective AI Agents" (anthropic.com):

> "The most successful implementations weren't using complex frameworks. They were building with simple, composable patterns."

> "Agents begin their work with either a command from, or interactive discussion with, the human user... It is therefore crucial to design **toolsets and their documentation** clearly and thoughtfully."

> "We suggest that developers start by using LLM APIs directly: many patterns can be implemented in **a few lines of code**."

**Anthropic's key patterns:**
1. **Prompt chaining** — sequence of steps with programmatic checks between them
2. **Orchestrator-workers** — central LLM delegates to workers (= our swarm)
3. **Evaluator-optimizer** — one LLM generates, another evaluates (= guardrails)
4. **Parallelization with guardrails** — one model works, another screens

---

## 3. דפוסים שלא עובדים

### ❌ לכתוב "חובה להשתמש ב-X" בפרומפט
**למה נכשל:** LLMs לא עוקבים באופן מהימן אחרי הוראות מורכבות. ככל שהפרומפט ארוך יותר, ה-compliance יורד. זה ממש כמו לבקש מעובד "תזכור תמיד לכתוב ביומן" — לפעמים יזכור, בדרך כלל לא.

### ❌ לסמוך על ה-agent שיקרא learn/reflect/notify
**למה נכשל:** הסוכן רוצה לסיים את המשימה הראשית. כלים "תומכים" (learn, notify, reflect) הם חיצוניים למשימה. ה-LLM לא רואה ערך ישיר בהם.

### ❌ לשים הרבה tools ולצפות ש-agent ישתמש בכולם
**למה נכשל:** מחקרים מראים ש-LLMs משתמשים ב-2-3 כלים גם כשיש להם 20. "Tool overload" מפחית שימוש, לא מגדיל.

### ❌ "שיפור פרומפט" חוזר
**למה נכשל:** מעבר לרמה מסוימת, שיפור פרומפט נותן diminishing returns. הבעיה היא ארכיטקטורית, לא ניסוח.

---

## 4. המלצה ספציפית למערכת שלנו (OpenClaw + subagents)

### הבעיה שלנו
- OpenClaw spawns sub-agents via `sessions_spawn`
- Sub-agent gets a task in the prompt
- Sub-agent does the task
- Sub-agent finishes — **NO mandatory learn/notify/reflect/memory**
- We rely on SYSTEM.md telling the agent to call these — it doesn't work

### הפתרון: Agent Wrapper Pattern

**לא לשנות את הסוכנים. לעטוף אותם.**

```
┌─────────────────────────────────────┐
│         AGENT WRAPPER               │
│                                     │
│  1. PRE-TASK (code, not LLM):       │
│     - learn.sh query "task context" │
│     - Load relevant lessons         │
│     - Inject into task prompt       │
│                                     │
│  2. SPAWN AGENT (as today)          │
│     - sessions_spawn with task      │
│     - task includes injected lessons│
│                                     │
│  3. POST-TASK (code, not LLM):      │
│     - Parse agent output            │
│     - learn.sh lesson auto          │
│     - pieces-save.sh auto           │
│     - notify.sh result              │
│     - Update status                 │
│                                     │
│  4. VALIDATE (optional):            │
│     - Check output format           │
│     - Check screenshots exist       │
│     - Retry if failed               │
└─────────────────────────────────────┘
```

---

## 5. תוכנית Implementation מפורטת

### Phase 1: Agent Wrapper Script (יום 1-2)

**קובץ חדש: `swarm/agent-wrapper.sh`**

```bash
#!/bin/bash
# agent-wrapper.sh — Wraps every agent spawn with mandatory pre/post hooks
# Usage: agent-wrapper.sh <agent_id> <thread_id> <task_description>

AGENT_ID="$1"
THREAD_ID="$2"
TASK="$3"

# ═══════════════════════════════════════
# PHASE 1: PRE-TASK (mandatory, code-driven)
# ═══════════════════════════════════════

# 1a. Query lessons relevant to this task
LESSONS=$(swarm/learn.sh query "$TASK" 2>/dev/null | head -20)

# 1b. Query memory for related context  
MEMORY=$(swarm/learn.sh inject "$AGENT_ID" "$TASK" 2>/dev/null | head -20)

# 1c. Build enhanced prompt with injected context
ENHANCED_TASK="📋 משימה: $TASK

📚 לקחים רלוונטיים מהעבר:
$LESSONS

🧠 הקשר נוסף:
$MEMORY

⚠️ כשתסיים, סכם מה עשית בפסקה אחת."

# ═══════════════════════════════════════
# PHASE 2: SPAWN AGENT (as today)
# ═══════════════════════════════════════

# Spawn and capture session key
# (This would be done via sessions_spawn from the orchestrator)
echo "$ENHANCED_TASK"

# ═══════════════════════════════════════
# PHASE 3: POST-TASK (mandatory, code-driven)
# Watch for agent completion, then:
# ═══════════════════════════════════════

post_task() {
    local RESULT="$1"
    
    # 3a. Auto-extract and save lesson
    swarm/learn.sh lesson "$AGENT_ID" "medium" \
        "Task: $TASK" \
        "Result: $RESULT" 2>/dev/null &
    
    # 3b. Save to Pieces LTM
    swarm/pieces-save.sh "$AGENT_ID" "$TASK" "$RESULT" 2>/dev/null &
    
    # 3c. Notify orchestrator
    swarm/send.sh "$AGENT_ID" "$THREAD_ID" \
        "✅ סיימתי: $(echo "$RESULT" | head -5)" 2>/dev/null &
    
    # 3d. Update status
    echo "{\"agent\":\"$AGENT_ID\",\"thread\":$THREAD_ID,\"status\":\"done\",\"ts\":$(date +%s)}" \
        >> swarm/logs/$(date +%Y-%m-%d).jsonl
    
    wait
}
```

### Phase 2: Orchestrator Integration (יום 3-4)

**שינוי ב-ORCHESTRATOR.md — במקום spawn ישיר, עבור דרך wrapper:**

```markdown
### Spawning Agents — ALWAYS through wrapper

Instead of direct sessions_spawn, use:

1. Run pre-task:
   ```bash
   ENHANCED=$(swarm/agent-wrapper.sh <agent_id> <thread_id> "task description")
   ```

2. Spawn with enhanced task:
   ```
   sessions_spawn with task=$ENHANCED
   ```

3. When agent reports completion, run post-task:
   ```bash
   swarm/agent-wrapper.sh post <agent_id> <thread_id> "result summary"
   ```
```

### Phase 3: Lesson Injection into Prompt (יום 5)

**שינוי ב-SYSTEM.md — הסוכן מקבל lessons כבר בפרומפט:**

```markdown
## 📚 לקחים מהעבר (injected automatically)
{{LESSONS}}

## 🧠 הקשר רלוונטי (injected automatically)  
{{MEMORY}}
```

הסוכן לא צריך *לבקש* את הלקחים. הם כבר שם. כמו שב-CrewAI ה-Memory.recall() רץ לפני כל task.

### Phase 4: Validation Guardrails (יום 6-7)

**קובץ חדש: `swarm/validate-output.sh`**

```bash
#!/bin/bash
# validate-output.sh — Check agent output meets requirements
# Returns 0 if valid, 1 if needs retry

AGENT_ID="$1"
THREAD_ID="$2"
TASK_TYPE="$3"  # code, research, design, security
OUTPUT="$4"

case "$TASK_TYPE" in
  code)
    # Must have: code blocks, no TODO left, error handling
    echo "$OUTPUT" | grep -q '```' || { echo "❌ No code blocks"; exit 1; }
    echo "$OUTPUT" | grep -qi 'todo\|fixme\|hack' && { echo "❌ Contains TODO/FIXME"; exit 1; }
    ;;
  research)
    # Must have: sources, summary, recommendations
    echo "$OUTPUT" | grep -qi 'source\|מקור\|reference' || { echo "❌ No sources"; exit 1; }
    [[ ${#OUTPUT} -lt 500 ]] && { echo "❌ Too short for research"; exit 1; }
    ;;
  security)
    # Must have: findings, severity, recommendations
    echo "$OUTPUT" | grep -qi 'severity\|חומרה\|risk\|סיכון' || { echo "❌ No severity"; exit 1; }
    ;;
  design)
    # Must have: screenshots or visual description
    echo "$OUTPUT" | grep -qi 'screenshot\|צילום\|image\|תמונה\|css\|color' || { echo "❌ No visuals"; exit 1; }
    ;;
esac

echo "✅ Output validated"
exit 0
```

### Phase 5: Background Memory Sync (שבוע 2)

**במקום לסמוך על הסוכן — daemon שמאזין ומסנכרן:**

```bash
#!/bin/bash
# memory-daemon.sh — Watches agent logs and auto-saves to memory

# Monitor log file for new entries
tail -F swarm/logs/$(date +%Y-%m-%d).jsonl | while read -r line; do
    AGENT=$(echo "$line" | jq -r '.agent // empty')
    STATUS=$(echo "$line" | jq -r '.status // empty')
    
    if [[ "$STATUS" == "done" ]]; then
        TASK=$(echo "$line" | jq -r '.task // empty')
        RESULT=$(echo "$line" | jq -r '.result // empty')
        
        # Auto-save to pieces
        swarm/pieces-realtime.sh "agent:$AGENT" "Completed: $TASK -> $RESULT" &
        
        # Auto-extract lesson
        swarm/learn.sh lesson "$AGENT" "auto" "$TASK" "$RESULT" &
    fi
done
```

---

## 6. סיכום — מה לעשות מחר

| עדיפות | פעולה | מאמץ | השפעה |
|---------|-------|------|--------|
| 🔴 | בנה `agent-wrapper.sh` עם pre/post hooks | 2 שעות | ⭐⭐⭐⭐⭐ |
| 🔴 | שנה orchestrator לעבור דרך wrapper | 1 שעה | ⭐⭐⭐⭐⭐ |
| 🟡 | הוסף lesson injection לכל task prompt | 2 שעות | ⭐⭐⭐⭐ |
| 🟡 | בנה validate-output.sh | 2 שעות | ⭐⭐⭐ |
| 🟢 | memory-daemon ב-background | 3 שעות | ⭐⭐⭐ |
| 🟢 | מערכת retry אוטומטית (max 3) | 2 שעות | ⭐⭐ |

**העיקרון המנחה:**
> **כל מה שהסוכן חייב לעשות — צריך להתבצע ע"י קוד שעוטף אותו, לא ע"י הסוכן עצמו.**
> 
> הסוכן צריך רק דבר אחד: לעשות את המשימה שלו טוב.
> כל השאר (learn, memory, notify, validate) — infrastructure.

---

## מקורות

| פרויקט | מה למדנו | קוד |
|--------|----------|-----|
| **SWE-agent** | Hook system מפורש (on_step_start, on_action_executed, on_run_done) | `sweagent/agent/hooks/abstract.py` |
| **CrewAI** | Guardrails, callbacks, event bus, unified memory | `crewai/task.py`, `crewai/crew.py`, `crewai/memory/` |
| **LangGraph** | State graph with forced edges — agent is a node, not controller | `langgraph/graph/state.py` |
| **AutoGen** | Tool separation: caller suggests, executor executes | `autogen/agentchat/conversable_agent.py` |
| **Anthropic** | "Simple composable patterns" > complex frameworks | anthropic.com/engineering/building-effective-agents |

**כל הקוד נקרא ישירות מ-GitHub repos (cloned locally).**
