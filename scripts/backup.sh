#!/usr/bin/env bash
# ==============================================================================
# backup.sh — Automated Backup with Rotation
# Author: Bijan Mosavat
# Description: Backs up one or more source directories to a destination,
#              creates timestamped compressed archives, and rotates old backups.
# Usage: ./backup.sh --source /var/www --dest /mnt/backups [--retain 7] [--name myapp]
# ==============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SOURCES=()
DEST=""
RETAIN=7
BACKUP_NAME="backup"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="/var/log/backup.log"
COMPRESS="gzip"   # gzip or bzip2

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Parse Arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  SOURCES+=("$2");     shift 2 ;;
    --dest)    DEST="$2";           shift 2 ;;
    --retain)  RETAIN="$2";         shift 2 ;;
    --name)    BACKUP_NAME="$2";    shift 2 ;;
    --log)     LOG_FILE="$2";       shift 2 ;;
    --bzip2)   COMPRESS="bzip2";    shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[ERROR]${RESET} $*" >&2; log "ERROR: $*"; exit 1; }

[[ ${#SOURCES[@]} -eq 0 ]] && err "No --source specified. Use: --source /path/to/dir"
[[ -z "$DEST" ]]           && err "No --dest specified. Use: --dest /path/to/backup/dir"

for src in "${SOURCES[@]}"; do
  [[ -d "$src" ]] || err "Source directory does not exist: $src"
done

mkdir -p "$DEST" || err "Cannot create destination directory: $DEST"

# ── Set compression extension ─────────────────────────────────────────────────
EXT="tar.gz"
TAR_FLAG="-czf"
[[ "$COMPRESS" == "bzip2" ]] && { EXT="tar.bz2"; TAR_FLAG="-cjf"; }

ARCHIVE_NAME="${BACKUP_NAME}_${TIMESTAMP}.${EXT}"
ARCHIVE_PATH="${DEST}/${ARCHIVE_NAME}"

# ── Run Backup ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── BACKUP STARTED ──────────────────────────${RESET}"
echo -e "  Sources:     ${SOURCES[*]}"
echo -e "  Destination: ${ARCHIVE_PATH}"
echo -e "  Compression: ${COMPRESS}"
echo -e "  Retention:   ${RETAIN} backups"
echo ""

log "Starting backup: ${ARCHIVE_NAME}"
log "Sources: ${SOURCES[*]}"

START_TIME=$SECONDS

tar "$TAR_FLAG" "$ARCHIVE_PATH" "${SOURCES[@]}" 2>/dev/null \
  && echo -e "  ${GREEN}✔${RESET}  Archive created: ${ARCHIVE_NAME}" \
  || err "Failed to create archive"

ELAPSED=$(( SECONDS - START_TIME ))
SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)

log "Archive created: ${ARCHIVE_PATH} | Size: ${SIZE} | Time: ${ELAPSED}s"
echo -e "  ${GREEN}✔${RESET}  Size: ${SIZE} | Completed in ${ELAPSED}s"

# ── Verify Archive ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}── VERIFYING ARCHIVE ───────────────────────${RESET}"
if tar -tf "$ARCHIVE_PATH" &>/dev/null; then
  echo -e "  ${GREEN}✔${RESET}  Archive integrity: OK"
  log "Archive integrity verified: OK"
else
  err "Archive verification FAILED — archive may be corrupt"
fi

# ── Rotate Old Backups ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}── ROTATING OLD BACKUPS ────────────────────${RESET}"

EXISTING=$(find "$DEST" -maxdepth 1 -name "${BACKUP_NAME}_*.${EXT}" | sort)
COUNT=$(echo "$EXISTING" | grep -c . || true)

if (( COUNT > RETAIN )); then
  TO_DELETE=$(( COUNT - RETAIN ))
  echo "$EXISTING" | head -n "$TO_DELETE" | while read -r old; do
    rm -f "$old"
    echo -e "  ${YELLOW}✖${RESET}  Deleted old backup: $(basename "$old")"
    log "Deleted old backup: $old"
  done
else
  echo -e "  ${GREEN}✔${RESET}  ${COUNT} backup(s) exist — within retention limit (${RETAIN})"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
REMAINING=$(find "$DEST" -maxdepth 1 -name "${BACKUP_NAME}_*.${EXT}" | wc -l)
echo -e "${GREEN}${BOLD}  ✔  Backup complete. ${REMAINING} backup(s) retained.${RESET}"
echo ""
log "Backup complete. Retained: ${REMAINING} backup(s)"
