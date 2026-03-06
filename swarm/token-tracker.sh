#!/bin/bash
# token-tracker.sh — Track token usage per agent/task from OpenClaw session files
# Usage: bash token-tracker.sh [minutes]

MINUTES="${1:-60}"

echo "╔══════════════════════════════════════════════════╗"
echo "║          💰 TOKEN USAGE TRACKER                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

python3 - "$MINUTES" << 'PYEOF'
import json, glob, os, time, sys

sessions_dir = "/root/.openclaw/agents/main/sessions"
tracker_file = "/root/.openclaw/workspace/swarm/learning/token-usage.jsonl"
minutes = int(sys.argv[1]) if len(sys.argv) > 1 else 60
cutoff = time.time() * 1000 - (minutes * 60 * 1000)

os.makedirs(os.path.dirname(tracker_file), exist_ok=True)

# Read sessions.json
sessions = {}
try:
    with open(os.path.join(sessions_dir, "sessions.json")) as f:
        sessions = json.load(f)
except:
    pass

agent_stats = {}

for key, val in sessions.items():
    if 'subagent' not in key:
        continue
    updated = val.get('updatedAt', 0)
    if updated < cutoff:
        continue
    
    session_id = val.get('sessionId', '')
    label = val.get('label', key.split(':')[-1][:30])
    
    # Find session JSONL file
    jsonl_file = None
    for f in glob.glob(os.path.join(sessions_dir, f"{session_id}*.jsonl")):
        jsonl_file = f
        break
    
    if not jsonl_file or not os.path.exists(jsonl_file):
        continue
    
    input_tokens = 0
    output_tokens = 0
    cache_read = 0
    cache_write = 0
    
    try:
        with open(jsonl_file) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    msg = entry.get('message', {})
                    usage = msg.get('usage', {})
                    if usage:
                        input_tokens += usage.get('input', 0)
                        output_tokens += usage.get('output', 0)
                        cache_read += usage.get('cacheRead', 0)
                        cache_write += usage.get('cacheWrite', 0)
                except:
                    pass
    except:
        pass
    
    if input_tokens > 0 or output_tokens > 0:
        total = input_tokens + output_tokens + cache_read + cache_write
        # Cost estimate (Claude Sonnet: $3/M input, $15/M output, $0.30/M cache read, $3.75/M cache write)
        cost = (input_tokens * 3 + output_tokens * 15 + cache_read * 0.30 + cache_write * 3.75) / 1_000_000
        
        agent_name = label.split('-')[0] if '-' in label else label
        if agent_name not in agent_stats:
            agent_stats[agent_name] = {'input': 0, 'output': 0, 'cache_r': 0, 'cache_w': 0, 'cost': 0, 'tasks': 0, 'labels': []}
        agent_stats[agent_name]['input'] += input_tokens
        agent_stats[agent_name]['output'] += output_tokens
        agent_stats[agent_name]['cache_r'] += cache_read
        agent_stats[agent_name]['cache_w'] += cache_write
        agent_stats[agent_name]['cost'] += cost
        agent_stats[agent_name]['tasks'] += 1
        agent_stats[agent_name]['labels'].append(label)

if agent_stats:
    print(f"📊 Last {minutes} minutes:\n")
    print(f"  {'Agent':<15} {'Tasks':>5} {'Input':>8} {'Output':>8} {'Cache':>10} {'Cost':>8}")
    print(f"  {'─'*15} {'─'*5} {'─'*8} {'─'*8} {'─'*10} {'─'*8}")
    
    total_cost = 0
    total_tokens = 0
    for agent, s in sorted(agent_stats.items(), key=lambda x: x[1]['cost'], reverse=True):
        cache = s['cache_r'] + s['cache_w']
        tokens = s['input'] + s['output']
        total_cost += s['cost']
        total_tokens += tokens + cache
        print(f"  {agent:<15} {s['tasks']:>5} {s['input']:>8,} {s['output']:>8,} {cache:>10,} ${s['cost']:>6.3f}")
    
    print(f"  {'─'*15} {'─'*5} {'─'*8} {'─'*8} {'─'*10} {'─'*8}")
    print(f"  {'TOTAL':<15} {'':>5} {'':>8} {'':>8} {total_tokens:>10,} ${total_cost:>6.3f}")
    
    print()
    # Warnings
    for agent, s in agent_stats.items():
        if s['cost'] > 0.50:
            print(f"  ⚠️  {agent}: ${s['cost']:.3f} — high cost!")
        avg_tokens = (s['input'] + s['output']) / max(s['tasks'], 1)
        if avg_tokens > 30000:
            print(f"  ⚠️  {agent}: {avg_tokens:,.0f} avg tokens/task — review prompts")
    
    # Top expensive tasks
    print(f"\n  📋 Tasks tracked: {sum(s['tasks'] for s in agent_stats.values())}")
else:
    print("  No token data found for recent sessions.")
PYEOF
