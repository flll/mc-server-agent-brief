#!/usr/bin/env bash
# Generate mods-manifest.tsv: filename + sha256 + size for all mod jars.
# jar 実体は git 管理外にする運用のため、このマニフェストが構成の正本となる。
# Usage: scripts/gen-mods-manifest.sh [MODS_DIR] [OUT_TSV]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODS_DIR="${1:-${ROOT}/data/mods}"
OUT="${2:-${ROOT}/data/mods-manifest.tsv}"

[ -d "$MODS_DIR" ] || { echo "ERROR: mods dir not found: $MODS_DIR" >&2; exit 1; }

{
  printf "# filename\tsha256\tbytes\tstatus\n"
  for f in "$MODS_DIR"/*.jar "$MODS_DIR"/*.jar.disabled; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      *.disabled) status="disabled" ;;
      *)          status="enabled" ;;
    esac
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    size="$(stat -c%s "$f")"
    printf "%s\t%s\t%s\t%s\n" "$base" "$sha" "$size" "$status"
  done | sort
} > "$OUT"

enabled=$(grep -c $'\tenabled$' "$OUT" || true)
disabled=$(grep -c $'\tdisabled$' "$OUT" || true)
echo "Wrote $OUT (enabled: $enabled, disabled: $disabled)"
