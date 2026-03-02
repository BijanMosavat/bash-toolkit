#!/usr/bin/env bash
# ==============================================================================
# health_check.sh — Quick system health check
# Author: Bijan Mosavat
# Version: 1.0.0
#
# What it does:
#   Gives a snapshot of your system health:
#     • CPU load & usage
#     • Memory and swap usage
#     • Disk usage per mount
#     • Checks if important services are running
#     • Basic internet connectivity
#     • Counts open ports listening on your machine
#
# Why:
#   Useful for quick audits, cron jobs, or showing off monitoring skills.
#
# Usage:
#   ./health_check.sh [--services "nginx mysql ssh"] [--disk-warn 80]
#                     [--cpu-warn 85] [--mem-warn 90] [--log /path/to/log]
#                     [--json]
# ==============================================================================

set -euo pipefail

VERSION="1.0.0"

# -----------------------------
# Default settings
# -----------------------------
DISK_WARN=80           # Disk usage % threshold for warnings
CPU_WARN=85            # CPU usage % threshold
MEM_WARN=90            # Memory usage % threshold
SERVICES=("ssh" "cron")  # Critical services to check
LOG_FILE="/var/log/health_check.log"
JSON_MODE=false
ALERT=0                # Will flip to 1 if any check fails

# -----------------------------
# Colors for terminal output
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# -----------------------------
# Handle command line arguments
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --services) IFS=' ' read -r -a SERVICES <<< "$2"; shift 2 ;;
    --disk-warn) DISK_WARN="$2"; shift 2 ;;
    --cpu-warn) CPU_WARN="$2"; shift 2 ;;
    --mem-warn) MEM_WARN="$2"; shift 2 ;;
    --log) LOG_FILE="$2"; shift 2 ;;
    --json) JSON_MODE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# -----------------------------
# Helper functions
# -----------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
ok() { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; ALERT=1; }
fail() { echo -e "  ${RED}✖${RESET}  $*"; ALERT=1; }
header() { echo -e "\n${BOLD}${BLUE}── $* ──────────────────────────────${RESET}"; }

JSON_OUTPUT="{"

# -----------------------------
# Banner
# -----------------------------
if [[ "$JSON_MODE" = false ]]; then
  echo -e "${BOLD}"
  echo "╔══════════════════════════════════╗"
  printf "║  SYSTEM HEALTH CHECK v%-6s     ║\n" "$VERSION"
  printf "║  Host: %-16s %-16s ║\n" "$(hostname)" "$(date '+%Y-%m-%d %H:%M')"
  echo "╚══════════════════════════════════╝"
  echo -e "${RESET}"
fi

log "Health check started"

# -----------------------------
# CPU check (using /proc/stat)
# -----------------------------
CPU_IDLE1=$(awk '/^cpu / {print $5}' /proc/stat)
CPU_TOTAL1=$(awk '/^cpu / {sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}' /proc/stat)
sleep 1
CPU_IDLE2=$(awk '/^cpu / {print $5}' /proc/stat)
CPU_TOTAL2=$(awk '/^cpu / {sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}' /proc/stat)

IDLE_DIFF=$((CPU_IDLE2 - CPU_IDLE1))
TOTAL_DIFF=$((CPU_TOTAL2 - CPU_TOTAL1))
CPU_USED=$((100 * (TOTAL_DIFF - IDLE_DIFF) / TOTAL_DIFF))
LOAD=$(cut -d ' ' -f1 /proc/loadavg)

if [[ "$JSON_MODE" = false ]]; then
  header "CPU"
  if (( CPU_USED >= CPU_WARN )); then
    warn "CPU usage: ${CPU_USED}% (above ${CPU_WARN}%)"
  else
    ok "CPU usage: ${CPU_USED}%"
  fi
  ok "Load average (1 min): ${LOAD}"
fi

JSON_OUTPUT+="\"cpu\":{\"usage\":$CPU_USED,\"load_1m\":$LOAD},"

