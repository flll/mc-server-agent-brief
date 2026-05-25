<div align="center">

<p align="center">
  <img src="docs/assets/logo.png" alt="mc-server-agent-brief" width="150" height="150">
</p>

<h1 align="center">:sunny: AI agent brief for Minecraft servers :crescent_moon:</h1>

<p align="center">
  Instruction document and reference tooling for AI agents building Docker-based Minecraft servers.
  <br>
  Paper, modpacks, Velocity, Bedrock — Linux and Windows (WSL2).
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/itzg/docker-minecraft-server"><img src="https://img.shields.io/badge/Docker-itzg%2Fminecraft--server-2496ED?logo=docker&logoColor=white" alt="Docker"></a>
  <a href="https://github.com/flll/mc-server-agent-brief"><img src="https://img.shields.io/github/stars/flll/mc-server-agent-brief?style=social" alt="GitHub stars"></a>
</p>

<h2 align="center">
  <a href="#quick-start">Brief</a> |
  <a href="docs/en/minecraft-server-agent-brief.md">Docs</a> |
  <a href="AGENTS.md">Agents</a> |
  <a href="Makefile">Makefile</a> |
  <a href="#license">License</a>
</h2>

<h4 align="center">Translations:</h4>

<p align="center">
  EN |
  <a href="README.ja.md"><img src="https://img.shields.io/badge/-JP-red?style=flat-square" alt="JP"></a>
</p>

<p align="center"><sub>This brief could be your agent's go-to Minecraft server guide.</sub></p>

</div>

Brief and reference tooling for **AI agents** (Cursor, Claude Code, etc.) to build Minecraft servers with Docker.

> **Note:** This is **not** an in-game AI bot (unlike [AgentCraft](https://github.com/wrxck/AgentCraft) or Steve). It guides agents to set up **server infrastructure**.

---

## What's included

| File | Description |
|------|-------------|
| [docs/en/minecraft-server-agent-brief.md](docs/en/minecraft-server-agent-brief.md) | Detailed brief (English) |
| [docs/ja/minecraft-server-agent-brief.md](docs/ja/minecraft-server-agent-brief.md) | 詳細指示書（日本語） |
| [AGENTS.md](AGENTS.md) | Short agent entry point |
| [Makefile](Makefile) | Unified entry for daily operations |
| [scripts/](scripts/) | Backup / restore (Linux + Windows) |
| [.env.example](.env.example) | Environment variable template |

This README describes **this repository**. It is separate from per-server `README.md` files that agents generate when they build a server.

---

## Quick start

### 1. Give the agent the brief

```text
Read docs/en/minecraft-server-agent-brief.md and build a Minecraft server.
```

Or link [AGENTS.md](AGENTS.md) in Cursor Rules / project rules.

### 2. What the agent generates

The agent creates under `~/servers/${SERVER_NAME}/`:

- `docker-compose.yml` (bind mount, `restart: unless-stopped`)
- `.env` / `.env.example`
- `Makefile` (based on this repo's reference implementation)

### 3. Start the server (user)

```bash
cd ~/servers/your-server-name
cp .env.example .env   # edit SERVER_NAME, etc.
make init
make up
make logs
```

On Windows, run `make` **inside WSL2** when possible.

---

## Key policies

| Topic | Policy |
|------|--------|
| Persistence | bind mount `./data:/data` only (no named volumes) |
| Performance | On WSL2, place under ext4 (not `/mnt/c`) |
| Restart | `restart: unless-stopped` (no systemd) |
| JVM | `USE_AIKAR_FLAGS: "TRUE"` always required |
| MOTD | Auto-generate `§6${SERVER_NAME}§r` |
| Backup | Full `./data` via manual `make backup` |

---

## Use cases (brief Chapter 7)

- Paper / Purpur plugin servers
- CurseForge / Modrinth modpacks
- Fabric / Forge custom mods
- Velocity proxy + multiple Paper backends
- Bedrock Dedicated Server
- Geyser cross-play
- Plugin dev environment (reference)

Base image: [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)

---

## Makefile commands (reference)

| Command | Description |
|---------|-------------|
| `make help` | List targets |
| `make init` | First-time setup (`.env`, directories) |
| `make config` | Validate compose syntax |
| `make up` | Start |
| `make down` | Stop |
| `make restart` | Restart |
| `make logs` | Follow logs |
| `make status` | Container status |
| `make pull` | Pull images |
| `make update` | Pull images + restart |
| `make backup` | Backup full `./data` |
| `make restore` | `RESTORE=backups/xxx.tar.gz make restore` |
| `make shell` | Enter container |
| `make rcon CMD="list"` | Run RCON command |
| `make check-path` | Detect slow WSL paths |

---

## Sample user prompts

```text
Server name survival-2024, Paper 1.21.1. 10 players, 4GB RAM, RCON on.
Follow docs/en/minecraft-server-agent-brief.md.
```

```text
CurseForge All the Mods 10. 12GB RAM. WSL2.
Follow the mc-server-agent-brief.
```

---

## Maintaining docs

Treat **Japanese (`docs/ja/`) as source of truth** and keep English (`docs/en/`) in sync for the same chapters.

---

## License

[MIT License](LICENSE)

---

## Links

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [docker-minecraft-server docs](https://docker-minecraft-server.readthedocs.io/)
