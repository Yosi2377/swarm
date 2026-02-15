#!/bin/bash
# health-check.sh — בדיקות אוטומטיות לכל השירותים
# Usage: health-check.sh [--notify] [--fix]
# --notify = שלח התראה בטלגרם אם משהו נפל
# --fix = נסה לתקן אוטומטית (restart services)

set -uo pipefail

SWARM_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY=false
AUTOFIX=false
ERRORS=()
WARNINGS=()
OK=()

for arg in "$@"; do
  case "$arg" in
    --notify) NOTIFY=true ;;
    --fix) AUTOFIX=true ;;
  esac
done

pass() { OK+=("$1"); echo "  ✅ $1"; }
fail() { ERRORS+=("$1"); echo "  ❌ $1"; }
warn() { WARNINGS+=("$1"); echo "  ⚠️ $1"; }

try_fix() {
  local service="$1"
  if $AUTOFIX; then
    echo "  🔧 Attempting restart: $service"
    systemctl restart "$service" 2>/dev/null
    sleep 2
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      echo "  🔧 Fixed! $service is running again"
      return 0
    else
      echo "  🔧 Failed to fix $service"
      return 1
    fi
  fi
  return 1
}

# ══════════════════════════════════════
echo "🏥 Health Check — $(date '+%Y-%m-%d %H:%M:%S')"
echo "══════════════════════════════════════"

# ── ZozoBet ──
echo ""
echo "🎰 ZozoBet (zozobet.duckdns.org)"
echo "──────────────────────────────"

# Backend service
if systemctl is-active --quiet betting-backend 2>/dev/null; then
  pass "betting-backend service running"
else
  fail "betting-backend service DOWN"
  try_fix "betting-backend"
fi

# Aggregator service
if systemctl is-active --quiet betting-aggregator 2>/dev/null; then
  pass "betting-aggregator service running"
else
  fail "betting-aggregator service DOWN"
  try_fix "betting-aggregator"
fi

# API returns events
EVENTS=$(curl -s --max-time 5 "http://localhost:8089/api/events" 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d))" 2>/dev/null || echo "0")
if [ "$EVENTS" -gt 0 ]; then
  pass "API returns $EVENTS events"
else
  fail "API returns 0 events"
fi

# Live events exist
LIVE=$(curl -s --max-time 5 "http://localhost:8089/api/events?live=true" 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d))" 2>/dev/null || echo "0")
if [ "$LIVE" -gt 0 ]; then
  pass "$LIVE live events with scores"
else
  warn "No live events (might be off-hours)"
fi

# MongoDB connected
MONGO=$(mongosh --quiet --eval "db.events.countDocuments()" betting 2>/dev/null || echo "0")
if [ "$MONGO" -gt 0 ]; then
  pass "MongoDB: $MONGO events in DB"
else
  fail "MongoDB connection failed or empty"
fi

# Redis connected
REDIS=$(redis-cli -a 123456 PING 2>/dev/null || echo "FAIL")
if [ "$REDIS" = "PONG" ]; then
  pass "Redis connected"
else
  fail "Redis not responding"
fi

# BetsAPI rate limit
RATE_REMAINING=$(curl -s -D /dev/stdout -o /dev/null --max-time 5 "https://api.b365api.com/v1/bet365/upcoming?sport_id=1&token=246040-qAUnad5f8My9aG" 2>/dev/null | grep -i "x-ratelimit-remaining" | awk '{print $2}' | tr -d '\r')
if [ -n "$RATE_REMAINING" ] && [ "$RATE_REMAINING" -gt 100 ]; then
  pass "BetsAPI rate limit: $RATE_REMAINING remaining"
elif [ -n "$RATE_REMAINING" ]; then
  warn "BetsAPI rate limit LOW: $RATE_REMAINING remaining"
else
  warn "Could not check BetsAPI rate limit"
fi

# ── Texas Poker ──
echo ""
echo "🃏 Texas Poker (zozopoker.duckdns.org)"
echo "──────────────────────────────"

if systemctl is-active --quiet texas-poker 2>/dev/null; then
  pass "texas-poker service running"
else
  fail "texas-poker service DOWN"
  try_fix "texas-poker"
fi

POKER_HTTP=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "http://localhost:7001" 2>/dev/null || echo "000")
if [ "$POKER_HTTP" = "200" ] || [ "$POKER_HTTP" = "101" ] || [ "$POKER_HTTP" = "404" ]; then
  pass "Poker server responding (HTTP $POKER_HTTP)"
else
  fail "Poker server not responding (HTTP $POKER_HTTP)"
fi

# ── Dashboard ──
echo ""
echo "📊 Dashboard (tworkswarm.duckdns.org)"
echo "──────────────────────────────"

if systemctl is-active --quiet swarm-dashboard 2>/dev/null; then
  pass "swarm-dashboard service running"
else
  fail "swarm-dashboard service DOWN"
  try_fix "swarm-dashboard"
fi

DASH_HTTP=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "http://localhost:8090" 2>/dev/null || echo "000")
if [ "$DASH_HTTP" = "200" ]; then
  pass "Dashboard responding (HTTP $DASH_HTTP)"
else
  fail "Dashboard not responding (HTTP $DASH_HTTP)"
fi

# ── Nginx + SSL ──
echo ""
echo "🔒 Nginx + SSL"
echo "──────────────────────────────"

if systemctl is-active --quiet nginx 2>/dev/null; then
  pass "nginx running"
else
  fail "nginx DOWN"
  try_fix "nginx"
fi

for domain in zozobet.duckdns.org zozopoker.duckdns.org tworkswarm.duckdns.org; do
  SSL_DAYS=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  if [ -n "$SSL_DAYS" ]; then
    pass "SSL $domain valid until $SSL_DAYS"
  else
    warn "Could not check SSL for $domain"
  fi
done

# ── System ──
echo ""
echo "💻 System"
echo "──────────────────────────────"

DISK=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK" -lt 80 ]; then
  pass "Disk usage: ${DISK}%"
elif [ "$DISK" -lt 90 ]; then
  warn "Disk usage: ${DISK}% (getting full!)"
else
  fail "Disk usage: ${DISK}% CRITICAL"
fi

MEM=$(free -m | awk 'NR==2 {printf "%.0f", $3/$2*100}')
if [ "$MEM" -lt 80 ]; then
  pass "Memory usage: ${MEM}%"
else
  warn "Memory usage: ${MEM}%"
fi

# ══════════════════════════════════════
echo ""
echo "══════════════════════════════════════"
echo "📊 Results: ${#OK[@]} ✅ | ${#WARNINGS[@]} ⚠️ | ${#ERRORS[@]} ❌"
echo "══════════════════════════════════════"

# ── Send Telegram notification if errors ──
if $NOTIFY && [ ${#ERRORS[@]} -gt 0 ]; then
  MSG="🚨 <b>Health Check Alert!</b>%0A%0A"
  for e in "${ERRORS[@]}"; do
    MSG+="❌ $e%0A"
  done
  for w in "${WARNINGS[@]}"; do
    MSG+="⚠️ $w%0A"
  done
  MSG+="%0A✅ ${#OK[@]} passed"
  
  BOT_TOKEN=$(cat "$SWARM_DIR/.bot-token" 2>/dev/null)
  if [ -n "$BOT_TOKEN" ]; then
    curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d "chat_id=-1003815143703" \
      -d "parse_mode=HTML" \
      -d "text=$MSG" > /dev/null 2>&1
  fi
fi

# Exit code
if [ ${#ERRORS[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi
