#!/usr/bin/env bash
# watch-sync.sh - ingest Syncthing-delivered Markdown pages into Qdrant.

set -euo pipefail

WORKSPACE="${1:-$HOME/.openclaw/workspace}"
WIKI_SCRIPT="$WORKSPACE/scripts/wiki.py"
STATE_FILE="$WORKSPACE/.synced-ingested.json"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "ERROR: inotifywait is required. Install inotify-tools." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required." >&2
  exit 1
fi

if [ ! -f "$WIKI_SCRIPT" ]; then
  echo "ERROR: wiki.py not found at $WIKI_SCRIPT" >&2
  exit 1
fi

mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

relpath() {
  python3 - "$WORKSPACE" "$1" <<'PY'
import os
import sys
workspace, path = sys.argv[1], sys.argv[2]
print(os.path.relpath(os.path.realpath(path), os.path.realpath(workspace)).replace(os.sep, "/"))
PY
}

file_hash() {
  python3 - "$1" <<'PY'
import hashlib
import sys
path = sys.argv[1]
h = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

state_get() {
  python3 - "$STATE_FILE" "$1" <<'PY'
import json
import sys
state_path, rel = sys.argv[1], sys.argv[2]
try:
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
except Exception:
    state = {}
print(state.get(rel, ""))
PY
}

state_set() {
  python3 - "$STATE_FILE" "$1" "$2" <<'PY'
import json
import os
import sys
state_path, rel, digest = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
except Exception:
    state = {}
state[rel] = digest
tmp = state_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, sort_keys=True)
os.replace(tmp, state_path)
PY
}

should_ingest() {
  local file="$1"
  local rel="$2"

  [ -f "$file" ] || return 1
  [[ "$rel" == wiki/*.md || "$rel" == wiki-works/*.md ]] || return 1
  [[ "$rel" == *.tmp ]] && return 1
  [[ "$rel" == *".sync-conflict-"* ]] && return 1
  [[ "$rel" == "wiki/index.md" ]] && return 1
  return 0
}

echo "Watching Syncthing Markdown updates in $WORKSPACE"

inotifywait -m -r -e close_write,moved_to --format '%w%f' \
  "$WORKSPACE/wiki" "$WORKSPACE/wiki-works" \
| while IFS= read -r file; do
    rel="$(relpath "$file")"
    if ! should_ingest "$file" "$rel"; then
      continue
    fi

    sleep 1
    digest="$(file_hash "$file")"
    previous="$(state_get "$rel")"
    if [ "$digest" = "$previous" ]; then
      continue
    fi

    echo "Ingesting synced page: $rel"
    if python3 "$WIKI_SCRIPT" ingest \
      --workspace "$WORKSPACE" \
      --pages "$rel" \
      --log "sync-watchdog | $(date -Iseconds) | $rel"; then
      state_set "$rel" "$digest"
    else
      echo "ERROR: ingest failed for $rel" >&2
    fi
  done
