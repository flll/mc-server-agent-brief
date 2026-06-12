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
6. Once the server goes live, **graduate it into an independent operations repository** (Appendix C.1 of the brief)

## Forbidden

| Forbidden | Reason |
|-----------|--------|
| Docker named volumes | bind mount `./data:/data` only |
| `docker compose down -v` | Risk of data loss |
| systemd unit / cron timer | No OS auto-start or scheduled jobs |
| Project under `/mnt/c/...` | WSL I/O degradation |
| Omitting `USE_AIKAR_FLAGS` | Always `TRUE` on Java servers |
| Committing jars / mrpacks / zips to git | Repo bloat (real case: 6.8GB .git) — use `mods-manifest.tsv` instead |
| Changing mods without `make backup` first | No-exception rule from operations |

## Troubleshooting shorthand (modded)

- No crash report but "it broke": a crash-handler mod may have swallowed the exception — check `latest.log` WARNs
- Culprit mod: the mixin name `handler$xxx$<modid>$...` in the stack trace identifies it immediately
- Details: Appendix C.4 of the brief

## Required settings

- `restart: unless-stopped` (compose)
- `USE_AIKAR_FLAGS: "TRUE"` (Java)
- `OVERRIDE_SERVER_PROPERTIES: "TRUE"` + `MOTD`
- Backup: full `./data` → `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz`

## Reference implementation (this repo)

- [Makefile](Makefile) — daily operations
- [scripts/backup.sh](scripts/backup.sh) / [scripts/restore.sh](scripts/restore.sh)
- [scripts/download-mod.sh](scripts/download-mod.sh) — fetch mods from Modrinth / CurseForge ([guide](docs/en/agent-mod-download.md))
- [scripts/gen-mods-manifest.sh](scripts/gen-mods-manifest.sh) — mods-manifest.tsv (sha256 source of truth, keeps jars out of git)
- [scripts/diff-client-mods.sh](scripts/diff-client-mods.sh) — server vs client jar diff
- [.env.example](.env.example)

## External references

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — primary Docker image
- [Official documentation](https://docker-minecraft-server.readthedocs.io/)
