# 🔧 Bash Automation Toolkit

> Production-grade sysadmin scripts built from real infrastructure experience.
> Written to be used, not just read.

[![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black)](https://kernel.org)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

---

## 📋 Overview

A collection of battle-tested Bash scripts for Linux systems administration. These scripts handle real operational tasks — the kind that come up when you're managing production servers, not following tutorials.

Each script follows the same principles:
- **Argument-driven** — no hardcoded paths or values
- **Safe by default** — `set -euo pipefail` on every script
- **Auditable** — all actions logged with timestamps
- **Dry-run support** where destructive actions are involved
- **Clear output** — color-coded status, not silent failures

---

## 📁 Scripts

| Script | Description |
|---|---|
| [`health_check.sh`](scripts/health_check.sh) | CPU, memory, disk, load, and service monitoring |
| [`backup.sh`](scripts/backup.sh) | Compressed backups with timestamping and rotation |
| [`log_rotate.sh`](scripts/log_rotate.sh) | Log rotation by size and age with compression |
| [`user_provision.sh`](scripts/user_provision.sh) | Create/delete users, assign groups, deploy SSH keys |

---

## 🚀 Usage

### System Health Check

Checks CPU usage, memory, disk space, load average, network connectivity, and systemd service status.

```bash
# Basic check with default thresholds
sudo ./scripts/health_check.sh

# Custom thresholds and services
sudo ./scripts/health_check.sh \
  --services "nginx postgresql ssh" \
  --disk-warn 75 \
  --cpu-warn 80 \
  --mem-warn 85
```

**Output example:**
```
╔══════════════════════════════════════════╗
║         SYSTEM HEALTH CHECK              ║
║  Host: prod-web-01  │  2024-03-15 09:00  ║
╚══════════════════════════════════════════╝

── CPU ──────────────────────────────────
  ✔  CPU usage: 23%
  ✔  Load average (1m): 0.45

── Memory ───────────────────────────────
  ✔  Memory usage: 3.2GB / 8GB (40%)

── Disk Usage ───────────────────────────
  ✔  Disk /: 45GB / 100GB (45%)
  ⚠  Disk /data: 87GB / 100GB (87%) — ABOVE THRESHOLD

── Services ─────────────────────────────
  ✔  Service nginx: running
  ✖  Service postgresql: NOT running
```

Exit code `0` = healthy, `1` = one or more checks failed. Suitable for use in cron jobs or monitoring pipelines.

---

### Backup with Rotation

Creates timestamped compressed archives and automatically removes old backups beyond the retention limit.

```bash
# Backup a single directory, keep 7 days
sudo ./scripts/backup.sh \
  --source /var/www/html \
  --dest /mnt/backups \
  --name webserver \
  --retain 7

# Backup multiple sources
sudo ./scripts/backup.sh \
  --source /etc \
  --source /var/www \
  --dest /mnt/backups \
  --name full-system \
  --retain 14
```

Archives are named `{name}_{YYYY-MM-DD_HH-MM-SS}.tar.gz`. After creating the archive, integrity is verified with `tar -tf` before old backups are rotated out.

---

### Log Rotation

Rotates log files that exceed a size threshold, compresses rotated logs, and deletes logs older than the retention period.

```bash
# Rotate logs over 50MB, keep 30 days
sudo ./scripts/log_rotate.sh \
  --dir /var/log/myapp \
  --max-size 50M \
  --retain-days 30

# Dry run first to see what would happen
sudo ./scripts/log_rotate.sh \
  --dir /var/log/myapp \
  --dry-run
```

---

### User Provisioning

Create users with group membership and SSH key deployment, or safely remove them with full audit logging.

```bash
# Create a new user
sudo ./scripts/user_provision.sh \
  --action create \
  --user john.doe \
  --groups sudo,docker \
  --ssh-key "ssh-rsa AAAAB3Nza..."

# List all non-system users
sudo ./scripts/user_provision.sh --action list

# Delete a user (preserve home dir)
sudo ./scripts/user_provision.sh --action delete --user john.doe

# Delete and purge home directory
sudo ./scripts/user_provision.sh --action delete --user john.doe --purge
```

All actions are written to `/var/log/user_provision.log` with timestamp and invoking user for audit trail.

---

## ⚙️ Requirements

- Linux (tested on Ubuntu 22.04, Debian 12, RHEL 9)
- Bash 4.0+
- Standard GNU coreutils (`find`, `df`, `free`, `tar`, `gzip`)
- Root or sudo access for most scripts

```bash
# Make all scripts executable
chmod +x scripts/*.sh
```

---

## 🗂️ Project Structure

```
bash-toolkit/
├── scripts/
│   ├── health_check.sh      # System monitoring
│   ├── backup.sh            # Backup and rotation
│   ├── log_rotate.sh        # Log management
│   └── user_provision.sh    # User management
├── logs/                    # Default log output directory
└── README.md
```

---

## 💡 Design Decisions

**`set -euo pipefail`** on every script — exits immediately on error, treats unset variables as errors, and catches failures in pipelines. This is non-negotiable in production scripts.

**Arguments over hardcoding** — every path, threshold, and name is configurable via flags. Scripts that hardcode `/var/log/myapp` are scripts you can't reuse.

**Dry-run mode** on destructive scripts — you should always be able to see what a script will do before it does it.

**Audit logs** — every user creation, deletion, backup, and rotation is logged with a timestamp and the invoking user. When something goes wrong at 2am, you need to know what happened.

---

## 📄 License

MIT — use freely, modify as needed, no warranty implied.

---

*Part of my [DevOps portfolio](https://github.com/bijanmosavat) — building production-grade projects while transitioning from sysadmin to DevOps & Cloud Engineering.*
