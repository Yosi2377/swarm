#!/bin/bash
# sandbox.sh — Sandbox Environment Manager for Swarm Agents
# Auto-detects ports for ANY project. No manual config needed.

set -euo pipefail

SANDBOX_ROOT="/root/sandbox"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/sandbox-projects.json"
PORT_OFFSET=6000

usage() {
  cat <<EOF
Usage: sandbox.sh <command> [project_path] [options]

Commands:
  create   <path>  — Clone project to sandbox with auto port remapping
  test     <path>  — Start sandbox on sandbox ports
  apply    <path>  — Copy sandbox changes back to production
  destroy  <path>  — Remove sandbox
  status           — Show active sandboxes
  diff     <path>  — Show diff between sandbox and production
  ports    <path>  — Show detected/configured port mapping
  add-project <path> --ports 4000:10000,4001:10001 [--service name]

Auto-detection: If no port config exists, scans project files for ports
and maps them automatically (production + $PORT_OFFSET = sandbox).

Examples:
  sandbox.sh create /root/my-new-project    # auto-detects ports!
  sandbox.sh create /root/Blackjack-Game-Multiplayer  # uses saved config
  sandbox.sh add-project /root/app --ports 5000:11000 --service my-app
EOF
  exit 1
}

# ─── Config helpers ───

read_config() {
  if [ -f "$CONFIG_FILE" ]; then
    cat "$CONFIG_FILE"
  else
    echo '{"portOffset":6000,"projects":{}}'
  fi
}

get_project_config() {
  local project_path="$1"
  read_config | python3 -c "
import json,sys
d=json.load(sys.stdin)
p=d.get('projects',{}).get('$project_path')
if p: print(json.dumps(p))
else: print('')
" 2>/dev/null
}

save_project_config() {
  local project_path="$1"
  local ports_json="$2"
  local service="${3:-}"
  
  python3 -c "
import json
try:
    with open('$CONFIG_FILE') as f: d=json.load(f)
except: d={'portOffset':$PORT_OFFSET,'projects':{}}

entry = {'ports': $ports_json}
if '$service': entry['service']='$service'
d['projects']['$project_path']=entry
with open('$CONFIG_FILE','w') as f: json.dump(d,f,indent=2)
print('saved')
"
}

# ─── Auto port detection ───

detect_ports() {
  local project_path="$1"
  local detected=""
  
  # Scan common files for port patterns
  local files=$(find "$project_path" -maxdepth 3 \
    \( -name "*.js" -o -name "*.ts" -o -name "*.json" -o -name ".env" -o -name "*.env.*" -o -name "*.yml" -o -name "*.yaml" -o -name "*.conf" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null)
  
  if [ -n "$files" ]; then
    detected=$(echo "$files" | xargs grep -ohP '(?:PORT\s*[=:]\s*|listen\s*\(\s*|port\s*[=:]\s*|PORT_\w*\s*[=:]\s*)(\d{4,5})' 2>/dev/null \
      | grep -oP '\d{4,5}' | sort -un | head -10)
  fi
  
  # Also check package.json scripts for --port flags
  if [ -f "$project_path/package.json" ]; then
    local pkg_ports=$(grep -oP '(?:--port\s+|PORT=)(\d{4,5})' "$project_path/package.json" 2>/dev/null | grep -oP '\d{4,5}')
    if [ -n "$pkg_ports" ]; then
      detected=$(echo -e "${detected}\n${pkg_ports}" | sort -un | grep -v '^$')
    fi
  fi
  
  # Filter out common non-server ports (27017=mongo, 6379=redis, etc)
  detected=$(echo "$detected" | grep -vP '^(27017|6379|5432|3306|9200|2181)$' | grep -v '^$')
  
  echo "$detected"
}

auto_map_ports() {
  local project_path="$1"
  local detected=$(detect_ports "$project_path")
  
  if [ -z "$detected" ]; then
    echo "{}"
    return
  fi
  
  local json="{"
  local first=true
  while IFS= read -r port; do
    [ -z "$port" ] && continue
    local sandbox_port=$((port + PORT_OFFSET))
    # Make sure sandbox port doesn't collide
    while ss -tlnp 2>/dev/null | grep -q ":${sandbox_port} " || echo "$json" | grep -q "\"$sandbox_port\""; do
      sandbox_port=$((sandbox_port + 1))
    done
    if [ "$first" = true ]; then first=false; else json+=","; fi
    json+="\"$port\":\"$sandbox_port\""
  done <<< "$detected"
  json+="}"
  
  echo "$json"
}

get_or_detect_ports() {
  local project_path="$1"
  local config=$(get_project_config "$project_path")
  
  if [ -n "$config" ]; then
    echo "$config" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('ports',{})))"
    return
  fi
  
  # Auto-detect and save
  local ports_json=$(auto_map_ports "$project_path")
  if [ "$ports_json" != "{}" ]; then
    save_project_config "$project_path" "$ports_json" "" >/dev/null 2>&1
    echo "  🔍 Auto-detected ports and saved to config" >&2
  fi
  echo "$ports_json"
}

