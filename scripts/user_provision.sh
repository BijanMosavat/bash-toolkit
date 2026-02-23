#!/usr/bin/env bash
# ==============================================================================
# user_provision.sh — User Provisioning and Deprovisioning
# Author: Bijan Mosavat
# Description: Create or remove Linux users, assign groups, set up SSH keys,
#              enforce password policies, and log all actions for audit.
# Usage:
#   Create:  ./user_provision.sh --action create --user john --groups sudo,docker --ssh-key "ssh-rsa AAA..."
#   Delete:  ./user_provision.sh --action delete --user john [--purge]
#   List:    ./user_provision.sh --action list
# ==============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
ACTION=""
USERNAME=""
GROUPS=""
SSH_KEY=""
SHELL="/bin/bash"
HOME_BASE="/home"
PURGE=false
AUDIT_LOG="/var/log/user_provision.log"
REQUIRE_ROOT=true

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Parse Arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)    ACTION="$2";     shift 2 ;;
    --user)      USERNAME="$2";   shift 2 ;;
    --groups)    GROUPS="$2";     shift 2 ;;
    --ssh-key)   SSH_KEY="$2";    shift 2 ;;
    --shell)     SHELL="$2";      shift 2 ;;
    --log)       AUDIT_LOG="$2";  shift 2 ;;
    --purge)     PURGE=true;      shift ;;
    --no-root)   REQUIRE_ROOT=false; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
audit() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$(whoami)] $*" | tee -a "$AUDIT_LOG"; }
ok()    { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; audit "ERROR: $*"; exit 1; }
info()  { echo -e "  ${BLUE}→${RESET}  $*"; }

# ── Root Check ────────────────────────────────────────────────────────────────
if [[ "$REQUIRE_ROOT" == true && $EUID -ne 0 ]]; then
  err "This script must be run as root. Use: sudo $0 $*"
fi

# ── Validate Action ───────────────────────────────────────────────────────────
[[ -z "$ACTION" ]] && err "No --action specified. Use: create | delete | list"

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: LIST
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "list" ]]; then
  echo -e "\n${BOLD}${BLUE}── SYSTEM USERS (UID >= 1000) ──────────────${RESET}"
  printf "  %-20s %-10s %-30s %s\n" "USERNAME" "UID" "HOME" "SHELL"
  echo "  ──────────────────────────────────────────────────────────────"
  while IFS=: read -r user _ uid gid _ home shell; do
    (( uid >= 1000 && uid != 65534 )) || continue
    GROUPS_LIST=$(id -Gn "$user" 2>/dev/null | tr ' ' ',')
    printf "  %-20s %-10s %-30s %s\n" "$user" "$uid" "$home" "$shell"
    echo -e "  ${BLUE}→${RESET}  Groups: ${GROUPS_LIST}"
    echo ""
  done < /etc/passwd
  exit 0
fi

# ── Validate Username ─────────────────────────────────────────────────────────
[[ -z "$USERNAME" ]] && err "No --user specified."
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || err "Invalid username: '$USERNAME'. Use lowercase letters, numbers, hyphens, underscores."

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: CREATE
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "create" ]]; then
  echo -e "\n${BOLD}${BLUE}── CREATING USER: ${USERNAME} ───────────────${RESET}"

  # Check if user already exists
  if id "$USERNAME" &>/dev/null; then
    warn "User '$USERNAME' already exists — skipping creation"
  else
    useradd \
      --create-home \
      --home-dir "${HOME_BASE}/${USERNAME}" \
      --shell "$SHELL" \
      --comment "Provisioned by user_provision.sh on $(date '+%Y-%m-%d')" \
      "$USERNAME"
    ok "User created: ${USERNAME} (home: ${HOME_BASE}/${USERNAME}, shell: ${SHELL})"
    audit "CREATE user=$USERNAME home=${HOME_BASE}/${USERNAME} shell=$SHELL"
  fi

  # Assign groups
  if [[ -n "$GROUPS" ]]; then
    IFS=',' read -r -a GROUP_LIST <<< "$GROUPS"
    for group in "${GROUP_LIST[@]}"; do
      group=$(echo "$group" | xargs)
      if getent group "$group" &>/dev/null; then
        usermod -aG "$group" "$USERNAME"
        ok "Added to group: ${group}"
        audit "ADD_GROUP user=$USERNAME group=$group"
      else
        warn "Group '$group' does not exist — skipping"
      fi
    done
  fi

  # Set up SSH key
  if [[ -n "$SSH_KEY" ]]; then
    SSH_DIR="${HOME_BASE}/${USERNAME}/.ssh"
    AUTH_KEYS="${SSH_DIR}/authorized_keys"
    mkdir -p "$SSH_DIR"
    echo "$SSH_KEY" >> "$AUTH_KEYS"
    chmod 700 "$SSH_DIR"
    chmod 600 "$AUTH_KEYS"
    chown -R "${USERNAME}:${USERNAME}" "$SSH_DIR"
    ok "SSH public key installed"
    audit "SSH_KEY_ADDED user=$USERNAME"
  fi

  # Force password change on first login
  passwd --expire "$USERNAME" &>/dev/null || true
  ok "Password set to expire — user must set password on first login"

  # Summary
  echo ""
  echo "────────────────────────────────────────────"
  echo -e "${GREEN}${BOLD}  ✔  User '${USERNAME}' provisioned successfully.${RESET}"
  info "Login:  ssh ${USERNAME}@$(hostname -I | awk '{print $1}')"
  [[ -n "$GROUPS" ]] && info "Groups: ${GROUPS}"
  echo ""
  audit "PROVISION_COMPLETE user=$USERNAME groups=$GROUPS"
fi

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: DELETE
# ──────────────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "delete" ]]; then
  echo -e "\n${BOLD}${BLUE}── DELETING USER: ${USERNAME} ───────────────${RESET}"

  if ! id "$USERNAME" &>/dev/null; then
    err "User '$USERNAME' does not exist"
  fi

  # Safety check — don't delete root or system users
  UID_CHECK=$(id -u "$USERNAME")
  (( UID_CHECK >= 1000 )) || err "Refusing to delete system user (UID < 1000): $USERNAME"

  # Kill active sessions
  SESSIONS=$(who | grep "^${USERNAME}" | wc -l)
  if (( SESSIONS > 0 )); then
    warn "User has ${SESSIONS} active session(s) — killing processes"
    pkill -u "$USERNAME" || true
    ok "Processes terminated"
    audit "KILL_SESSIONS user=$USERNAME sessions=$SESSIONS"
  fi

  if [[ "$PURGE" == true ]]; then
    userdel --remove "$USERNAME"
    ok "User deleted with home directory purged"
    audit "DELETE_PURGE user=$USERNAME uid=$UID_CHECK"
  else
    userdel "$USERNAME"
    ok "User deleted (home directory preserved at ${HOME_BASE}/${USERNAME})"
    warn "Home directory retained — remove manually if needed: rm -rf ${HOME_BASE}/${USERNAME}"
    audit "DELETE user=$USERNAME uid=$UID_CHECK home_retained=true"
  fi

  echo ""
  echo "────────────────────────────────────────────"
  echo -e "${GREEN}${BOLD}  ✔  User '${USERNAME}' removed successfully.${RESET}"
  echo ""
fi
