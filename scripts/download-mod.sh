#!/usr/bin/env bash
# Download Minecraft mods from Modrinth or CurseForge.
#
# Usage:
#   scripts/download-mod.sh modrinth <slug> [game_version] [loader] -o <dir>
#   scripts/download-mod.sh curseforge-file <fileId> [modIdOrSlug] -o <dir>
#
# Secrets: ~/.cursor/secrets/secret.env (CF_API_KEY) and project .env
# CF_API_KEY values contain `$` — always single-quote them in env files.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Source secrets before set -u (secret.env may contain optional refs)
set +u
set -a
# shellcheck disable=SC1091
[ -f "${HOME}/.cursor/secrets/secret.env" ] && . "${HOME}/.cursor/secrets/secret.env"
if [[ -z "${CF_API_KEY:-}" && -f .env ]]; then
  # Avoid sourcing full .env (UID is readonly in bash)
  CF_API_KEY="$(grep -m1 '^CF_API_KEY=' .env | cut -d= -f2- || true)"
  export CF_API_KEY
fi
set +a
set -euo pipefail

USER_AGENT="mc-server-agent-brief/1.0"
OUT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/download-mod.sh modrinth <slug> [game_version] [loader] -o <dir>
  scripts/download-mod.sh curseforge-file <fileId> [modIdOrSlug] -o <dir>

Options:
  -o <dir>   Output directory (required)

Examples:
  scripts/download-mod.sh modrinth sodium 1.21.1 neoforge -o ./tmp
  scripts/download-mod.sh curseforge-file 8186973 -o ./mods
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Never echo API keys — redact if they appear in curl stderr.
redact_secrets() {
  local msg="$1"
  if [[ -n "${CF_API_KEY:-}" ]]; then
    msg="${msg//${CF_API_KEY}/***REDACTED***}"
  fi
  printf '%s' "$msg"
}

curl_json() {
  local url="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  local err
  err="$(mktemp)"
  if ! curl -fsSL "$@" -H "User-Agent: ${USER_AGENT}" -o "$tmp" "$url" 2>"$err"; then
    local e
    e="$(redact_secrets "$(cat "$err")")"
    rm -f "$tmp" "$err"
    die "HTTP request failed: ${e:-unknown error}"
  fi
  rm -f "$err"
  cat "$tmp"
  rm -f "$tmp"
}

curl_cf_json() {
  : "${CF_API_KEY:?CF_API_KEY is not set (add to ~/.cursor/secrets/secret.env or .env)}"
  curl_json "$1" -H "x-api-key: ${CF_API_KEY}" -H "Accept: application/json"
}

download_url_to_file() {
  local url="$1"
  local dest="$2"
  curl -fsSL -H "User-Agent: ${USER_AGENT}" -o "$dest" "$url"
}

cmd_modrinth() {
  local slug="${1:?modrinth slug required}"
  local game_version="${2:-1.21.1}"
  local loader="${3:-neoforge}"

  local query
  query="$(python3 -c "import json,urllib.parse; print(urllib.parse.urlencode({'game_versions': json.dumps(['${game_version}']), 'loaders': json.dumps(['${loader}'])}))")"
  local versions_json
  versions_json="$(curl_json "https://api.modrinth.com/v2/project/${slug}/version?${query}")"

  local result
  result="$(VERSIONS_JSON="$versions_json" python3 - <<'PY'
import json, os, sys
versions = json.loads(os.environ["VERSIONS_JSON"])
if not versions:
    sys.exit("no matching Modrinth versions")
ver = versions[0]
for f in ver.get("files", []):
    if f.get("primary") or f.get("filename", "").endswith(".jar"):
        print(f["url"])
        print(f["filename"])
        sys.exit(0)
sys.exit("no jar file in latest version")
PY
)" || die "$result"

  local url filename
  url="$(sed -n '1p' <<<"$result")"
  filename="$(sed -n '2p' <<<"$result")"
  : "${OUT_DIR:?-o <dir> is required}"

  mkdir -p "$OUT_DIR"
  local dest="${OUT_DIR}/${filename}"
  echo "Downloading Modrinth ${slug} → ${dest}"
  download_url_to_file "$url" "$dest"
  echo "Saved: ${dest}"
}

cdn_url_for_file_id() {
  local file_id="$1"
  local filename="$2"
  local a="${file_id:0:4}"
  local b="${file_id: -3}"
  echo "https://mediafilez.forgecdn.net/files/${a}/${b}/${filename}"
}

cf_resolve_mod_id() {
  local hint="${1:-}"
  [[ -n "$hint" ]] || return 1
  if [[ "$hint" =~ ^[0-9]+$ ]]; then
    echo "$hint"
    return 0
  fi
  local search_json=""
  if [[ -n "${CF_API_KEY:-}" ]]; then
    local tmp code
    tmp="$(mktemp)"
    code="$(curl -sS -o "$tmp" -w "%{http_code}" \
      -H "x-api-key: ${CF_API_KEY}" \
      -H "Accept: application/json" \
      -H "User-Agent: ${USER_AGENT}" \
      "https://api.curseforge.com/v1/mods/search?gameId=432&slug=${hint}")"
    [[ "$code" == "200" ]] && search_json="$(cat "$tmp")"
    rm -f "$tmp"
  fi
  if [[ -z "$search_json" ]]; then
    local tmp2 code2
    tmp2="$(mktemp)"
    code2="$(curl -sS -o "$tmp2" -w "%{http_code}" -H "User-Agent: ${USER_AGENT}" \
      "https://www.curseforge.com/api/v1/mods/search?gameId=432&slug=${hint}")"
    [[ "$code2" == "200" ]] && search_json="$(cat "$tmp2")"
    rm -f "$tmp2"
  fi
  [[ -n "$search_json" ]] || return 1
  MOD_SEARCH_JSON="$search_json" python3 - <<'PY'
import json, os, sys
hits = json.loads(os.environ["MOD_SEARCH_JSON"]).get("data", [])
if not hits:
    sys.exit(1)
print(hits[0]["id"])
PY
}

