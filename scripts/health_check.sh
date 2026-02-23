wadsdsadsadsadsaddswdasdwdsda#!/usr/bin/env bash
# ==============================================================================
# health_check.sh — System Health Monitor
# Author: Bijan Mosavat
# Description: Checks CPU, memory, disk, load average, and critical services.
#              Outputs a clean report and exits with non-zero if thresholds exceeded.
# Usage: ./health_check.sh [--services "nginx mysql ssh"] [--disk-warn 80] [--cpu-warn 85]
# ==============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DISK_WARN=80
CPU_WARN=85
MEM_WARN=90
SERVICES=("ssh" "cron")
LOG_FILE="/var/log/health_check.log"
ALERT=0

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Parse Arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --services)   IFS=' ' read -r -a SERVICES <<< "$2"; shift 2 ;;
    --disk-warn)  DISK_WARN="$2"; shift 2 ;;
    --cpu-warn)   CPU_WARN="$2"; shift 2 ;;
    --mem-warn)   MEM_WARN="$2"; shift 2 ;;
    --log)        LOG_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; ALERT=1; }
fail() { echo -e "  ${RED}✖${RESET}  $*"; ALERT=1; }
header() { echo -e "\n${BOLD}${BLUE}── $* ──────────────────────────────${RESET}"; }

# ── Report Header ─────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║         SYSTEM HEALTH CHECK              ║"
echo "║  Host: $(hostname)  │  $(date '+%Y-%m-%d %H:%M')   ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${RESET}"

log "Health check started on $(hostname)"

# ── CPU ───────────────────────────────────────────────────────────────────────
header "CPU"
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%')
CPU_USED=$(echo "100 - $CPU_IDLE" | bc 2>/dev/null || echo "0")
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')

if (( $(echo "$CPU_USED >= $CPU_WARN" | bc -l 2>/dev/null || echo 0) )); then
  warn "CPU usage: ${CPU_USED}% (threshold: ${CPU_WARN}%)"
else
  ok "CPU usage: ${CPU_USED}%"
fi
ok "Load average (1m): ${LOAD}"

# ── Memory ────────────────────────────────────────────────────────────────────
header "Memory"
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
MEM_PCT=$(echo "scale=1; $MEM_USED * 100 / $MEM_TOTAL" | bc)
SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')

if (( $(echo "$MEM_PCT >= $MEM_WARN" | bc -l 2>/dev/null || echo 0) )); then
  warn "Memory usage: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
else
  ok "Memory usage: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
fi
ok "Swap used: ${SWAP_USED}MB"

# ── Disk ──────────────────────────────────────────────────────────────────────
header "Disk Usage"
while IFS= read -r line; do
  USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
  MOUNT=$(echo "$line" | awk '{print $6}')
  SIZE=$(echo "$line"  | awk '{print $2}')
  USED=$(echo "$line"  | awk '{print $3}')

  if (( USAGE >= DISK_WARN )); then
    warn "Disk ${MOUNT}: ${USED} / ${SIZE} (${USAGE}%) — ABOVE THRESHOLD"
  else
    ok "Disk ${MOUNT}: ${USED} / ${SIZE} (${USAGE}%)"
  fi
done < <(df -h | awk 'NR>1 && $1 ~ /^\/dev/' )

# ── Services ──────────────────────────────────────────────────────────────────
header "Services"
for svc in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    ok "Service ${svc}: running"
  else
    fail "Service ${svc}: NOT running"
  fi
done

# ── Network ───────────────────────────────────────────────────────────────────
header "Network"
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
  ok "Internet connectivity: reachable"
else
  warn "Internet connectivity: UNREACHABLE"
fi

OPEN_PORTS=$(ss -tuln | grep LISTEN | wc -l)
ok "Open listening ports: ${OPEN_PORTS}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
if [[ $ALERT -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✔  All checks passed. System is healthy.${RESET}"
  log "Health check PASSED"
  exit 0
else
  echo -e "${RED}${BOLD}  ✖  One or more checks failed. Review above.${RESET}"
  log "Health check FAILED — review $LOG_FILE"
  exit 1
fi
