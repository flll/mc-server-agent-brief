# Agent Mod Download Guide

Standard workflow for fetching mod jars during modded-server operations.

## Source priority

1. **Modrinth** (no API key — first choice)
2. **CurseForge API** (requires `CF_API_KEY`)
3. **GitHub Releases** (community fix mods, etc.)

## Prerequisites

| Item | Detail |
|------|--------|
| Script | [`scripts/download-mod.sh`](../../scripts/download-mod.sh) |
| Modrinth | No API key |
| CurseForge | `CF_API_KEY` required (**never commit to git**) |
| Secret loading order | `~/.cursor/secrets/secret.env` → project `.env` |

## Managing CF_API_KEY (based on real incidents)

Use only keys issued at the **[CurseForge Console](https://console.curseforge.com/)** (API Keys page). Keys legitimately start with `$2a$10$`, but pasting an unrelated bcrypt hash yields `Forbidden: API Key missing or invalid` (HTTP **403**).

Always **single-quote** the value — unquoted `$` sequences get expanded by bash and silently corrupt the key:

```bash
CF_API_KEY='$2a$10$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
```

Validate without printing the key:

```bash
set -a; . ~/.cursor/secrets/secret.env; set +a
test -n "$CF_API_KEY" && echo "CF_API_KEY: set (${#CF_API_KEY} chars)"
curl -sS -o /dev/null -w "GET /v1/games -> HTTP %{http_code}\n" \
  -H "x-api-key: ${CF_API_KEY}" -H "Accept: application/json" \
  https://api.curseforge.com/v1/games
# 200 = valid / 401 or 403 = reissue the key
```

## Usage

```bash
# Modrinth — latest matching version
scripts/download-mod.sh modrinth <slug> [game_version] [loader] -o <dir>

# CurseForge — by file ID (for mods not on Modrinth)
# modIdOrSlug is required when the official API returns 403 (www API fallback)
scripts/download-mod.sh curseforge-file <fileId> [modIdOrSlug] -o <dir>
```

## Agent workflow (server mod update)

1. **`make backup`** — always back up first, no exceptions
2. **Download** — place jars into `DATA_DIR/mods/` via `download-mod.sh`
3. **Remove old versions** — including stray `.jar.disabled` files
4. **Regenerate manifest** — `scripts/gen-mods-manifest.sh`
5. **`make restart`** — confirm the mod loads in logs
6. **git commit** — never include secrets or jar binaries

## Security

- The script never prints API key values and redacts them from curl errors
- Never commit `.env` / `secret.env`
- Never paste key values into chat or logs (verify by length / first few chars only)

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `CF_API_KEY is not set` | Set it in `~/.cursor/secrets/secret.env` or `.env` |
| `401` / `403` | Issue a fresh key at console.curseforge.com, re-set with single quotes |
| Official API 403 but jar needed | Pass `modIdOrSlug` (www API fallback) |
| Modrinth `no matching versions` | Check slug / game_version / loader |
