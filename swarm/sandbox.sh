#!/bin/bash
# sandbox.sh — Sandbox Environment Manager for Swarm Agents
# Creates isolated copies of projects for safe development

set -euo pipefail

SANDBOX_ROOT="/root/sandbox"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Port mapping: production → sandbox
declare -A PORT_MAP=(
  # TexasPokerGame
  ["8088"]="9088"
  ["7001"]="9001"
  # Blackjack
  ["3000"]="9000"
  # BettingPlatform
  ["3001"]="9301"
  ["3002"]="9302"
  ["8089"]="9089"
)

# Project configs
declare -A PROJECT_PORTS=(
  ["/root/TexasPokerGame"]="8088,7001"
  ["/root/Blackjack-Game-Multiplayer"]="3000"
  ["/root/BettingPlatform"]="3001,3002,8089"
)

declare -A PROJECT_SERVICE=(
  ["/root/TexasPokerGame"]="texas-poker"
  ["/root/Blackjack-Game-Multiplayer"]="blackjack"
  ["/root/BettingPlatform"]="betting-backend"
)

usage() {
  cat <<EOF
Usage: sandbox.sh <command> [project_path]

Commands:
  create  <path>  — Clone project to sandbox with port remapping
  test    <path>  — Start sandbox on sandbox ports
  apply   <path>  — Copy sandbox changes back to production
  destroy <path>  — Remove sandbox
  status          — Show active sandboxes
  diff    <path>  — Show diff between sandbox and production

Examples:
  sandbox.sh create /root/Blackjack-Game-Multiplayer
  sandbox.sh test /root/Blackjack-Game-Multiplayer
  sandbox.sh apply /root/Blackjack-Game-Multiplayer
  sandbox.sh destroy /root/Blackjack-Game-Multiplayer
EOF
  exit 1
}

get_sandbox_path() {
  local project_path="$1"
  local project_name=$(basename "$project_path")
  echo "${SANDBOX_ROOT}/${project_name}"
}

# Remap ports in files
remap_ports() {
  local sandbox_path="$1"
  local project_path="$2"
  local ports="${PROJECT_PORTS[$project_path]:-}"
  
  if [ -z "$ports" ]; then
    echo "⚠️  No port mapping defined for $project_path"
    return 0
  fi
  
  IFS=',' read -ra port_list <<< "$ports"
  for port in "${port_list[@]}"; do
    local sandbox_port="${PORT_MAP[$port]:-}"
    if [ -n "$sandbox_port" ]; then
      echo "  🔄 Port $port → $sandbox_port"
      # Replace in common config files
      find "$sandbox_path" -maxdepth 3 \
        -name "*.js" -o -name "*.json" -o -name "*.env" -o -name "*.conf" -o -name "*.yml" -o -name "*.yaml" \
        2>/dev/null | while read -r f; do
          if grep -q "\b${port}\b" "$f" 2>/dev/null; then
            sed -i "s/\b${port}\b/${sandbox_port}/g" "$f"
          fi
        done
    fi
  done
}

# Restore original ports in files (for apply)
restore_ports() {
  local sandbox_path="$1"
  local project_path="$2"
  local ports="${PROJECT_PORTS[$project_path]:-}"
  
  if [ -z "$ports" ]; then return 0; fi
  
  IFS=',' read -ra port_list <<< "$ports"
  for port in "${port_list[@]}"; do
    local sandbox_port="${PORT_MAP[$port]:-}"
    if [ -n "$sandbox_port" ]; then
      find "$sandbox_path" -maxdepth 3 \
        -name "*.js" -o -name "*.json" -o -name "*.env" -o -name "*.conf" -o -name "*.yml" -o -name "*.yaml" \
        2>/dev/null | while read -r f; do
          if grep -q "\b${sandbox_port}\b" "$f" 2>/dev/null; then
            sed -i "s/\b${sandbox_port}\b/${port}/g" "$f"
          fi
        done
    fi
  done
}

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
  
  # Copy project (excluding node_modules, .git heavy objects)
  rsync -a --exclude='node_modules' --exclude='.git' "$project_path/" "$sandbox_path/"
  
  # Init git in sandbox for tracking changes
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
  echo "🔄 Remapping ports..."
  remap_ports "$sandbox_path" "$project_path"
  
  # Save metadata
  cat > "$sandbox_path/.sandbox-meta" <<META
SOURCE=$project_path
CREATED=$(date -Iseconds)
PORTS=${PROJECT_PORTS[$project_path]:-none}
META
  
  echo "✅ Sandbox created: $sandbox_path"
  echo "   Source: $project_path"
  echo "   Ports remapped: ${PROJECT_PORTS[$project_path]:-none}"
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
  local ports="${PROJECT_PORTS[$project_path]:-}"
  
  echo "🧪 Starting sandbox for $project_name..."
  
  # Determine start command
  local start_cmd="node index.js"
  if [ -f "$sandbox_path/package.json" ]; then
    local pkg_start=$(node -e "try{console.log(require('$sandbox_path/package.json').scripts.start||'')}catch(e){}" 2>/dev/null)
    if [ -n "$pkg_start" ]; then
      start_cmd="npm start"
    fi
  fi
  
  # Start in background
  cd "$sandbox_path"
  nohup bash -c "$start_cmd" > /tmp/sandbox-${project_name}.log 2>&1 &
  local pid=$!
  echo "$pid" > "$sandbox_path/.sandbox-pid"
  
  sleep 2
  
  if kill -0 $pid 2>/dev/null; then
    # Show sandbox URLs
    IFS=',' read -ra port_list <<< "$ports"
    echo "✅ Sandbox running (PID: $pid)"
    for port in "${port_list[@]}"; do
      local sandbox_port="${PORT_MAP[$port]:-$port}"
      echo "   🔗 http://95.111.247.22:$sandbox_port"
    done
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
  
  # Restore original ports before copying
  restore_ports "$sandbox_path" "$project_path"
  
  # Sync changes back (excluding sandbox-specific files)
  rsync -a \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='.sandbox-meta' \
    --exclude='.sandbox-pid' \
    "$sandbox_path/" "$project_path/"
  
  echo "✅ Changes applied to $project_path"
  echo "   ⚠️  Remember to restart the production service!"
  
  local service="${PROJECT_SERVICE[$project_path]:-}"
  if [ -n "$service" ]; then
    echo "   Run: systemctl restart $service"
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
  
  # Stop if running
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
  
  echo "📝 Changes in sandbox vs production:"
  diff -rq \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='.sandbox-meta' \
    --exclude='.sandbox-pid' \
    "$project_path" "$sandbox_path" 2>/dev/null || true
}

# Main
case "${1:-}" in
  create)  cmd_create "${2:-}" ;;
  test)    cmd_test "${2:-}" ;;
  apply)   cmd_apply "${2:-}" ;;
  destroy) cmd_destroy "${2:-}" ;;
  status)  cmd_status ;;
  diff)    cmd_diff "${2:-}" ;;
  *)       usage ;;
esac
