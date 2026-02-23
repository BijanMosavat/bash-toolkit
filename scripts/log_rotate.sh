#!/usr/bin/env bash
# ==============================================================================
# log_rotate.sh — Log Rotation and Cleanup
# Author: Bijan Mosavat
# Description: Rotates log files by size or age, compresses old logs,
#              and removes logs beyond the retention period.
# Usage: ./log_rotate.sh --dir /var/log/myapp [--max-size 50M] [--retain-days 30]
# ==============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
LOG_DIR=""
MAX_SIZE="50M"
RETAIN_DAYS=30
PATTERN="*.log"
COMPRESS=true
DRY_RUN=false
SCRIPT_LOG="/var/log/log_rotate.log"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Parse Arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)          LOG_DIR="$2";       shift 2 ;;
    --max-size)     MAX_SIZE="$2";      shift 2 ;;
    --retain-days)  RETAIN_DAYS="$2";   shift 2 ;;
    --pattern)      PATTERN="$2";       shift 2 ;;
    --no-compress)  COMPRESS=false;     shift ;;
    --dry-run)      DRY_RUN=true;       shift ;;
    --log)          SCRIPT_LOG="$2";    shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SCRIPT_LOG"; }
ok()     { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
skipped(){ echo -e "  ${BLUE}→${RESET}  [DRY RUN] Would: $*"; }
err()    { echo -e "${RED}[ERROR]${RESET} $*" >&2; log "ERROR: $*"; exit 1; }

do_or_dry() {
  if [[ "$DRY_RUN" == true ]]; then
    skipped "$*"
  else
    eval "$*"
  fi
}

# ── Validation ────────────────────────────────────────────────────────────────
[[ -z "$LOG_DIR" ]] && err "No --dir specified. Use: --dir /path/to/logs"
[[ -d "$LOG_DIR" ]] || err "Directory does not exist: $LOG_DIR"

# Convert max size to bytes for comparison
SIZE_BYTES=$(numfmt --from=iec "$MAX_SIZE" 2>/dev/null || echo 52428800)

# ── Header ────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── LOG ROTATION ────────────────────────────${RESET}"
echo -e "  Directory:    ${LOG_DIR}"
echo -e "  Pattern:      ${PATTERN}"
echo -e "  Max Size:     ${MAX_SIZE}"
echo -e "  Retain Days:  ${RETAIN_DAYS}"
echo -e "  Compress:     ${COMPRESS}"
[[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}Mode: DRY RUN — no changes will be made${RESET}"
echo ""

log "Log rotation started | dir=$LOG_DIR pattern=$PATTERN max_size=$MAX_SIZE retain=${RETAIN_DAYS}d"

ROTATED=0
COMPRESSED=0
DELETED=0

# ── Rotate Oversized Logs ─────────────────────────────────────────────────────
echo -e "${BOLD}Checking log sizes...${RESET}"
while IFS= read -r logfile; do
  [[ -f "$logfile" ]] || continue
  FILE_SIZE=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile")

  if (( FILE_SIZE >= SIZE_BYTES )); then
    ROTATED_NAME="${logfile}.$(date '+%Y%m%d_%H%M%S')"
    do_or_dry "mv '$logfile' '$ROTATED_NAME'"
    do_or_dry "touch '$logfile'"
    ok "Rotated: $(basename "$logfile") ($(numfmt --to=iec "$FILE_SIZE" 2>/dev/null || echo "${FILE_SIZE}B"))"
    log "Rotated: $logfile → $ROTATED_NAME"
    (( ROTATED++ )) || true

    if [[ "$COMPRESS" == true ]]; then
      do_or_dry "gzip '$ROTATED_NAME'"
      ok "Compressed: $(basename "$ROTATED_NAME").gz"
      log "Compressed: ${ROTATED_NAME}.gz"
      (( COMPRESSED++ )) || true
    fi
  else
    SIZE_HUMAN=$(numfmt --to=iec "$FILE_SIZE" 2>/dev/null || echo "${FILE_SIZE}B")
    echo -e "  ${BLUE}→${RESET}  $(basename "$logfile"): ${SIZE_HUMAN} — OK"
  fi
done < <(find "$LOG_DIR" -maxdepth 2 -name "$PATTERN" -not -name "*.gz")

# ── Compress Uncompressed Rotated Logs ────────────────────────────────────────
echo ""
echo -e "${BOLD}Compressing uncompressed rotated logs...${RESET}"
FOUND_UNCOMPRESSED=0
while IFS= read -r old_log; do
  [[ -f "$old_log" ]] || continue
  do_or_dry "gzip '$old_log'"
  ok "Compressed: $(basename "$old_log")"
  log "Compressed old log: $old_log"
  (( COMPRESSED++ )) || true
  (( FOUND_UNCOMPRESSED++ )) || true
done < <(find "$LOG_DIR" -maxdepth 2 -name "${PATTERN%.*}.*[0-9]" -not -name "*.gz" 2>/dev/null || true)
[[ $FOUND_UNCOMPRESSED -eq 0 ]] && echo -e "  ${BLUE}→${RESET}  No uncompressed rotated logs found"

# ── Delete Old Logs ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Removing logs older than ${RETAIN_DAYS} days...${RESET}"
FOUND_OLD=0
while IFS= read -r old_log; do
  [[ -f "$old_log" ]] || continue
  do_or_dry "rm -f '$old_log'"
  warn "Deleted: $(basename "$old_log")"
  log "Deleted old log: $old_log"
  (( DELETED++ )) || true
  (( FOUND_OLD++ )) || true
done < <(find "$LOG_DIR" -maxdepth 2 \( -name "*.gz" -o -name "$PATTERN" \) -mtime +"$RETAIN_DAYS" 2>/dev/null || true)
[[ $FOUND_OLD -eq 0 ]] && ok "No logs older than ${RETAIN_DAYS} days found"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}  ✔  Done.${RESET}"
echo -e "      Rotated:    ${ROTATED} file(s)"
echo -e "      Compressed: ${COMPRESSED} file(s)"
echo -e "      Deleted:    ${DELETED} file(s)"
echo ""
log "Rotation complete | rotated=$ROTATED compressed=$COMPRESSED deleted=$DELETED"