get_service_name() {
  local project_path="$1"
  local config=$(get_project_config "$project_path")
  if [ -n "$config" ]; then
    echo "$config" | python3 -c "import json,sys; print(json.load(sys.stdin).get('service',''))" 2>/dev/null
  fi
}

get_sandbox_path() {
  local project_path="$1"
  local project_name=$(basename "$project_path")
  echo "${SANDBOX_ROOT}/${project_name}"
}

# ─── Port remapping in files ───

remap_ports_in_files() {
  local sandbox_path="$1"
  local ports_json="$2"
  local reverse="${3:-false}"
  
  [ "$ports_json" = "{}" ] && return 0
  
  python3 -c "
import json, os, re, sys

ports = json.loads('$ports_json')
reverse = '$reverse' == 'true'
if reverse:
    ports = {v:k for k,v in ports.items()}

sandbox = '$sandbox_path'
exts = {'.js','.ts','.json','.env','.yml','.yaml','.conf','.sh'}
skip = {'node_modules','.git'}

for root, dirs, files in os.walk(sandbox):
    dirs[:] = [d for d in dirs if d not in skip]
    for fname in files:
        if not any(fname.endswith(e) for e in exts) and fname != '.env':
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath, 'r') as f: content = f.read()
        except: continue
        
        changed = content
        for src, dst in ports.items():
            changed = re.sub(r'\b' + re.escape(src) + r'\b', dst, changed)
        
        if changed != content:
            with open(fpath, 'w') as f: f.write(changed)
            print(f'  🔄 {os.path.relpath(fpath, sandbox)}: {src}→{dst}')
"
}

# ─── Commands ───

cmd_create() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  local sandbox_path=$(get_sandbox_path "$project_path")
  
  if [ -d "$sandbox_path" ]; then
    echo "⚠️  Sandbox already exists: $sandbox_path"
    echo "    Use 'destroy' first or 'status' to check"
    exit 1
  fi
  
  mkdir -p "$SANDBOX_ROOT"
  echo "📦 Creating sandbox for $(basename $project_path)..."
  
  # Get port mapping (auto-detect if needed)
  local ports_json=$(get_or_detect_ports "$project_path")
  
  # Copy project
  rsync -a --exclude='node_modules' --exclude='.git' "$project_path/" "$sandbox_path/"
  
  # Init git in sandbox
  cd "$sandbox_path"
  git init -q
  git add -A
  git commit -q -m "sandbox: initial copy from $project_path"
  
  # Install dependencies
  if [ -f "$sandbox_path/package.json" ]; then
    echo "📦 Installing dependencies..."
    cd "$sandbox_path" && npm install --silent 2>/dev/null || true
  fi
  
  # Remap ports
  if [ "$ports_json" != "{}" ]; then
    echo "🔄 Remapping ports..."
    remap_ports_in_files "$sandbox_path" "$ports_json"
  fi
  
  # Save metadata
  cat > "$sandbox_path/.sandbox-meta" <<META
SOURCE=$project_path
CREATED=$(date -Iseconds)
PORTS_JSON=$ports_json
META
  
  echo ""
  echo "✅ Sandbox created: $sandbox_path"
  echo "   Source: $project_path"
  
  # Show port mapping
  if [ "$ports_json" != "{}" ]; then
    echo "   Port mapping:"
    echo "$ports_json" | python3 -c "
import json,sys
for k,v in json.load(sys.stdin).items():
    print(f'     {k} → {v}')
"
  else
    echo "   ⚠️  No ports detected. Use 'add-project' to set manually."
  fi
}

cmd_test() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  local sandbox_path=$(get_sandbox_path "$project_path")
  
  if [ ! -d "$sandbox_path" ]; then
    echo "❌ No sandbox found. Run 'create' first."
    exit 1
  fi
  
  local project_name=$(basename "$project_path")
  
  echo "🧪 Starting sandbox for $project_name..."
  
  # Determine start command
  local start_cmd="node index.js"
  if [ -f "$sandbox_path/package.json" ]; then
    local pkg_start=$(node -e "try{console.log(require('$sandbox_path/package.json').scripts.start||'')}catch(e){}" 2>/dev/null)
    if [ -n "$pkg_start" ]; then
      start_cmd="npm start"
    fi
  fi
  
  cd "$sandbox_path"
  nohup bash -c "$start_cmd" > /tmp/sandbox-${project_name}.log 2>&1 &
  local pid=$!
  echo "$pid" > "$sandbox_path/.sandbox-pid"
  
  sleep 2
  
  if kill -0 $pid 2>/dev/null; then
    echo "✅ Sandbox running (PID: $pid)"
    # Show sandbox URLs from config
    local ports_json=$(get_or_detect_ports "$project_path")
    echo "$ports_json" | python3 -c "
import json,sys
for k,v in json.load(sys.stdin).items():
    print(f'   🔗 http://95.111.247.22:{v}')
" 2>/dev/null
    echo "   📋 Logs: tail -f /tmp/sandbox-${project_name}.log"
  else
    echo "❌ Sandbox failed to start. Check logs:"
    tail -20 /tmp/sandbox-${project_name}.log
    exit 1
  fi
}

cmd_apply() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  local sandbox_path=$(get_sandbox_path "$project_path")
  
  if [ ! -d "$sandbox_path" ]; then
    echo "❌ No sandbox found."
    exit 1
  fi
  
  # Stop sandbox if running
  if [ -f "$sandbox_path/.sandbox-pid" ]; then
    local pid=$(cat "$sandbox_path/.sandbox-pid")
    kill $pid 2>/dev/null || true
    echo "⏹ Stopped sandbox process"
  fi
  
  echo "📤 Applying sandbox changes to production..."
  
  # Restore original ports
  local ports_json=$(get_or_detect_ports "$project_path")
  if [ "$ports_json" != "{}" ]; then
    remap_ports_in_files "$sandbox_path" "$ports_json" true
  fi
  
  # Sync back
  rsync -a \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='.sandbox-meta' \
    --exclude='.sandbox-pid' \
    "$sandbox_path/" "$project_path/"
  
  echo "✅ Changes applied to $project_path"
  
  local service=$(get_service_name "$project_path")
  if [ -n "$service" ]; then
    echo "   ⚠️  Restart service: systemctl restart $service"
  fi
}

cmd_destroy() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  local sandbox_path=$(get_sandbox_path "$project_path")
  
  if [ ! -d "$sandbox_path" ]; then
    echo "⚠️  No sandbox found for $(basename $project_path)"
    exit 0
  fi
  
  if [ -f "$sandbox_path/.sandbox-pid" ]; then
    local pid=$(cat "$sandbox_path/.sandbox-pid")
    kill $pid 2>/dev/null || true
  fi
  
  rm -rf "$sandbox_path"
  echo "🗑 Sandbox destroyed: $sandbox_path"
}