# -----------------------------
# Memory check
# -----------------------------
MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
MEM_AVAILABLE=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
MEM_PCT=$((100 * MEM_USED / MEM_TOTAL))
SWAP_USED=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END {print int((t-f)/1024)}' /proc/meminfo)

if [[ "$JSON_MODE" = false ]]; then
  header "Memory"
  if (( MEM_PCT >= MEM_WARN )); then
    warn "Memory usage: ${MEM_USED}/${MEM_TOTAL}MB (${MEM_PCT}%)"
  else
    ok "Memory usage: ${MEM_USED}/${MEM_TOTAL}MB (${MEM_PCT}%)"
  fi
  ok "Swap used: ${SWAP_USED}MB"
fi

JSON_OUTPUT+="\"memory\":{\"used_mb\":$MEM_USED,\"total_mb\":$MEM_TOTAL,\"percent\":$MEM_PCT},"

# -----------------------------
# Disk check
# -----------------------------
if [[ "$JSON_MODE" = false ]]; then
  header "Disk Usage"
fi

JSON_OUTPUT+="\"disk\":["
FIRST=true

while IFS= read -r line; do
  USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
  MOUNT=$(echo "$line" | awk '{print $6}')
  SIZE=$(echo "$line"  | awk '{print $2}')
  USED=$(echo "$line"  | awk '{print $3}')

  if [[ "$JSON_MODE" = false ]]; then
    if (( USAGE >= DISK_WARN )); then
      warn "Disk ${MOUNT}: ${USED}/${SIZE} (${USAGE}%)"
    else
      ok "Disk ${MOUNT}: ${USED}/${SIZE} (${USAGE}%)"
    fi
  fi

  [[ "$FIRST" = false ]] && JSON_OUTPUT+=","
  JSON_OUTPUT+="{\"mount\":\"$MOUNT\",\"usage_percent\":$USAGE}"
  FIRST=false
done < <(df -h | awk 'NR>1 && $1 ~ /^\/dev/')

JSON_OUTPUT+="],"

# -----------------------------
# Services check
# -----------------------------
if [[ "$JSON_MODE" = false ]]; then
  header "Services"
fi

JSON_OUTPUT+="\"services\":{"
FIRST=true

for svc in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    STATUS="running"
    [[ "$JSON_MODE" = false ]] && ok "Service ${svc}: running"
  else
    STATUS="stopped"
    ALERT=1
    [[ "$JSON_MODE" = false ]] && fail "Service ${svc}: NOT running"
  fi

  [[ "$FIRST" = false ]] && JSON_OUTPUT+=","
  JSON_OUTPUT+="\"$svc\":\"$STATUS\""
  FIRST=false
done

JSON_OUTPUT+="},"

# -----------------------------
# Network check
# -----------------------------
PING_STATUS="unreachable"
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
  PING_STATUS="reachable"
  [[ "$JSON_MODE" = false ]] && header "Network" && ok "Internet reachable"
else
  ALERT=1
  [[ "$JSON_MODE" = false ]] && header "Network" && warn "Internet unreachable"
fi

OPEN_PORTS=$(ss -tuln | awk '/LISTEN/ {count++} END {print count+0}')
[[ "$JSON_MODE" = false ]] && ok "Open ports: ${OPEN_PORTS}"

JSON_OUTPUT+="\"network\":{\"internet\":\"$PING_STATUS\",\"open_ports\":$OPEN_PORTS}}"

# -----------------------------
# Output results
# -----------------------------
if [[ "$JSON_MODE" = true ]]; then
  echo "$JSON_OUTPUT"
  exit $ALERT
fi

echo ""
echo "────────────────────────────────────────────"
if [[ $ALERT -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✔ Everything looks good!${RESET}"
  log "Health check PASSED"
else
  echo -e "${RED}${BOLD}✖ Some checks need attention.${RESET}"
  log "Health check FAILED"
fi

exit $ALERT
