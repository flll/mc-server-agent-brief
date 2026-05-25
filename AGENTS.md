# AGENTS.md — Short agent entry point

<h4 align="center">Translations:</h4>

<p align="center">
  EN |
  <a href="AGENTS.ja.md"><img src="https://img.shields.io/badge/-JP-red?style=flat-square" alt="JP"></a>
</p>

This repository is a brief for **Minecraft server infrastructure**, not in-game AI bots (AgentCraft / Steve, etc.).

## Required reading

Before you start, **read the full brief** below, then implement.

- [docs/en/minecraft-server-agent-brief.md](docs/en/minecraft-server-agent-brief.md)

## Workflow (summary)

1. **Confirm `SERVER_NAME` with the user** (highest priority; do not proceed without it)
2. Auto-set `MOTD=§6${SERVER_NAME}§r`
3. Confirm host OS (Linux / Windows+WSL2)
4. Chapter 1 discovery → pick use case → generate files
5. `make config` for syntax check → hand off to user

## Forbidden

| Forbidden | Reason |
|-----------|--------|
| Docker named volumes | bind mount `./data:/data` only |
| `docker compose down -v` | Risk of data loss |
| systemd unit / cron timer | No OS auto-start or scheduled jobs |
| Project under `/mnt/c/...` | WSL I/O degradation |
| Omitting `USE_AIKAR_FLAGS` | Always `TRUE` on Java servers |

## Required settings

- `restart: unless-stopped` (compose)
- `USE_AIKAR_FLAGS: "TRUE"` (Java)
- `OVERRIDE_SERVER_PROPERTIES: "TRUE"` + `MOTD`
- Backup: full `./data` → `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz`

## Reference implementation (this repo)

- [Makefile](Makefile) — daily operations
- [scripts/backup.sh](scripts/backup.sh) / [scripts/restore.sh](scripts/restore.sh)
- [.env.example](.env.example)

## External references

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — primary Docker image
- [Official documentation](https://docker-minecraft-server.readthedocs.io/)