cmd_status() {
  echo "📊 Sandbox Status"
  echo "━━━━━━━━━━━━━━━━"
  
  if [ ! -d "$SANDBOX_ROOT" ] || [ -z "$(ls -A $SANDBOX_ROOT 2>/dev/null)" ]; then
    echo "No active sandboxes."
    return
  fi
  
  for dir in "$SANDBOX_ROOT"/*/; do
    [ -d "$dir" ] || continue
    local name=$(basename "$dir")
    local running="❌"
    
    if [ -f "$dir/.sandbox-pid" ]; then
      local pid=$(cat "$dir/.sandbox-pid")
      if kill -0 $pid 2>/dev/null; then
        running="✅ (PID: $pid)"
      fi
    fi
    
    local source="unknown"
    if [ -f "$dir/.sandbox-meta" ]; then
      source=$(grep "^SOURCE=" "$dir/.sandbox-meta" | cut -d= -f2)
    fi
    
    echo "  📁 $name"
    echo "     Source: $source"
    echo "     Running: $running"
    echo ""
  done
}

cmd_diff() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  local sandbox_path=$(get_sandbox_path "$project_path")
  
  if [ ! -d "$sandbox_path" ]; then
    echo "❌ No sandbox found."
    exit 1
  fi
  
  echo "📝 Changes in sandbox:"
  cd "$sandbox_path" && git diff --stat HEAD 2>/dev/null
  echo ""
  cd "$sandbox_path" && git diff HEAD 2>/dev/null
}

cmd_ports() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  
  local config=$(get_project_config "$project_path")
  if [ -n "$config" ]; then
    echo "📋 Saved config for $(basename $project_path):"
    echo "$config" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for k,v in d.get('ports',{}).items():
    print(f'  {k} → {v}')
svc=d.get('service','')
if svc: print(f'  Service: {svc}')
"
  else
    echo "🔍 No saved config. Auto-detecting..."
    local detected=$(detect_ports "$project_path")
    if [ -n "$detected" ]; then
      echo "  Detected ports:"
      while IFS= read -r port; do
        [ -z "$port" ] && continue
        echo "    $port → $((port + PORT_OFFSET))"
      done <<< "$detected"
    else
      echo "  No ports detected."
    fi
  fi
}

cmd_add_project() {
  local project_path="${1:?Missing project path}"
  project_path=$(realpath "$project_path")
  shift
  
  local ports_arg=""
  local service=""
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --ports) ports_arg="$2"; shift 2 ;;
      --service) service="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  
  if [ -z "$ports_arg" ]; then
    echo "❌ Missing --ports. Example: --ports 4000:10000,4001:10001"
    exit 1
  fi
  
  # Parse ports into JSON
  local ports_json="{"
  local first=true
  IFS=',' read -ra pairs <<< "$ports_arg"
  for pair in "${pairs[@]}"; do
    IFS=':' read -r src dst <<< "$pair"
    if [ "$first" = true ]; then first=false; else ports_json+=","; fi
    ports_json+="\"$src\":\"$dst\""
  done
  ports_json+="}"
  
  save_project_config "$project_path" "$ports_json" "$service"
  echo "✅ Project added: $(basename $project_path)"
  echo "   Ports: $ports_arg"
  [ -n "$service" ] && echo "   Service: $service"
}

# ─── Main ───

case "${1:-}" in
  create)      cmd_create "${2:-}" ;;
  test)        cmd_test "${2:-}" ;;
  apply)       cmd_apply "${2:-}" ;;
  destroy)     cmd_destroy "${2:-}" ;;
  status)      cmd_status ;;
  diff)        cmd_diff "${2:-}" ;;
  ports)       cmd_ports "${2:-}" ;;
  add-project) shift; cmd_add_project "$@" ;;
  *)           usage ;;
esac
