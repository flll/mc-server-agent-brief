#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${SERVER_NAME:?SERVER_NAME is not set in .env}"

TS=$(date +%Y%m%d_%H%M%S)
mkdir -p backups

echo "Flushing world data..."
docker compose exec -T mc rcon-cli save-all flush 2>/dev/null || true

echo "Stopping server for consistent backup..."
docker compose stop mc

ARCHIVE="backups/${SERVER_NAME}_data_${TS}.tar.gz"
tar -czf "${ARCHIVE}" -C . data

echo "Starting server..."
docker compose start mc

echo "Backup complete: ${ARCHIVE}"
