#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

RESTORE="${1:?Usage: RESTORE=backups/SERVER_NAME_data_xxx.tar.gz make restore}"

if [[ ! -f "${RESTORE}" ]]; then
  echo "ERROR: Backup file not found: ${RESTORE}"
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${SERVER_NAME:?SERVER_NAME is not set in .env}"

echo "Stopping containers..."
docker compose down

if [[ -d data ]]; then
  OLD="data.old.$(date +%s)"
  echo "Moving existing data/ to ${OLD}/"
  mv data "${OLD}"
fi

echo "Extracting ${RESTORE}..."
tar -xzf "${RESTORE}"

if [[ -f .env ]] && grep -q '^UID=' .env && grep -q '^GID=' .env; then
  UID_VAL=$(grep '^UID=' .env | cut -d= -f2)
  GID_VAL=$(grep '^GID=' .env | cut -d= -f2)
  if [[ -n "${UID_VAL}" && -n "${GID_VAL}" ]]; then
    chown -R "${UID_VAL}:${GID_VAL}" data 2>/dev/null || sudo chown -R "${UID_VAL}:${GID_VAL}" data || true
  fi
fi

echo "Restore complete. Run 'make up' to start the server."
