#!/usr/bin/env bash
# Compare server mods vs client mods directory.
# Usage: scripts/diff-client-mods.sh /path/to/client/mods [SERVER_MODS_DIR]
set -euo pipefail

CLIENT="${1:?client mods directory required}"
SERVER="${2:-$(cd "$(dirname "$0")/.." && pwd)/data/mods}"

python3 - "$CLIENT" "$SERVER" <<'PY'
import re, sys
from pathlib import Path

client = Path(sys.argv[1])
server = Path(sys.argv[2])

def slug(j: str) -> str:
    s = re.sub(r"\.jar(\.disabled)?$", "", j)
    m = re.match(r"^(.+?)(?:[-_+]?(?:\d+\.\d+|\d+)[\w.+_-]*)$", s)
    return (m.group(1) if m else s).lower().replace(" ", "")

def collect(d: Path) -> dict[str, str]:
    out = {}
    if not d.is_dir():
        return out
    for p in d.iterdir():
        if p.suffix == ".jar" or p.name.endswith(".jar.disabled"):
            out[slug(p.name)] = p.name
    return out

c = collect(client)
s = collect(server)

missing_on_client = [s[k] for k in sorted(s) if k not in c and not s[k].endswith(".disabled")]
extra_on_client = [c[k] for k in sorted(c) if k not in s]
version_mismatch = [(s[k], c[k]) for k in sorted(s) if k in c and s[k] != c[k] and not s[k].endswith(".disabled")]

print(f"Server mods dir: {server}")
print(f"Client mods dir: {client}")
print(f"Server slugs: {len(s)} | Client slugs: {len(c)}")
print()
if missing_on_client:
    print(f"Missing on CLIENT ({len(missing_on_client)}) — add these jars:")
    for j in missing_on_client:
        print(f"  - {j}")
    print()
if extra_on_client:
    print(f"Extra on CLIENT only ({len(extra_on_client)}) — OK if client-side mods:")
    for j in extra_on_client[:30]:
        print(f"  - {j}")
    if len(extra_on_client) > 30:
        print(f"  … and {len(extra_on_client) - 30} more")
    print()
if version_mismatch:
    print(f"Version mismatch ({len(version_mismatch)}):")
    for sv, cv in version_mismatch:
        print(f"  server: {sv}")
        print(f"  client: {cv}")
    print()
if not missing_on_client and not version_mismatch:
    print("OK — server-required mods match (client may have extra client-only mods).")
PY