cf_fetch_file_meta() {
  local file_id="$1"
  local mod_id="${2:-}"
  local file_json=""

  if [[ -n "${CF_API_KEY:-}" ]]; then
    local tmp code
    tmp="$(mktemp)"
    code="$(curl -sS -o "$tmp" -w "%{http_code}" -X POST \
      -H "x-api-key: ${CF_API_KEY}" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "User-Agent: ${USER_AGENT}" \
      -d "{\"fileIds\":[${file_id}]}" \
      "https://api.curseforge.com/v1/mods/files")"
    if [[ "$code" == "200" ]]; then
      file_json="$(cat "$tmp")"
      if [[ -z "$mod_id" ]]; then
        mod_id="$(FILE_JSON="$file_json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["FILE_JSON"]).get("data") or []
if data:
    print(data[0].get("modId", ""))
PY
)"
      fi
    else
      echo "WARN: CurseForge API POST /mods/files returned ${code}; using www fallback" >&2
    fi
    rm -f "$tmp"
  fi

  if [[ -z "$file_json" ]]; then
    [[ -n "$mod_id" ]] || die "modIdOrSlug required when API file lookup fails (e.g. curseforge-file ${file_id} 1557241 -o <dir>)"
    file_json="$(curl_json "https://www.curseforge.com/api/v1/mods/${mod_id}/files/${file_id}")"
  fi

  FILE_JSON="$file_json" MOD_ID="$mod_id" python3 - <<'PY'
import json, os, sys
raw = os.environ["FILE_JSON"]
body = json.loads(raw)
data = body.get("data")
if isinstance(data, list):
    data = data[0] if data else {}
if not data:
    sys.exit("CurseForge response missing file metadata")
fn = data.get("fileName")
if not fn:
    sys.exit("CurseForge response missing fileName")
mod_id = data.get("modId") or data.get("projectId") or os.environ.get("MOD_ID") or ""
url = data.get("downloadUrl") or ""
print(fn)
print(mod_id)
print(url)
PY
}

cmd_curseforge_file() {
  local file_id="${1:?curseforge fileId required}"
  local mod_hint="${2:-}"

  local mod_id=""
  if [[ -n "$mod_hint" ]]; then
    mod_id="$(cf_resolve_mod_id "$mod_hint")" || die "Could not resolve mod id from: ${mod_hint}"
  fi

  local meta
  meta="$(cf_fetch_file_meta "$file_id" "$mod_id")" || die "$meta"

  local filename cf_mod_id url
  filename="$(sed -n '1p' <<<"$meta")"
  cf_mod_id="$(sed -n '2p' <<<"$meta")"
  url="$(sed -n '3p' <<<"$meta")"

  : "${OUT_DIR:?-o <dir> is required}"
  mkdir -p "$OUT_DIR"
  local dest="${OUT_DIR}/${filename}"

  if [[ -n "$url" ]]; then
    echo "Downloading CurseForge file ${file_id} → ${dest}"
    download_url_to_file "$url" "$dest"
  elif [[ -n "$cf_mod_id" ]]; then
    echo "Downloading CurseForge file ${file_id} (mod ${cf_mod_id}) → ${dest}"
    curl -fsSL -H "User-Agent: ${USER_AGENT}" -L \
      -o "$dest" \
      "https://www.curseforge.com/api/v1/mods/${cf_mod_id}/files/${file_id}/download"
  else
    echo "Downloading CurseForge file ${file_id} via CDN → ${dest}"
    download_url_to_file "$(cdn_url_for_file_id "$file_id" "$filename")" "$dest"
  fi
  echo "Saved: ${dest}"
}

# Parse global -o and subcommand
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      OUT_DIR="${2:?-o requires a directory}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

[[ ${#ARGS[@]} -ge 1 ]] || { usage; exit 1; }

case "${ARGS[0]}" in
  modrinth)
    [[ ${#ARGS[@]} -ge 2 ]] || die "usage: modrinth <slug> [game_version] [loader] -o <dir>"
    cmd_modrinth "${ARGS[1]}" "${ARGS[2]:-}" "${ARGS[3]:-}"
    ;;
  curseforge-file)
    [[ ${#ARGS[@]} -ge 2 ]] || die "usage: curseforge-file <fileId> [modIdOrSlug] -o <dir>"
    cmd_curseforge_file "${ARGS[1]}" "${ARGS[2]:-}"
    ;;
  *)
    die "unknown subcommand: ${ARGS[0]}"
    ;;
esac
