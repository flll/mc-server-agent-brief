# Minecraft Server Setup — Agent Brief for AI Agents

**Language / 言語**: [English](../en/minecraft-server-agent-brief.md) | [日本語](../ja/minecraft-server-agent-brief.md)

> **Version**: 1.0  
> **Audience**: AI agents (Cursor, Claude Code, etc.)  
> **Base images**: [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) (Java), [itzg/docker-minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server) (Bedrock)

---

## Table of Contents

- [Chapter 0 — How to Use This Brief](#chapter-0--how-to-use-this-brief)
- [Chapter 1 — Pre-Deployment Discovery](#chapter-1--pre-deployment-discovery)
- [Chapter 2 — Host Environment Setup](#chapter-2--host-environment-setup)
- [Chapter 3 — Bind Mount Persistence + I/O Performance Optimization](#chapter-3--bind-mount-persistence--io-performance-optimization)
- [Chapter 4 — Standard Project Layout](#chapter-4--standard-project-layout)
- [Chapter 5 — Makefile Reference](#chapter-5--makefile-reference)
- [Chapter 6 — Architecture Decision Flow](#chapter-6--architecture-decision-flow)
- [Chapter 7 — Use-Case Procedures](#chapter-7--use-case-procedures)
- [Chapter 8 — Environment Variable Reference](#chapter-8--environment-variable-reference)
- [Chapter 9 — Agent Execution Checklist](#chapter-9--agent-execution-checklist)
- [Chapter 10 — Security](#chapter-10--security)
- [Chapter 11 — Troubleshooting](#chapter-11--troubleshooting)
- [Chapter 12 — Sample User Prompts](#chapter-12--sample-user-prompts)
- [Chapter 13 — Reference Links](#chapter-13--reference-links)

---

## Chapter 0 — How to Use This Brief

### 0.1 Audience and Purpose

This brief is a detailed guide for **AI agents** to build Docker-based Minecraft server environments from user requirements using a **consistent workflow**.

Following this document, the agent generates and configures:

- `docker-compose.yml` (bind mount only, `restart: unless-stopped`)
- `.env` / `.env.example` (secrets in `.env` only)
- `Makefile` (single entry point for daily operations)
- `scripts/backup.sh` / `restore.sh` (and Windows `.ps1` variants)
- `README.md` (handoff document for the user)

**Out of scope** (do not perform):

- Actually starting the server with `docker compose up` (unless the user explicitly requests it)
- Downloading modpacks (generate configuration only)
- Cloud IaC with Terraform, etc.
- systemd unit / cron timer setup
- Docker named volumes

### 0.2 Core Principles

| Principle | Description |
|------|------|
| **Reproducibility** | Lock configuration with compose + `.env.example` + README + Makefile |
| **Secret separation** | API keys and RCON passwords in `.env` only. Must be gitignored |
| **Bind mount only** | `./data:/data`, etc. Named / external volumes **forbidden** |
| **I/O optimization** | Placement, cache, and build context exclusion are mandatory |
| **No OS auto-start** | systemd unit / cron timer **forbidden** |
| **Docker restart enabled** | compose `restart: unless-stopped` (or `always`) **required** |
| **Manual operations** | Daily ops via `make up` / `make logs` / `make backup`, etc. Backups manual only |
| **Aikar flags always on** | `USE_AIKAR_FLAGS: "TRUE"` **required** on all Java servers |
| **Auto-generated MOTD** | Set `MOTD=§6${SERVER_NAME}§r` automatically after `SERVER_NAME` is confirmed |

### 0.3 Agent Workflow Overview

```
1. Confirm SERVER_NAME with the user (highest priority)
2. Auto-generate MOTD from SERVER_NAME
3. Detect host OS (Linux / Windows+WSL2)
4. Complete pre-deployment discovery (Chapter 1)
5. Select use case (UC)
6. Generate project files (Phase 2)
7. Validate syntax with make config
8. Hand off to the user (including README)
```

### 0.4 Success Criteria Checklist (10 items)

At completion, all of the following must be satisfied:

- [ ] **1.** `SERVER_NAME` conforms to slug rules and is reflected in the root directory name, `COMPOSE_PROJECT_NAME`, and backup filenames
- [ ] **2.** `MOTD=§6${SERVER_NAME}§r` is set in `.env` and compose
- [ ] **3.** All persistent data uses bind mounts (`./data:/data`) only; no named volumes exist
- [ ] **4.** compose has `restart: unless-stopped` (or `always`)
- [ ] **5.** Java servers have `USE_AIKAR_FLAGS: "TRUE"`
- [ ] **6.** MOTD is applied via `OVERRIDE_SERVER_PROPERTIES: "TRUE"`
- [ ] **7.** `.dockerignore` includes `data/`, `backups/`, and `.env`
- [ ] **8.** All Makefile targets work (verifiable with `make help`)
- [ ] **9.** On Windows, placement inside WSL2 is confirmed (no `/mnt/c`)
- [ ] **10.** No auto-start or auto-backup via systemd / cron / Task Scheduler

---

## Chapter 1 — Pre-Deployment Discovery

### 1.0 Work Order (Strict)

**`SERVER_NAME` must be confirmed with the user before any other work.** Do not proceed if unanswered.

Order after confirmation:

1. Confirm and validate `SERVER_NAME` with the user
2. Auto-set `MOTD=§6${SERVER_NAME}§r` in `.env` (no separate question needed)
3. Create the project under `~/servers/${SERVER_NAME}/` (Linux) or inside WSL home
4. compose / Makefile / backup scripts all reference `SERVER_NAME`
5. compose must include `USE_AIKAR_FLAGS: "TRUE"` and `MOTD`

### 1.1 Discovery Items

| # | Item | Options | Default |
|---|------|--------|-----------|
| **0** | **Server name (`SERVER_NAME`)** | Lowercase letters, digits, hyphens (slug) | **Always ask. Stop if unanswered** |
| 1 | Host OS | Linux / Windows | Detect from user environment |
| 2 | Edition | Java / Bedrock / Java+Bedrock | Java |
| 3 | Server type | Vanilla / Paper / Purpur / Fabric / Forge / NeoForge | Paper |
| 4 | Content | Vanilla / plugins / modpack / custom MODs | Plugins |
| 5 | Modpack source | CurseForge / Modrinth / FTB / local zip | — |
| 6 | MC version | e.g. `1.21.1` | Latest stable |
| 7 | Concurrent players | Number | 10 |
| 8 | Allocated RAM | GB | players × 0.5–1 GB (×2 with MODs) |
| 9 | Exposure | LAN / internet / local only | LAN |
| 10 | Extras | RCON / whitelist / backup / proxy / Dynmap | RCON + backup |

### 1.2 Server Name (`SERVER_NAME`) Rules

During discovery, present the following to the user:

> "Choose a server name. It will be used for the project folder name, backup filenames, and the Docker Compose project name."

| Rule | OK examples | NG examples |
|--------|----------|----------|
| Lowercase letters, digits, hyphens only | `my-paper-server`, `atm10` | `My Server` (spaces) |
| Must start with a letter | `survival-01` | `01-survival` (starts with digit) |
| 3–32 characters | `lobby` | `a` (too short) |
| Avoid reserved words | — | `data`, `backups`, `config` |

**Validation regex**:

```regex
^[a-z][a-z0-9-]{2,31}$
```

**Uses of `SERVER_NAME`**:

| Use | Format | Example (`SERVER_NAME=survival-2024`) |
|------|------|-----------------------------------|
| Root directory name | `${SERVER_NAME}/` | `~/servers/survival-2024/` |
| Backup filename | `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz` | `survival-2024_data_20260526_143000.tar.gz` |
| Compose project name | `COMPOSE_PROJECT_NAME=${SERVER_NAME}` | Reflected in container name prefix |
| `.env` variable | `SERVER_NAME=survival-2024` | Referenced by all scripts |
| **MOTD (required)** | Auto-generated from `SERVER_NAME` | `§6survival-2024§r` |

### 1.3 MOTD — Simple Display (Required, Linked to `SERVER_NAME`)

**Policy**: The **server name must be recognizable** in the server list. Do not ask about MOTD separately — **auto-generate from `SERVER_NAME`**.

**Requirements**:

- **`MOTD` must be set** in compose / `.env` (never omit)
- **Single line, simple**: display the server name only (no multi-line or excessive decoration)
- **Once `SERVER_NAME` is set, MOTD is set** — no extra questions

**Default generation rule**:

```
MOTD = "§6" + SERVER_NAME + "§r"
```

Example: `SERVER_NAME=survival-2024` → `MOTD=§6survival-2024§r`

**compose template**:

```yaml
environment:
  OVERRIDE_SERVER_PROPERTIES: "TRUE"
  MOTD: "§6${SERVER_NAME}§r"
```

**Explicit setting in `.env`**:

```dotenv
SERVER_NAME=survival-2024
MOTD=§6survival-2024§r
```

**Optional customization** (only when the user explicitly requests it):

- Override MOTD only when a different display name is desired (e.g. `§6My Survival Server§r`)
- Otherwise use the `SERVER_NAME`-based default

### 1.4 `USE_AIKAR_FLAGS` — Always Enabled (Required)

- Set `USE_AIKAR_FLAGS: "TRUE"` on **all Java server configurations** (never omit or set `FALSE`)
- Fixed requirement for JVM performance; non-negotiable
- Do not apply to Bedrock-only servers (UC-F)

### 1.5 RAM Estimation Table

| Configuration | Minimum RAM | Recommended RAM |
|------|----------|----------|
| Vanilla, 1–5 players | 2GB | 4GB |
| Paper + plugins, 10 players | 4GB | 6GB |
| Light MODs (Fabric) | 4GB | 6GB |
| Medium modpack | 8GB | 12GB |
| Large modpack (ATM, etc.) | 10GB | 16GB+ |

**Docker Desktop / WSL2**: Do not set `MEMORY` above host-assigned RAM. Adjust the memory limit in `.wslconfig` (see Chapter 2).

---

## Chapter 2 — Host Environment Setup

### 2.1 Common Prerequisites

| Item | Requirement |
|------|------|
| Docker Engine | 24+ |
| Docker Compose | v2 (`docker compose` subcommand) |
| Java port | 25565/TCP |
| Bedrock port | 19132/UDP |
| RCON port | 25575/TCP (when enabled) |
| Disk | Minimum 10GB. Modpacks 20GB+ |
| OS auto-start | **Not needed** — do not configure systemd / cron timer |
| Container auto-restart | Handled by compose `restart:` policy |

### 2.2 Linux (Ubuntu / Debian Example)

#### 2.2.1 Docker Installation

```bash
# 1. Official convenience script (recommended)
curl -fsSL https://get.docker.com | sh

# 2. Add user to docker group
sudo usermod -aG docker $USER

# 3. After re-login, verify version
docker --version && docker compose version
```

#### 2.2.2 Firewall (when using ufw)

```bash
sudo ufw allow 25565/tcp comment 'Minecraft Java'
sudo ufw allow 19132/udp comment 'Minecraft Bedrock'
sudo ufw allow 25575/tcp comment 'Minecraft RCON'
```

#### 2.2.3 Project Placement

```bash
mkdir -p ~/servers/${SERVER_NAME}
cd ~/servers/${SERVER_NAME}
```

**Reason**: ext4/xfs under the home directory gives the best bind mount I/O performance.

#### 2.2.4 UID / GID Configuration

```bash
id -u   # → set as UID in .env
id -g   # → set as GID in .env
```

Pass these via compose `environment` so container file ownership matches the host user.

#### 2.2.5 Prohibited Actions

- Creating systemd units such as `/etc/systemd/system/minecraft.service` **forbidden**
- Scheduled backups via cron **forbidden**
- Configurations that invoke `docker compose up` from systemd **forbidden**

### 2.3 Windows — Two Patterns

#### Pattern A (Recommended): WSL2 + Docker Desktop

1. Enable WSL2:

```powershell
wsl --install
```

2. Install Docker Desktop → enable the target distribution under **Settings → Resources → WSL Integration**

3. **Place the project inside the WSL filesystem**:

```bash
# Inside WSL (Ubuntu) terminal
mkdir -p ~/servers/${SERVER_NAME}
cd ~/servers/${SERVER_NAME}
```

**Reason**: bind mounts to `C:\Users\...` are extremely slow over 9p/DrvFs and file watching is unreliable.

4. Run `make` commands from a WSL terminal

5. When invoking WSL `make` from Windows:

```powershell
wsl -d Ubuntu --cd ~/servers/survival-2024 make up
```

#### Pattern B: Docker Desktop + Windows Native Path — Not Recommended

- bind mount to `C:\Users\...` is **treated as nearly forbidden**
- If unavoidable, document in README: "chunk saves and MOD downloads may be ~10× slower"
- Run Makefile inside WSL

**Velocity mount difference** (Windows native only):

```yaml
# Linux / WSL
- ./velocity.toml:/config

# Windows native (when needed)
- ./velocity.toml:/config/velocity.toml
```

#### 2.3.1 Windows Firewall (PowerShell — Administrator)

```powershell
New-NetFirewallRule -DisplayName "Minecraft Java" -Direction Inbound -Protocol TCP -LocalPort 25565 -Action Allow
New-NetFirewallRule -DisplayName "Minecraft Bedrock" -Direction Inbound -Protocol UDP -LocalPort 19132 -Action Allow
New-NetFirewallRule -DisplayName "Minecraft RCON" -Direction Inbound -Protocol TCP -LocalPort 25575 -Action Allow
```

#### 2.3.2 WSL2 Memory Settings

`%UserProfile%\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
# localhostForwarding=true  # enabled by default
```

After changes:

```powershell
wsl --shutdown
```

### 2.4 Cross-OS Branching Rules for Agents

```
IF host OS == Windows:
  IF Docker Desktop + WSL2 available:
    Recommended: create project inside WSL2 (~/servers/${SERVER_NAME}/)
    Scripts: .sh (bash) primary, .ps1 auxiliary
    make check-path rejects /mnt/ paths
  ELSE:
    Generate compose on Windows native path (not recommended, warning required)
    Scripts: .ps1 primary
ELSE Linux:
  Scripts: .sh primary
  Placement: ~/servers/${SERVER_NAME}/
  Backup: make backup (manual only)
```

### 2.5 Free Port and Disk Checks

**Linux / WSL**:

```bash
ss -tlnp | grep -E '25565|25575'
ss -ulnp | grep 19132
df -h .
```

**Windows (PowerShell)**:

```powershell
netstat -ano | findstr 25565
netstat -ano | findstr 25575
Get-PSDrive C | Select-Object Used,Free
```

---

## Chapter 3 — Bind Mount Persistence + I/O Performance Optimization

> **This chapter is the core of the brief.** Agents must strictly follow these rules.

### 3.1 Persistence Policy — Bind Mount Only (Strict)

**Required**: All persistent data must use bind mounts to host directories.

```yaml
services:
  mc:
    volumes:
      - ./data:/data
      - ./config/plugins:/plugins:ro   # optional: read-only plugin injection
      - ./backups:/backups             # optional: backup output directory
```

**Forbidden** (fix the configuration on violation):

| Prohibited | Reason |
|----------|------|
| Top-level named volume definitions in `volumes:` (e.g. `mc-data:`) | Opaque data location, hard to migrate |
| Mounts like `mc-data:/data` | Uses named volume |
| `docker compose down -v` | Named volume deletion risk (avoid the habit even with bind mounts) |
| Project placement on Windows `C:\...` / `/mnt/c/...` | Extremely slow I/O over 9p |
| Excessive split mounts like `./config:/data/config` | More mount points hurt performance |

### 3.2 I/O Cache and Performance Optimization

| Measure | Linux | Windows (WSL2) | Reason |
|------|-------|----------------|------|
| Project placement | Local ext4/xfs | **`~/servers/${SERVER_NAME}` (inside WSL ext4)** | Native FS = full cache efficiency |
| Forbidden paths | — | `/mnt/c/Users/...` | Random I/O over 9p is very slow |
| Docker Desktop | — | Settings → WSL2 engine enabled | ext4 bind inside Linux VM |
| `.dockerignore` | `data/`, `backups/`, `*.log` | Same | Exclude large data from build context |
| Image pull | `pull_policy: daily` or pin version | Same | Avoid unnecessary re-pulls |
| MC/JAR cache | server.jar etc. kept under `data/` | Same | Faster startup from second run onward |
| Initial MOD download | `CF_PARALLEL_DOWNLOADS: "8"` (when RAM allows) | Same | Parallel DL shortens first run only |
| JVM | `USE_AIKAR_FLAGS: "TRUE"` | Same | **Always required** |
| Reduce sync load | Single `./data` mount is default | Same | Split mounts not recommended |

### 3.3 Placement Check (Required for Agents)

Run inside WSL — **FAIL** if path contains `/mnt/c`:

```bash
make check-path
# or
pwd | grep -q '/mnt/' && echo "ERROR: Slow path detected. Move to WSL home." || echo "OK"
```

Because `make up` depends on `check-path`, a slow path errors before startup.

### 3.4 Standard compose Template

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      USE_AIKAR_FLAGS: "TRUE"          # always required
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"       # auto from SERVER_NAME; single line
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
      TYPE: "${TYPE:-PAPER}"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      ENABLE_RCON: "${ENABLE_RCON:-TRUE}"
      RCON_PASSWORD: "${RCON_PASSWORD}"
    volumes:
      - ./data:/data
    restart: unless-stopped   # Docker auto-restarts after crash/OOM
```

### 3.5 Docker `restart:` Policy

**Do not use systemd, but always set compose `restart:`.**

| Policy | Behavior | Recommendation |
|----------|------|------|
| `unless-stopped` | Auto-recover after crash/OOM/Docker daemon restart. No restart after `make down` | **Default** |
| `always` | Also recovers after manual stop when Docker daemon restarts | When always-on is top priority |
| `on-failure` | Restart only on non-zero exit | During debugging |
| (unspecified) | No restart after stop | **Forbidden** |

**Behavior summary**:

| Event | Behavior with `unless-stopped` |
|----------|-------------------------|
| Process crash / OOM | Docker auto-restarts |
| `make down` (intentional stop) | Stays stopped (no restart) |
| Host OS reboot | Auto-recovers when Docker starts (no systemd unit needed) |
| `make restart` | Manual down + up |

**Clarification vs. prohibitions**:

| Method | Allowed |
|------|------|
| compose `restart: unless-stopped` | OK |
| compose `restart: always` | OK (as needed) |
| systemd unit running `docker compose up` | **NG** |
| Periodic start via cron / systemd timer | **NG** |
| Periodic backup via cron / Task Scheduler | **NG** |

### 3.6 Persistence Target — Entire `./data` Directory

**Backup target is the entire `./data`** (not just the world — includes mods / plugins / config / JAR cache, etc.).

| Container path | Contents | Backup |
|---------------|------|-------------|
| Entire `/data/` | World, MODs, plugins, config, JAR, etc. | **Bulk (tar.gz)** |
| `/data/world` | World data | Included above |
| `/data/mods` | MODs | Included above |
| `/data/plugins` | Plugins | Included above |
| `/data/config` | Various settings | Included above |

### 3.7 Permissions (Linux / WSL)

```yaml
environment:
  UID: "1000"   # value from id -u
  GID: "1000"   # value from id -g
```

If `data/` becomes root-owned:

```bash
sudo chown -R $(id -u):$(id -g) ./data
```

### 3.8 Backup Procedure — Full Server Data (`make backup`)

**Policy**: Archive the **`./data` directory whole**. No world-only partial backups.

**Filename format**: `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz`

**Linux / WSL** — `scripts/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source .env
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p backups
docker compose exec -T mc rcon-cli save-all flush 2>/dev/null || true
docker compose stop mc
tar -czf "backups/${SERVER_NAME}_data_${TS}.tar.gz" -C . data
docker compose start mc
```

**Windows PowerShell** — `scripts/backup.ps1`:

```powershell
# Recommended inside WSL. On native Windows, use tar command
tar -czf "backups\${env:SERVER_NAME}_data_$ts.tar.gz" -C . data
```

**Restore**:

```bash
RESTORE=backups/survival-2024_data_20260526_143000.tar.gz make restore
make up
```

Internal steps:

1. `docker compose down`
2. Move existing `data/` to `data.old.<timestamp>/`
3. Restore `./data` with `tar -xzf "$RESTORE"`
4. User starts with `make up`

- Backups are **manual only** (`make backup`)
- Do **not** include cron / Task Scheduler examples

### 3.9 Data Safety During Updates and Image Pulls

```bash
make update    # internally: pull + up -d. ./data remains on bind mount
```

- `docker compose down -v` is **absolutely forbidden**
- Do not add volume deletion targets to the Makefile

---

## Chapter 4 — Standard Project Layout

**Root directory name = `SERVER_NAME`** (do not use fixed name `minecraft-server/`).

```
${SERVER_NAME}/                    # e.g. survival-2024/
├── Makefile
├── docker-compose.yml
├── docker-compose.override.yml    # optional (local overrides)
├── .dockerignore
├── .env.example
├── .env                           # gitignore
├── .gitignore
├── README.md                      # optional: English README (default)
├── README.ja.md                   # optional: Japanese README
├── AGENTS.md                      # optional: agent instructions (English)
├── AGENTS.ja.md                   # optional: Japanese agent instructions
├── docs/
│   ├── en/
│   │   └── minecraft-server-agent-brief.md
│   └── ja/
│       └── minecraft-server-agent-brief.md
├── config/
│   └── plugins/                   # optional: local plugin injection
├── data/                          # bind mount target (gitignore)
├── backups/                       # ${SERVER_NAME}_data_*.tar.gz (gitignore)
└── scripts/
    ├── backup.sh
    ├── backup.ps1
    ├── restore.sh
    └── restore.ps1
```

### 4.1 `.env.example` Header Fields

```dotenv
SERVER_NAME=survival-2024
MOTD=§6survival-2024§r
COMPOSE_PROJECT_NAME=survival-2024
```

### 4.2 Required `.dockerignore` Entries

```
data/
backups/
.git/
*.log
.env
```

### 4.3 Required `.gitignore` Entries

```
.env
data/
backups/
*.log
forwarding.secret
*.old.*
```

### 4.4 Required README.md Sections

1. Server name (`SERVER_NAME`) and connection instructions
2. Required RAM / disk / MC version
3. First-time setup (`make init` → edit `.env` → `make up`)
4. Daily operations (`make help` listing)
5. OS-specific notes (WSL2 recommended, etc.)
6. Backup / restore procedure
7. Update procedure (`make update`)
8. Troubleshooting

---

## Chapter 5 — Makefile Reference

Use the Makefile as the **single entry point** for daily operations.

### 5.1 Target List

| Target | Action | Notes |
|-----------|------|------|
| `help` | Show target list | Default |
| `init` | Generate `.env`, **confirm SERVER_NAME**, create directories | First run only |
| `config` | `docker compose config` syntax validation | |
| `up` | `docker compose up -d` | Runs `check-path` |
| `down` | `docker compose down` (**no -v**) | |
| `restart` | down + up | |
| `logs` | `docker compose logs -f` | |
| `status` | `docker compose ps` | |
| `pull` | `docker compose pull` | |
| `update` | pull + up -d | |
| `backup` | RCON save → stop → tar entire `./data` → start | `scripts/backup.sh` |
| `restore` | Restore entire `./data` with `RESTORE=...` | `scripts/restore.sh` |
| `shell` | bash inside container | |
| `rcon` | `make rcon CMD="list"` | Run RCON command |
| `check-path` | Detect `/mnt/` placement on WSL | For Windows |

### 5.2 Reference Implementation

See the project root `Makefile`. Key sections:

```makefile
-include $(ENV_FILE)
export $(shell sed -n 's/=.*//p' $(ENV_FILE) 2>/dev/null)

init:
	@test -f .env || cp .env.example .env
	@grep -q '^SERVER_NAME=.' .env || (echo "ERROR: Set SERVER_NAME in .env"; exit 1)
	@mkdir -p data backups config/plugins
	@$(MAKE) check-path

backup:
	@bash scripts/backup.sh

restore:
	@test -n "$(RESTORE)" || (echo "Usage: RESTORE=backups/... make restore"; exit 1)
	@bash scripts/restore.sh "$(RESTORE)"
```

### 5.3 Running Makefile on Windows

| Method | Command |
|------|----------|
| **Recommended: inside WSL** | `cd ~/servers/my-server && make up` |
| From Windows terminal | `wsl -d Ubuntu --cd ~/servers/my-server make up` |
| make not installed | `sudo apt install make` (WSL) |
| When make unavailable | Document direct `docker compose` table in README |

**Windows native only**: `scripts/*.ps1` are auxiliary. **Primary path is WSL + make**.

### 5.4 Direct docker compose Alternatives

| make command | Direct docker compose |
|--------------|----------------------|
| `make up` | `docker compose up -d` |
| `make down` | `docker compose down` |
| `make logs` | `docker compose logs -f` |
| `make status` | `docker compose ps` |
| `make pull` | `docker compose pull` |
| `make shell` | `docker compose exec mc bash` |
| `make rcon CMD="list"` | `docker compose exec mc rcon-cli list` |

---

## Chapter 6 — Architecture Decision Flow

```
Requirements discovery
    │
    ▼
Confirm SERVER_NAME with user (highest priority)
    │
    ▼
Auto-set MOTD = §6${SERVER_NAME}§r
    │
    ▼
OS check ── Windows ── WSL2 available? ── Yes ── Place inside WSL
    │                    └── No ── Native (warning)
    └── Linux ── ~/servers/${SERVER_NAME}/
    │
    ▼
Edition ── Java ── Type ── Plugins → Paper (UC-A)
    │                    ├── Modpack → CF/MR (UC-B/C)
    │                    ├── Custom MODs → Fabric/Forge (UC-D)
    │                    └── Multiple servers → Velocity (UC-E)
    ├── Bedrock → UC-F
    └── Java+Bedrock → Geyser (UC-G)
```

**Image selection**:

| Requirement | Image |
|------|----------|
| Java (general purpose) | `itzg/minecraft-server` |
| Bedrock | `itzg/minecraft-bedrock-server` |
| Velocity proxy | `itzg/mc-proxy` |

---

## Chapter 7 — Use-Case Procedures

Each UC follows the same format:

1. Overview and when to use
2. Prerequisites
3. Complete `docker-compose.yml` example
4. Additional `.env.example` fields
5. First startup procedure (Linux / Windows branches)
6. Startup verification
7. Client connection steps
8. Common failures and fixes
9. Reference links

---

### UC-A: Paper Plugin Server

#### Overview

The most common setup. Java server using Bukkit/Spigot-compatible plugins.

#### Prerequisites

- RAM: 4GB+ (for ~10 players)
- Disk: 10GB+
- Port: 25565/TCP

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME:-survival-2024}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
      - "${RCON_PORT:-25575}:25575"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      MAX_PLAYERS: "${MAX_PLAYERS:-10}"
      ENABLE_RCON: "${ENABLE_RCON:-TRUE}"
      RCON_PASSWORD: "${RCON_PASSWORD}"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
      ONLINE_MODE: "${ONLINE_MODE:-TRUE}"
      DIFFICULTY: "${DIFFICULTY:-normal}"
      WHITE_LIST: "${WHITE_LIST:-FALSE}"
      # Plugin URL list (comma-separated)
      PLUGINS: |
        https://github.com/EssentialsX/Essentials/releases/latest/download/EssentialsX-2.21.0.jar
        https://download.luckperms.net/1565/bukkit/loader/LuckPerms-Bukkit-5.4.145.jar
    volumes:
      - ./data:/data
      - ./config/plugins:/plugins:ro
    restart: unless-stopped
```

#### Additional `.env.example` Fields

```dotenv
TYPE=PAPER
VERSION=1.21.1
MEMORY=4G
MAX_PLAYERS=10
ENABLE_RCON=TRUE
RCON_PASSWORD=your-secure-password-here
```

#### First Startup

**Linux / WSL**:

```bash
cd ~/servers/${SERVER_NAME}
cp .env.example .env
# Edit .env (SERVER_NAME, RCON_PASSWORD, etc.)
make init
make config
make up
make logs
```

**Windows (WSL2 recommended)**:

```powershell
wsl -d Ubuntu
cd ~/servers/${SERVER_NAME}
make init && make up
```

#### Startup Verification

Success when the log shows:

```
[Server thread/INFO]: Done (XX.Xs)! For help, type "help"
```

MOTD check:

```bash
make rcon CMD="list"
```

#### Client Connection

- Address: `<hostIP>:25565`
- LAN: IP on the same network
- Internet: router port forwarding required

#### Common Failures

| Symptom | Cause | Fix |
|------|------|------|
| Plugins not loaded | Version mismatch | Specify plugin versions matching MC version |
| Permission denied | UID/GID mismatch | `chown -R $(id -u):$(id -g) data` |
| MOTD not applied | OVERRIDE not set | `OVERRIDE_SERVER_PROPERTIES: "TRUE"` |

#### Reference Links

- [itzg/docker-minecraft-server — Paper](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/)
- [Paper official](https://papermc.io/)

---

### UC-B: CurseForge Modpack

#### Overview

Configuration that automatically downloads and builds a modpack from CurseForge.

#### Prerequisites

- RAM: **8GB+** (12GB+ for large packs)
- Disk: **20GB+**
- `CF_API_KEY` required

#### Obtaining CF_API_KEY

1. Visit https://console.curseforge.com/
2. Create account / sign in
3. Generate API key
4. Set in `.env` as `CF_API_KEY=...` (never commit to git)

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "AUTO_CURSEFORGE"
      CF_API_KEY: "${CF_API_KEY}"
      CF_PAGE_URL: "${CF_PAGE_URL}"
      CF_PARALLEL_DOWNLOADS: "8"
      MEMORY: "${MEMORY:-8G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### Additional `.env.example` Fields

```dotenv
TYPE=AUTO_CURSEFORGE
CF_API_KEY=
CF_PAGE_URL=https://www.curseforge.com/minecraft/modpacks/all-the-mods-10
MEMORY=12G
```

#### Important: Do Not Choose Server-Only zip

CurseForge has "client" and "server" zips. Point `CF_PAGE_URL` at the **client** pack page URL. Server-only zips may have incomplete MOD layout.

#### First Startup

First run involves **10–30 minutes** of downloads. Example log:

```
[mc-image-helper] Downloading mod ...
[mc-image-helper] Mod download complete
```

#### Common Failures

| Symptom | Fix |
|------|------|
| 401 Unauthorized | Verify `CF_API_KEY` |
| OOM Killed | Increase `MEMORY`, adjust `.wslconfig` |
| Specific MOD conflict | `CF_EXCLUDE_MODS` / `CF_FORCE_INCLUDE_MODS` |

---

### UC-C: Modrinth Modpack

#### Overview

Introduce a Modrinth-hosted modpack by URL.

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "MODRINTH"
      MODRINTH_MODPACK: "${MODRINTH_MODPACK}"
      MODRINTH_LOADER: "${MODRINTH_LOADER:-fabric}"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-6G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    ports:
      - "${MC_PORT:-25565}:25565"
    restart: unless-stopped
```

#### .env.example

```dotenv
MODRINTH_MODPACK=https://modrinth.com/modpack/fabulously-optimized
MODRINTH_LOADER=fabric
VERSION=LATEST
MEMORY=6G
```

---

### UC-D: Custom MOD List (Fabric / Forge / NeoForge)

#### Overview

Specify MODs individually via a list of Modrinth project slugs.

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "${TYPE:-FABRIC}"
      VERSION: "${VERSION:-LATEST}"
      MODRINTH_PROJECTS: |
        fabric-api
        lithium
        sodium?
      VERSION_FROM_MODRINTH_PROJECTS: "TRUE"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    ports:
      - "${MC_PORT:-25565}:25565"
    restart: unless-stopped
```

**`?` suffix**: Optional MOD (no error if not found)

**TYPE values**: `FABRIC` / `FORGE` / `NEOFORGE`

---

### UC-E: Velocity Proxy + Multiple Paper Servers

#### Overview

Combine multiple backends (lobby + survival, etc.) with Velocity.

#### Prerequisites

- RAM: 2GB+ per server + 512MB for proxy
- Generate `forwarding.secret` and configure Paper side

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  velocity:
    image: itzg/mc-proxy:latest
    ports:
      - "25565:25565"
    environment:
      TYPE: "VELOCITY"
      MEMORY: "512M"
    volumes:
      - ./velocity.toml:/config
      - ./forwarding.secret:/forwarding.secret:ro
    restart: unless-stopped
    depends_on:
      - lobby
      - survival

  lobby:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "2G"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}-lobby§r"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data/lobby:/data
    restart: unless-stopped

  survival:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}-survival§r"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data/survival:/data
    restart: unless-stopped
```

#### forwarding.secret Setup (Step by Step)

1. Generate secret:

```bash
openssl rand -hex 16 > forwarding.secret
chmod 600 forwarding.secret
```

2. Configure in `velocity.toml` (`player-info-forwarding-mode = "modern"`)

3. On each Paper server, `config/paper-global.yml`:

```yaml
proxies:
  velocity:
    enabled: true
    online-mode: true
    secret: "<contents of forwarding.secret>"
```

4. **Use Docker internal DNS**: backend addresses must be `lobby:25565` (`127.0.0.1` forbidden)

#### Windows Mount Difference

```yaml
# Linux / WSL
- ./velocity.toml:/config

# Windows native
- ./velocity.toml:/config/velocity.toml
```

#### Reference Links

- [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy)
- [heyvaldemar/minecraft-server-proxy-docker-compose](https://github.com/heyvaldemar/minecraft-server-proxy-docker-compose)

---

### UC-F: Bedrock Dedicated Server

#### Overview

Dedicated server for Minecraft Bedrock Edition (PE / Windows 10 / Xbox, etc.).

#### Prerequisites

- Port: **19132/UDP** (not TCP)
- Image: `itzg/minecraft-bedrock-server`

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  bedrock:
    image: itzg/minecraft-bedrock-server:latest
    pull_policy: daily
    ports:
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      SERVER_NAME: "${SERVER_NAME}"
      GAMEMODE: "survival"
      DIFFICULTY: "normal"
      MAX_PLAYERS: "${MAX_PLAYERS:-10}"
      ALLOW_CHEATS: "false"
      LEVEL_NAME: "Bedrock level"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

**Note**: Bedrock does not need `USE_AIKAR_FLAGS` (Java only).

#### Firewall

```bash
# Linux
sudo ufw allow 19132/udp
```

```powershell
# Windows
New-NetFirewallRule -DisplayName "Minecraft Bedrock" -Direction Inbound -Protocol UDP -LocalPort 19132 -Action Allow
```

#### Client Connection

- Bedrock client → "Servers" → `<IP>:19132`

---

### UC-G: Java + Bedrock Crossplay (Geyser + Floodgate)

#### Overview

Add Geyser / Floodgate plugins to a Java server so Bedrock clients can join.

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "${MC_PORT:-25565}:25565"
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### Ports

- 25565/TCP — Java clients
- 19132/UDP — Bedrock clients

---

### UC-H: Plugin Development Environment

#### Overview

Server for Paper API plugin development. Test via hot deploy or restart.

#### Prerequisites

- Local dev machine (WSL2 recommended)
- Gradle project (separate repository)

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "2G"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}-dev§r"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
      - ./plugins-dev:/data/plugins
    restart: unless-stopped
```

#### Development Flow

1. Gradle `build` → generate `.jar`
2. Copy to `plugins-dev/`
3. `make restart` or RCON `reload confirm` (not recommended — prefer restart)

#### Reference Links

- [KevinTCoughlin/minecraft-server](https://github.com/KevinTCoughlin/minecraft-server)

---

### UC-I: GitOps / VPS Production (Advanced)

#### Overview

GitOps deployment on a VPS. Auto-update via webhook.

#### Policy

- **Overview only** in this brief
- See [blueprint-minecraft-server-gitops](https://github.com/timo-reymann/blueprint-minecraft-server-gitops) for details
- Maintain bind mount / `restart: unless-stopped` / `USE_AIKAR_FLAGS` principles
- systemd compose startup still **forbidden** — rely on Docker restart policy

#### Minimum Components

- compose + `.env.example` in Git repository
- Deploy webhook → `git pull && make update`
- Manual backup (`make backup`) before deploy

---

### UC-J: Vanilla Server (Minimal)

#### Overview

Minimal Vanilla Java server without plugins or MODs. For verification and learning.

#### Prerequisites

- RAM: 2GB+
- Disk: 5GB+

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "VANILLA"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-2G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      MAX_PLAYERS: "${MAX_PLAYERS:-5}"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### .env.example

```dotenv
SERVER_NAME=vanilla-test
MOTD=§6vanilla-test§r
TYPE=VANILLA
VERSION=1.21.1
MEMORY=2G
MAX_PLAYERS=5
```

#### Startup Verification

```
[Server thread/INFO]: Done (XX.Xs)! For help, type "help"
```

---

## Chapter 8 — Environment Variable Reference

### 8.1 Common Project Variables

| Variable | Required | Description | Example |
|------|------|------|-----|
| **`SERVER_NAME`** | **Yes** | Set during discovery. Root dir, backup name, Compose name | `survival-2024` |
| **`MOTD`** | **Yes** | Server list MOTD. Auto-generated one line from `SERVER_NAME` | `§6survival-2024§r` |
| `COMPOSE_PROJECT_NAME` | Yes | Docker Compose project name | `survival-2024` |
| `MC_PORT` | No | Java port | `25565` |
| `RCON_PORT` | No | RCON port | `25575` |

### 8.2 Key itzg/minecraft-server Variables

| Variable | Required | Description | Example |
|------|------|------|-----|
| `EULA` | Yes | Mojang EULA acceptance | `TRUE` |
| `TYPE` | No | Server type | `PAPER`, `VANILLA`, `FABRIC`, `AUTO_CURSEFORGE` |
| `VERSION` | No | MC version | `1.21.1`, `LATEST` |
| `MEMORY` | No | JVM heap | `4G` |
| **`USE_AIKAR_FLAGS`** | **Yes** | JVM performance tuning. **Always `TRUE`** | `TRUE` |
| `OVERRIDE_SERVER_PROPERTIES` | Yes | Apply env vars like MOTD | `TRUE` |
| `MAX_PLAYERS` | No | Max players | `10` |
| `ENABLE_RCON` | No | Enable RCON | `TRUE` |
| `RCON_PASSWORD` | When RCON | Password | See `.env` |
| `UID` / `GID` | Recommended on Linux | File ownership | `1000` |
| `ONLINE_MODE` | No | Premium authentication | `TRUE` |
| `DIFFICULTY` | No | Difficulty | `normal` |
| `WHITE_LIST` | No | Whitelist | `TRUE` |
| `VIEW_DISTANCE` | No | View distance | `10` |
| `SPAWN_PROTECTION` | No | Spawn protection radius | `16` |

### 8.3 Modpack-Related Variables

| Variable | Required | Description | Example |
|------|------|------|-----|
| `CF_API_KEY` | For CF | CurseForge API key | `.env` |
| `CF_PAGE_URL` | For CF | Pack URL | `https://www.curseforge.com/...` |
| `CF_FILE_ID` | For CF | Specific file ID (pin version) | `1234567` |
| `CF_PARALLEL_DOWNLOADS` | No | Parallel download count | `8` |
| `CF_EXCLUDE_MODS` | No | Excluded MOD slugs | `sodium` |
| `CF_FORCE_INCLUDE_MODS` | No | Force-included MODs | `fabric-api` |
| `MODRINTH_MODPACK` | For MR | Modrinth pack URL | `https://modrinth.com/modpack/...` |
| `MODRINTH_LOADER` | For MR | Loader | `fabric`, `forge`, `quilt` |
| `MODRINTH_PROJECTS` | Custom | MOD slug list | `fabric-api\nlithium` |
| `VERSION_FROM_MODRINTH_PROJECTS` | No | Auto-determine MC version | `TRUE` |

### 8.4 Plugin-Related Variables

| Variable | Description | Example |
|------|------|-----|
| `PLUGINS` | Plugin URL list (newline-separated) | GitHub releases URL |
| `MODS` | Fabric/Forge MOD URL list | Modrinth CDN URL |
| `SPIGET_RESOURCES` | Spiget resource ID | `34315` |

### 8.5 World and Game Settings

| Variable | Description | Example |
|------|------|-----|
| `LEVEL` | World name | `world` |
| `MODE` | Game mode | `survival`, `creative` |
| `PVP` | PVP enabled | `TRUE` |
| `ALLOW_NETHER` | Nether enabled | `TRUE` |
| `ANNOUNCE_PLAYER_ACHIEVEMENTS` | Achievement announcements | `TRUE` |
| `ENABLE_COMMAND_BLOCK` | Command blocks | `FALSE` |
| `SNOOPER_ENABLED` | Snooper | `FALSE` |
| `GENERATE_STRUCTURES` | Structure generation | `TRUE` |
| `HARDCORE` | Hardcore mode | `FALSE` |

---

## Chapter 9 — Agent Execution Checklist

### Phase 0: Environment Verification

- [ ] **Confirm and validate `SERVER_NAME` with user (highest priority)**
- [ ] **After `SERVER_NAME` is set, auto-set `MOTD=§6${SERVER_NAME}§r`**
- [ ] Create project at `~/servers/${SERVER_NAME}/`
- [ ] Verify `docker --version` / `docker compose version`
- [ ] Check free ports (Linux: `ss -tlnp`, Windows: `netstat -an`)
- [ ] Check free disk space
- [ ] On Windows: decide project placement (WSL recommended)
- [ ] Reject `/mnt/` paths with `make check-path`

### Phase 1: Design

- [ ] Discovery complete or defaults documented
- [ ] UC selected (UC-A through UC-J)
- [ ] RAM / disk estimates documented in README
- [ ] List required API keys (CF, etc.)

### Phase 2: File Generation

- [ ] `docker-compose.yml` (bind mount, `restart: unless-stopped`, `USE_AIKAR_FLAGS: TRUE`, `MOTD` required)
- [ ] `.dockerignore` (exclude `data/`)
- [ ] `Makefile` (see Chapter 5)
- [ ] `.env.example` + `.gitignore`
- [ ] `scripts/backup.sh` + `scripts/restore.sh` (+ `.ps1`)
- [ ] `README.md` (`make help` listing, OS-specific sections)
- [ ] Confirm **no** named volumes exist

### Phase 3: Startup and Verification

- [ ] `make config`
- [ ] `make up` (only when user explicitly requests)
- [ ] Confirm startup complete with `make logs`
  - Paper: `Done (XX.Xs)! For help, type "help"`
  - MODs: `Loading ... mods`
- [ ] Verify `data/` created and permissions correct
- [ ] Confirm MOTD (server name) in server list
- [ ] Client connection test

### Phase 4: Handoff

- [ ] README: connection method, MC version, Mod requirements
- [ ] README: start / stop / restart (by OS)
- [ ] README: backup / restore
- [ ] README: update procedure (`make update`)
- [ ] README: troubleshooting
- [ ] Confirm `.env` is gitignored
- [ ] Confirm systemd / cron are **not** configured

---

## Chapter 10 — Security

### 10.1 Authentication

- Default to `ONLINE_MODE=TRUE` (requires legitimate Minecraft account)
- Recommend `WHITE_LIST=TRUE` when exposed to the internet

### 10.2 RCON Password Generation

**Linux / WSL**:

```bash
openssl rand -hex 16
```

**Windows (PowerShell)**:

```powershell
-join ((1..16) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
```

Set the generated value as `RCON_PASSWORD` in `.env`. Never commit to git.

### 10.3 Secret Management

| File | Git tracking |
|----------|----------|
| `.env` | **Forbidden** |
| `CF_API_KEY` | In `.env` only |
| `forwarding.secret` | **Forbidden** |
| `RCON_PASSWORD` | In `.env` only |

### 10.4 Network

- When exposed to internet: open only required ports in firewall
- RCON port (25575) **not recommended** for external exposure (use VPN / SSH tunnel if needed)
- Velocity `forwarding.secret` must match on Paper and Velocity

### 10.5 Prohibited Operations

- `docker compose down -v` — **absolutely forbidden** (also document in README)
- Committing `.env` to git — **forbidden**
- Default RCON password — **forbidden**

---

## Chapter 11 — Troubleshooting

### 11.1 OS-Specific Remediation Table

| Symptom | Linux / WSL | Windows |
|------|-------------|---------|
| Permission denied on `data/` | `sudo chown -R $(id -u):$(id -g) data` | Move inside WSL |
| Port in use | `ss -tlnp \| grep 25565` | `netstat -ano \| findstr 25565` |
| Slow I/O | Check disk with `iostat` | Using path outside WSL (`/mnt/c`) |
| OOM Killed | `dmesg \| grep -i oom`, increase `MEMORY` | Docker Desktop → Resources → increase Memory |
| Firewall | `sudo ufw status` | Windows Defender Firewall |
| Line ending issues | — | `* text=auto` in `.gitattributes` |
| MOTD not shown | Check `OVERRIDE_SERVER_PROPERTIES` | Same |
| Container restart loop | Check cause with `make logs` | Same |
| MOD download failure | Verify `CF_API_KEY` / network | Check WSL DNS settings |

### 11.2 Common Docker Issues

**Container won't start**:

```bash
make config          # check syntax errors
docker compose logs  # check error messages
```

**Data disappeared**:

- With bind mount, `./data` should remain on the host
- Confirm `docker compose down -v` was not run
- Check `data.old.*` backup directories

**Startup failure after image update**:

```bash
make logs
# Version mismatch → pin VERSION
# MOD incompatibility → restore from backup
```

### 11.3 WSL2-Specific

**Insufficient memory**:

Increase in `%UserProfile%\.wslconfig` with `memory=8GB`, etc. → `wsl --shutdown`

**Docker Desktop integration failure**:

Settings → Resources → WSL Integration → turn ON the distro in use

**`/mnt/c` placement detected**:

```bash
make check-path
# ERROR → move to ~/servers/${SERVER_NAME}/
```

---

## Chapter 12 — Sample User Prompts

Examples the user can copy-paste to an AI agent. The agent builds according to this brief.

### Paper (Linux VPS)

> Set up Paper 1.21.1 on an Ubuntu VPS with server name `survival-2024`. 10 players, EssentialsX + LuckPerms, 4GB RAM, RCON, manual backup (full data). restart: unless-stopped, no systemd.

### Paper (Home Windows)

> Paper server on Windows 11 + WSL2. Server name `friends-mc`. LAN for 3 friends. data/ bind mount. MOTD auto from SERVER_NAME.

### CurseForge MOD

> ATM10 from CurseForge with server name `atm10-home`. CF_API_KEY available. 12GB RAM. WSL2. bind mount only.

### Modrinth Pack

> Fabulously Optimized from Modrinth with server name `fo-server`. Fabric, 6GB RAM.

### Velocity

> Velocity + lobby + survival with server name `network-01`. Docker Compose. WSL2. Include forwarding.secret setup.

### Bedrock

> Bedrock Dedicated Server on Windows + WSL2 with server name `bedrock-pe`. UDP 19132.

### Plugin Development

> Paper dev environment with server name `plugin-dev`. ONLINE_MODE=false, 2GB RAM. Mount plugins-dev/.

### Vanilla Minimal

> Vanilla 1.21.1 with server name `vanilla-test`. 2GB RAM. For smoke testing.

### Custom MODs

> Fabric + fabric-api, lithium, sodium from Modrinth with server name `fabric-custom`. 4GB RAM.

### Crossplay

> Paper + Geyser + Floodgate with server name `crossplay`. Java + Bedrock support.

---

## Chapter 13 — Reference Links

### Primary Repositories

| Use | Repository |
|------|-----------|
| General Java server | [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) |
| Bedrock only | [itzg/docker-minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server) |
| Velocity / BungeeCord | [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy) |
| GitOps (Paper) | [timo-reymann/blueprint-minecraft-server-gitops](https://github.com/timo-reymann/blueprint-minecraft-server-gitops) |
| Plugin development | [KevinTCoughlin/minecraft-server](https://github.com/KevinTCoughlin/minecraft-server) |
| Proxy example | [heyvaldemar/minecraft-server-proxy-docker-compose](https://github.com/heyvaldemar/minecraft-server-proxy-docker-compose) |
| IaC (cloud) | [nolte/minecraft-infrastructure](https://github.com/nolte/minecraft-infrastructure) |

### Documentation

- [itzg official documentation](https://docker-minecraft-server.readthedocs.io/)
- [examples directory](https://github.com/itzg/docker-minecraft-server/tree/master/examples)
- [CurseForge API Key](https://console.curseforge.com/)
- [Modrinth](https://modrinth.com/)
- [Paper MC](https://papermc.io/)
- [Velocity official](https://docs.papermc.io/velocity/)
- [Geyser MC](https://geysermc.org/)

### Out of Scope (Not Covered by This Brief)

The following are in-game AI bots and **out of scope**:

- Minecraft_AI
- mindcraft-ce
- AgentCraft

---

## Appendix A — Prohibited Practices Summary

| # | Prohibited | Alternative |
|---|----------|------|
| 1 | Docker named volume | bind mount `./data:/data` |
| 2 | `docker compose down -v` | `make down` (no `-v`) |
| 3 | systemd unit / cron timer | compose `restart: unless-stopped` |
| 4 | Automatic backup (cron, etc.) | Manual `make backup` |
| 5 | Windows `/mnt/c/` placement | Placement inside WSL home |
| 6 | `USE_AIKAR_FLAGS: "FALSE"` | Always `"TRUE"` |
| 7 | Omitting MOTD | `§6${SERVER_NAME}§r` |
| 8 | Fixed name `minecraft-server/` | `${SERVER_NAME}/` |
| 9 | CurseForge server-only zip | Client pack URL |
| 10 | Velocity with `127.0.0.1` | Docker service name (`lobby:25565`) |

---

## Appendix B — Research Summary (GitHub Pioneers)

| Use | Representative Repository | Role in This Brief |
|------|---------------|-------------------|
| General Java server | itzg/docker-minecraft-server | **First choice. Base for all UCs** |
| Bedrock only | itzg/docker-minecraft-bedrock-server | UC-F |
| Velocity/BungeeCord | itzg/docker-mc-proxy | UC-E |
| GitOps (Paper) | blueprint-minecraft-server-gitops | UC-I (advanced) |
| Plugin development | KevinTCoughlin/minecraft-server | UC-H |
| Proxy example | heyvaldemar/minecraft-server-proxy-docker-compose | UC-E (Windows path differences) |
| IaC | nolte/minecraft-infrastructure | Appendix (cloud only) |

---

*Following this brief, agents shall build reproducible Minecraft server environments.*


### UC-A: Paper Plugin Server

#### Overview

The most common setup: a Java server using Bukkit/Spigot-compatible plugins.

#### Prerequisites

- RAM: 4GB+ (for ~10 players)
- Disk: 10GB+
- Port: 25565/TCP

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME:-survival-2024}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
      - "${RCON_PORT:-25575}:25575"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}ﾂｧr"
      MAX_PLAYERS: "${MAX_PLAYERS:-10}"
      ENABLE_RCON: "${ENABLE_RCON:-TRUE}"
      RCON_PASSWORD: "${RCON_PASSWORD}"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
      ONLINE_MODE: "${ONLINE_MODE:-TRUE}"
      DIFFICULTY: "${DIFFICULTY:-normal}"
      WHITE_LIST: "${WHITE_LIST:-FALSE}"
      # Plugin URL list (comma-separated in env; multiline here)
      PLUGINS: |
        https://github.com/EssentialsX/Essentials/releases/latest/download/EssentialsX-2.21.0.jar
        https://download.luckperms.net/1565/bukkit/loader/LuckPerms-Bukkit-5.4.145.jar
    volumes:
      - ./data:/data
      - ./config/plugins:/plugins:ro
    restart: unless-stopped
```

#### Additional `.env.example` fields

```dotenv
TYPE=PAPER
VERSION=1.21.1
MEMORY=4G
MAX_PLAYERS=10
ENABLE_RCON=TRUE
RCON_PASSWORD=your-secure-password-here
```

#### First startup

**Linux / WSL**:

```bash
cd ~/servers/${SERVER_NAME}
cp .env.example .env
# Edit .env (SERVER_NAME, RCON_PASSWORD, etc.)
make init
make config
make up
make logs
```

**Windows (WSL2 recommended)**:

```powershell
wsl -d Ubuntu
cd ~/servers/${SERVER_NAME}
make init && make up
```

#### Startup verification

Success when logs show:

```
[Server thread/INFO]: Done (XX.Xs)! For help, type "help"
```

Check MOTD:

```bash
make rcon CMD="list"
```

#### Client connection

- Address: `<host-ip>:25565`
- LAN: IP on the same network
- Internet: router port forwarding required

#### Common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Plugins not loaded | Version mismatch | Use plugin builds for your MC version |
| Permission denied | UID/GID mismatch | `chown -R $(id -u):$(id -g) data` |
| MOTD not applied | OVERRIDE not set | `OVERRIDE_SERVER_PROPERTIES: "TRUE"` |

#### References

- [itzg/docker-minecraft-server 窶・Paper](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/)
- [Paper](https://papermc.io/)

---

### UC-B: CurseForge Modpack

#### Overview

Automatically download and build a modpack from CurseForge.

#### Prerequisites

- RAM: **8GB+** (12GB+ for large packs)
- Disk: **20GB+**
- `CF_API_KEY` required

#### Obtaining CF_API_KEY

1. Go to https://console.curseforge.com/
2. Create account / sign in
3. Generate an API key
4. Set `CF_API_KEY=...` in `.env` (never commit)

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "AUTO_CURSEFORGE"
      CF_API_KEY: "${CF_API_KEY}"
      CF_PAGE_URL: "${CF_PAGE_URL}"
      CF_PARALLEL_DOWNLOADS: "8"
      MEMORY: "${MEMORY:-8G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}ﾂｧr"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### Additional `.env.example` fields

```dotenv
TYPE=AUTO_CURSEFORGE
CF_API_KEY=
CF_PAGE_URL=https://www.curseforge.com/minecraft/modpacks/all-the-mods-10
MEMORY=12G
```

#### Important: do not use server-only zip

CurseForge offers client and server zips. Use the **client** modpack page URL in `CF_PAGE_URL`. Server-only zips may have incomplete mod sets.

#### First startup

First run may take **10窶・0 minutes** to download. Example logs:

```
[mc-image-helper] Downloading mod ...
[mc-image-helper] Mod download complete
```

#### Common failures

| Symptom | Fix |
|---------|-----|
| 401 Unauthorized | Check `CF_API_KEY` |
| OOM Killed | Increase `MEMORY`, adjust `.wslconfig` |
| Specific mod conflict | `CF_EXCLUDE_MODS` / `CF_FORCE_INCLUDE_MODS` |

---

### UC-C: Modrinth Modpack

#### Overview

Install a Modrinth-hosted modpack by URL.

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "MODRINTH"
      MODRINTH_MODPACK: "${MODRINTH_MODPACK}"
      MODRINTH_LOADER: "${MODRINTH_LOADER:-fabric}"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-6G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}ﾂｧr"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    ports:
      - "${MC_PORT:-25565}:25565"
    restart: unless-stopped
```

#### `.env.example`

```dotenv
MODRINTH_MODPACK=https://modrinth.com/modpack/fabulously-optimized
MODRINTH_LOADER=fabric
VERSION=LATEST
MEMORY=6G
```

---

### UC-D: Custom Mod List (Fabric / Forge / NeoForge)

#### Overview

Specify mods individually via Modrinth project slugs.

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "${TYPE:-FABRIC}"
      VERSION: "${VERSION:-LATEST}"
      MODRINTH_PROJECTS: |
        fabric-api
        lithium
        sodium?
      VERSION_FROM_MODRINTH_PROJECTS: "TRUE"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}ﾂｧr"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    ports:
      - "${MC_PORT:-25565}:25565"
    restart: unless-stopped
```

**`?` suffix**: optional mod (no error if missing)

**TYPE values**: `FABRIC` / `FORGE` / `NEOFORGE`

---

### UC-E: Velocity Proxy + Multiple Paper Servers

#### Overview

Combine lobby + survival (etc.) backends behind Velocity.

#### Prerequisites

- RAM: 2GB+ per server + 512MB for proxy
- Generate `forwarding.secret` and configure Paper

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  velocity:
    image: itzg/mc-proxy:latest
    ports:
      - "25565:25565"
    environment:
      TYPE: "VELOCITY"
      MEMORY: "512M"
    volumes:
      - ./velocity.toml:/config
      - ./forwarding.secret:/forwarding.secret:ro
    restart: unless-stopped
    depends_on:
      - lobby
      - survival

  lobby:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "2G"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}-lobbyﾂｧr"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data/lobby:/data
    restart: unless-stopped

  survival:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}-survivalﾂｧr"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data/survival:/data
    restart: unless-stopped
```

#### forwarding.secret setup (step by step)

1. Generate secret:

```bash
openssl rand -hex 16 > forwarding.secret
chmod 600 forwarding.secret
```

2. Configure `velocity.toml` (`player-info-forwarding-mode = "modern"`)

3. On each Paper server, `config/paper-global.yml`:

```yaml
proxies:
  velocity:
    enabled: true
    online-mode: true
    secret: "<contents of forwarding.secret>"
```

4. **Use Docker internal DNS**: backend address `lobby:25565` (**not** `127.0.0.1`)

#### Windows mount differences

```yaml
# Linux / WSL
- ./velocity.toml:/config

# Windows native
- ./velocity.toml:/config/velocity.toml
```

#### References

- [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy)
- [heyvaldemar/minecraft-server-proxy-docker-compose](https://github.com/heyvaldemar/minecraft-server-proxy-docker-compose)

---

### UC-F: Bedrock Dedicated Server

#### Overview

Minecraft Bedrock Edition server (PE / Windows 10 / Xbox, etc.).

#### Prerequisites

- Port: **19132/UDP** (not TCP)
- Image: `itzg/minecraft-bedrock-server`

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  bedrock:
    image: itzg/minecraft-bedrock-server:latest
    pull_policy: daily
    ports:
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      SERVER_NAME: "${SERVER_NAME}"
      GAMEMODE: "survival"
      DIFFICULTY: "normal"
      MAX_PLAYERS: "${MAX_PLAYERS:-10}"
      ALLOW_CHEATS: "false"
      LEVEL_NAME: "Bedrock level"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

**Note:** Bedrock does not need `USE_AIKAR_FLAGS` (Java only).

#### Firewall

```bash
# Linux
sudo ufw allow 19132/udp
```

```powershell
# Windows
New-NetFirewallRule -DisplayName "Minecraft Bedrock" -Direction Inbound -Protocol UDP -LocalPort 19132 -Action Allow
```

#### Client connection

- Bedrock client 竊・Servers 竊・`<IP>:19132`

---

### UC-G: Java + Bedrock Cross-Play (Geyser + Floodgate)

#### Overview

Add Geyser / Floodgate plugins to a Java server so Bedrock clients can join.

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "${MC_PORT:-25565}:25565"
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}ﾂｧr"
      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### Ports

- 25565/TCP 窶・Java clients
- 19132/UDP 窶・Bedrock clients

---

### UC-H: Plugin Development Environment

#### Overview

Paper API plugin dev server. Test via hot deploy or restart.

#### Prerequisites

- Local dev machine (WSL2 recommended)
- Gradle project (separate repo)

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "2G"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}-devﾂｧr"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
      - ./plugins-dev:/data/plugins
    restart: unless-stopped
```

#### Dev workflow

1. Gradle `build` 竊・`.jar`
2. Copy to `plugins-dev/`
3. `make restart` or RCON `reload confirm` (restart preferred)

#### References

- [KevinTCoughlin/minecraft-server](https://github.com/KevinTCoughlin/minecraft-server)

---

### UC-I: GitOps / VPS Production (Advanced)

#### Overview

GitOps deploy on a VPS. Auto-update via webhook.

#### Policy

- **Overview only** in this brief
- Details: [blueprint-minecraft-server-gitops](https://github.com/timo-reymann/blueprint-minecraft-server-gitops)
- Keep bind mount / `restart: unless-stopped` / `USE_AIKAR_FLAGS` principles
- **Still no systemd** for compose 窶・rely on Docker restart policy

#### Minimum components

- Git repo with compose + `.env.example`
- Deploy webhook 竊・`git pull && make update`
- Manual `make backup` before deploy

---

### UC-J: Vanilla Server (Minimal)

#### Overview

Minimal Vanilla Java server without plugins or mods. Good for smoke tests and learning.

#### Prerequisites

- RAM: 2GB+
- Disk: 5GB+

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "VANILLA"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-2G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "ﾂｧ6${SERVER_NAME}ﾂｧr"
      MAX_PLAYERS: "${MAX_PLAYERS:-5}"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### `.env.example`

```dotenv
SERVER_NAME=vanilla-test
MOTD=ﾂｧ6vanilla-testﾂｧr
TYPE=VANILLA
VERSION=1.21.1
MEMORY=2G
MAX_PLAYERS=5
```

#### Startup verification

```
[Server thread/INFO]: Done (XX.Xs)! For help, type "help"
```

---

## Chapter 8 窶・Environment Variable Reference

### 8.1 Project-wide variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| **`SERVER_NAME`** | **Yes** | From discovery. Root dir, backup name, Compose name | `survival-2024` |
| **`MOTD`** | **Yes** | Server list MOTD. Auto one-liner from `SERVER_NAME` | `ﾂｧ6survival-2024ﾂｧr` |
| `COMPOSE_PROJECT_NAME` | Yes | Docker Compose project name | `survival-2024` |
| `MC_PORT` | No | Java port | `25565` |
| `RCON_PORT` | No | RCON port | `25575` |

### 8.2 itzg/minecraft-server main variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `EULA` | Yes | Mojang EULA acceptance | `TRUE` |
| `TYPE` | No | Server type | `PAPER`, `VANILLA`, `FABRIC`, `AUTO_CURSEFORGE` |
| `VERSION` | No | MC version | `1.21.1`, `LATEST` |
| `MEMORY` | No | JVM heap | `4G` |
| **`USE_AIKAR_FLAGS`** | **Yes** | JVM tuning. **Always `TRUE`** | `TRUE` |
| `OVERRIDE_SERVER_PROPERTIES` | Yes | Apply MOTD etc. from env | `TRUE` |
| `MAX_PLAYERS` | No | Max players | `10` |
| `ENABLE_RCON` | No | Enable RCON | `TRUE` |
| `RCON_PASSWORD` | If RCON | Password | in `.env` |
| `UID` / `GID` | Linux recommended | File owner | `1000` |
| `ONLINE_MODE` | No | Premium auth | `TRUE` |
| `DIFFICULTY` | No | Difficulty | `normal` |
| `WHITE_LIST` | No | Whitelist | `TRUE` |
| `VIEW_DISTANCE` | No | View distance | `10` |
| `SPAWN_PROTECTION` | No | Spawn protection radius | `16` |

### 8.3 Modpack-related

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `CF_API_KEY` | For CF | CurseForge API key | `.env` |
| `CF_PAGE_URL` | For CF | Pack URL | `https://www.curseforge.com/...` |
| `CF_FILE_ID` | For CF | Pin specific file ID | `1234567` |
| `CF_PARALLEL_DOWNLOADS` | No | Parallel downloads | `8` |
| `CF_EXCLUDE_MODS` | No | Exclude mod slug | `sodium` |
| `CF_FORCE_INCLUDE_MODS` | No | Force include mod | `fabric-api` |
| `MODRINTH_MODPACK` | For MR | Modrinth pack URL | `https://modrinth.com/modpack/...` |
| `MODRINTH_LOADER` | For MR | Loader | `fabric`, `forge`, `quilt` |
| `MODRINTH_PROJECTS` | Custom | Mod slug list | `fabric-api\nlithium` |
| `VERSION_FROM_MODRINTH_PROJECTS` | No | Auto MC version | `TRUE` |

### 8.4 Plugins

| Variable | Description | Example |
|----------|-------------|---------|
| `PLUGINS` | Plugin URL list (newline-separated) | GitHub release URLs |
| `MODS` | Fabric/Forge mod URLs | Modrinth CDN URLs |
| `SPIGET_RESOURCES` | Spiget resource IDs | `34315` |

### 8.5 World and game settings

| Variable | Description | Example |
|----------|-------------|---------|
| `LEVEL` | World name | `world` |
| `MODE` | Game mode | `survival`, `creative` |
| `PVP` | PVP enabled | `TRUE` |
| `ALLOW_NETHER` | Nether enabled | `TRUE` |
| `ANNOUNCE_PLAYER_ACHIEVEMENTS` | Achievement announcements | `TRUE` |
| `ENABLE_COMMAND_BLOCK` | Command blocks | `FALSE` |
| `SNOOPER_ENABLED` | Snooper | `FALSE` |
| `GENERATE_STRUCTURES` | Structure generation | `TRUE` |
| `HARDCORE` | Hardcore mode | `FALSE` |

---

## Chapter 9 窶・Agent Execution Checklist

### Phase 0: Environment check

- [ ] **Confirm `SERVER_NAME` with user (highest priority)**
- [ ] **After `SERVER_NAME` is set, auto-set `MOTD=ﾂｧ6${SERVER_NAME}ﾂｧr`**
- [ ] Create project at `~/servers/${SERVER_NAME}/`
- [ ] Check `docker --version` / `docker compose version`
- [ ] Check free ports (Linux: `ss -tlnp`, Windows: `netstat -an`)
- [ ] Check free disk space
- [ ] On Windows: decide project location (WSL recommended)
- [ ] `make check-path` rejects `/mnt/` paths

### Phase 1: Design

- [ ] Discovery complete or defaults documented
- [ ] UC selected (UC-A through UC-J)
- [ ] RAM / disk estimates in README
- [ ] List required API keys (CF, etc.)

### Phase 2: File generation

- [ ] `docker-compose.yml` (bind mount, `restart: unless-stopped`, `USE_AIKAR_FLAGS: TRUE`, `MOTD` required)
- [ ] `.dockerignore` (exclude `data/`)
- [ ] `Makefile` (see Chapter 5)
- [ ] `.env.example` + `.gitignore`
- [ ] `scripts/backup.sh` + `scripts/restore.sh` (+ `.ps1`)
- [ ] `README.md` (`make help` listing, OS-specific sections)
- [ ] Confirm **no** named volumes

### Phase 3: Start and verify

- [ ] `make config`
- [ ] `make up` (only if user explicitly requests)
- [ ] `make logs` until ready
  - Paper: `Done (XX.Xs)! For help, type "help"`
  - Mods: `Loading ... mods`
- [ ] `data/` created with correct permissions
- [ ] MOTD (server name) visible in server list
- [ ] Client connection test

### Phase 4: Handoff

- [ ] README: connection, MC version, mod requirements
- [ ] README: start / stop / restart (per OS)
- [ ] README: backup / restore
- [ ] README: updates (`make update`)
- [ ] README: troubleshooting
- [ ] `.env` in gitignore
- [ ] Confirm **no** systemd / cron configured

---

## Chapter 10 窶・Security

### 10.1 Authentication

- Default `ONLINE_MODE=TRUE` (official Minecraft accounts)
- For internet exposure, recommend `WHITE_LIST=TRUE`

### 10.2 RCON password generation

**Linux / WSL**:

```bash
openssl rand -hex 16
```

**Windows (PowerShell)**:

```powershell
-join ((1..16) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
```

Put the value in `.env` as `RCON_PASSWORD`. Never commit.

### 10.3 Secrets management

| File | Git |
|------|-----|
| `.env` | **Never** |
| `CF_API_KEY` | `.env` only |
| `forwarding.secret` | **Never** |
| `RCON_PASSWORD` | `.env` only |

### 10.4 Network

- Internet exposure: firewall 窶・open only required ports
- RCON (25575): **not** recommended on public internet (use VPN / SSH tunnel if needed)
- Velocity `forwarding.secret` must match on Paper and Velocity

### 10.5 Forbidden operations

- `docker compose down -v` 窶・**absolutely forbidden** (also document in README)
- Committing `.env` 窶・**forbidden**
- Default RCON passwords 窶・**forbidden**

---

## Chapter 11 窶・Troubleshooting

### 11.1 OS-specific fixes

| Symptom | Linux / WSL | Windows |
|---------|-------------|---------|
| Permission denied on `data/` | `sudo chown -R $(id -u):$(id -g) data` | Move project into WSL |
| Port in use | `ss -tlnp \| grep 25565` | `netstat -ano \| findstr 25565` |
| Slow I/O | Check disk `iostat` | Using `/mnt/c` outside WSL |
| OOM Killed | `dmesg \| grep -i oom`, increase `MEMORY` | Docker Desktop 竊・Resources 竊・Memory |
| Firewall | `sudo ufw status` | Windows Defender Firewall |
| Line endings | 窶・| `.gitattributes` with `* text=auto` |
| MOTD missing | Check `OVERRIDE_SERVER_PROPERTIES` | Same |
| Restart loop | `make logs` for cause | Same |
| Mod download fail | `CF_API_KEY` / network | WSL DNS settings |

### 11.2 Common Docker issues

**Container won't start**:

```bash
make config          # syntax errors
docker compose logs  # error messages
```

**Data missing**:

- With bind mount, `./data` should remain on host
- Check if `docker compose down -v` was run
- Check `data.old.*` backup directories

**Fails after image update**:

```bash
make logs
# Version mismatch 竊・pin VERSION
# Mod incompatibility 竊・restore from backup
```

### 11.3 WSL2-specific

**Low memory**:

Increase `%UserProfile%\.wslconfig` e.g. `memory=8GB` 竊・`wsl --shutdown`

**Docker Desktop integration**:

Settings 竊・Resources 竊・WSL Integration 竊・enable your distro

**`/mnt/c` placement detected**:

```bash
make check-path
# ERROR 竊・move to ~/servers/${SERVER_NAME}/
```

---

## Chapter 12 窶・Sample User Prompts

Examples users can paste to an AI agent. The agent follows this brief.

### Paper (Linux VPS)

> Server name `survival-2024` on Ubuntu VPS, Paper 1.21.1. 10 players, EssentialsX + LuckPerms, 4GB RAM, RCON, manual backup (full data). restart: unless-stopped, no systemd.

### Paper (Windows home)

> Windows 11 + WSL2 Paper server. Server name `friends-mc`. LAN for 3 friends. bind mount for data/. MOTD auto from SERVER_NAME.

### CurseForge modpack

> Server name `atm10-home`, ATM10 from CurseForge. CF_API_KEY set. 12GB RAM. WSL2. bind mount only.

### Modrinth pack

> Server name `fo-server`, Fabulously Optimized from Modrinth. Fabric, 6GB RAM.

### Velocity

> Server name `network-01`, Velocity + lobby + survival. Docker Compose. WSL2. Include forwarding.secret setup.

### Bedrock

> Server name `bedrock-pe`, Bedrock Dedicated Server on Windows + WSL2. UDP 19132.

### Plugin development

> Server name `plugin-dev`, Paper dev environment. ONLINE_MODE=false, 2GB RAM. Mount plugins-dev/.

### Vanilla minimal

> Server name `vanilla-test`, Vanilla 1.21.1. 2GB RAM. Smoke test.

### Custom mods

> Server name `fabric-custom`, Fabric + fabric-api, lithium, sodium from Modrinth. 4GB RAM.

### Cross-play

> Server name `crossplay`, Paper + Geyser + Floodgate. Java and Bedrock.

---

## Chapter 13 窶・Reference Links

### Main repositories

| Use | Repository |
|-----|------------|
| General Java server | [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) |
| Bedrock only | [itzg/docker-minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server) |
| Velocity / BungeeCord | [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy) |
| GitOps (Paper) | [timo-reymann/blueprint-minecraft-server-gitops](https://github.com/timo-reymann/blueprint-minecraft-server-gitops) |
| Plugin development | [KevinTCoughlin/minecraft-server](https://github.com/KevinTCoughlin/minecraft-server) |
| Proxy example | [heyvaldemar/minecraft-server-proxy-docker-compose](https://github.com/heyvaldemar/minecraft-server-proxy-docker-compose) |
| IaC (cloud) | [nolte/minecraft-infrastructure](https://github.com/nolte/minecraft-infrastructure) |

### Documentation

- [itzg official docs](https://docker-minecraft-server.readthedocs.io/)
- [examples directory](https://github.com/itzg/docker-minecraft-server/tree/master/examples)
- [CurseForge API key](https://console.curseforge.com/)
- [Modrinth](https://modrinth.com/)
- [Paper MC](https://papermc.io/)
- [Velocity](https://docs.papermc.io/velocity/)
- [Geyser MC](https://geysermc.org/)

### Out of scope (in-game AI bots)

Not covered by this brief:

- Minecraft_AI
- mindcraft-ce
- AgentCraft

---

## Appendix A 窶・Forbidden Items Summary

| # | Forbidden | Alternative |
|---|-----------|-------------|
| 1 | Docker named volume | bind mount `./data:/data` |
| 2 | `docker compose down -v` | `make down` (no `-v`) |
| 3 | systemd unit / cron timer | compose `restart: unless-stopped` |
| 4 | Automatic backup (cron, etc.) | manual `make backup` |
| 5 | Windows `/mnt/c/` placement | WSL home directory |
| 6 | `USE_AIKAR_FLAGS: "FALSE"` | always `"TRUE"` |
| 7 | Omitting MOTD | `ﾂｧ6${SERVER_NAME}ﾂｧr` |
| 8 | Fixed name `minecraft-server/` | `${SERVER_NAME}/` |
| 9 | CurseForge server-only zip | client modpack URL |
| 10 | Velocity `127.0.0.1` | Docker service name (`lobby:25565`) |

---

## Appendix B 窶・Survey Summary (GitHub Precedents)

| Use | Representative repo | Role in this brief |
|-----|---------------------|-------------------|
| General Java server | itzg/docker-minecraft-server | **Primary choice. Base for all UCs** |
| Bedrock only | itzg/docker-minecraft-bedrock-server | UC-F |
| Velocity/BungeeCord | itzg/docker-mc-proxy | UC-E |
| GitOps (Paper) | blueprint-minecraft-server-gitops | UC-I (advanced) |
| Plugin development | KevinTCoughlin/minecraft-server | UC-H |
| Proxy example | heyvaldemar/minecraft-server-proxy-docker-compose | UC-E (Windows path notes) |
| IaC | nolte/minecraft-infrastructure | Appendix (cloud only) |

---

## Appendix C — Operations-Phase Lessons (from running a modded server)

> Distilled from operating a large modpack server (NeoForge 1.21.1, 265 mods) across 9 releases.
> Generalized from what users actually asked the agent to do.

### C.1 Graduating from template to operations repository (mandatory)

Once server data accumulates in a project built from this template, it **loses all meaning as a fork of the upstream** (real case: origin still pointed at the template while operational commits piled up; jars/mrpacks bloated .git to 6.8GB and made pushing impossible). **Do the following as soon as the server goes live**:

1. Full backup (`make down` → cp to external disk → verify size/files)
2. Archive the old `.git` outside the repo and run a fresh `git init`
3. Directory convention: `/` = agent work directory, `server/` (or `data/`) = `DATA_DIR`, `legacy/` = old versions
4. Two-layer gitignore:
   - Root: mrpack / zip / backups / tmp / old git archive
   - DATA_DIR: world / jars (`mods/*.jar*` — catches typo extensions too) / logs / `server.properties` (plaintext RCON password) / `usercache.json` / `ops.json` / `whitelist.json` / `banned-*`
5. Keep jars out of git; make `scripts/gen-mods-manifest.sh` output (**mods-manifest.tsv** with sha256) the source of truth
6. Accumulate operational lessons in `docs/brief-feedback.md` and feed them back to this template via PR

### C.2 Standard mod-update flow

1. **`make backup` (no exceptions)** → 2. fetch via `scripts/download-mod.sh` (Modrinth → CurseForge → GitHub; see [agent-mod-download.md](agent-mod-download.md)) → 3. delete old jars → 4. regenerate manifest → 5. `make restart` + confirm load in logs → 6. commit (push only when the user explicitly asks)

### C.3 Client distribution (mrpack)

- Index hashes must **match the server jars exactly**. For jars that differ from the Modrinth CDN, embed them under `overrides/mods/` instead (mismatches make launchers fail hash checks with "Unknown error", and Retry never fixes it)
- Tell players to **import into a fresh instance**. Overwriting an existing instance leaves stale jars/indexes behind and causes connection rejections
- Treat object storage (R2 etc.) as the canonical distribution channel; use distinct filenames per version and keep old versions

### C.4 Modded troubleshooting patterns

| Pattern | Fix |
|---------|-----|
| "It broke" but no crash report | A crash-handler mod (Neruina etc.) swallowed the tick exception. Check WARNs in `latest.log` |
| Identifying the culprit mod | The mixin name in the stack trace — `handler$xxx$<modid>$...` — identifies it immediately |
| Desync/ghosting on dedicated servers only | Suspect network-path settings. **Server and client values must match** |
| New breakage after adding a fix mod | Its mixin may fire on contraptions it wasn't designed for. Look for an updated build with null guards, or remove it |
| Abandoned fix mods | Remove them once the base mod gains official support (they start breaking things instead) |
| `Can't keep up!` | A load warning — usually not the root cause of a nearby exception |

---

*Follow this brief to build reproducible Minecraft server environments.*
