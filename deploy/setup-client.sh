#!/usr/bin/env bash
# setup-client.sh - configure a new machine as a distributed wiki client.
# Prerequisites: Tailscale already installed and connected to the private network.

set -euo pipefail

QDRANT_HOST="${1:-qdrant-server}"
WORKSPACE="${2:-$HOME/.openclaw/workspace}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Distributed wiki client setup ==="
echo "Qdrant host: $QDRANT_HOST"
echo "Workspace: $WORKSPACE"

if ! command -v syncthing >/dev/null 2>&1; then
  echo "Syncthing is not installed. Install it with your OS package manager:"
  echo "  Fedora/RHEL:   sudo dnf install syncthing"
  echo "  Ubuntu/Debian: sudo apt install syncthing"
  echo "  macOS:         brew install syncthing"
  echo "  Windows:       winget install Syncthing.Syncthing"
  echo "Then re-run this script."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required. Install Python 3.11+ and re-run this script." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/scripts" "$WORKSPACE/skills" "$WORKSPACE/wiki" "$WORKSPACE/wiki-works"
cp -R "$REPO_ROOT/scripts/." "$WORKSPACE/scripts/"
cp -R "$REPO_ROOT/skills/." "$WORKSPACE/skills/"
cp "$REPO_ROOT/deploy/syncthing-stignore" "$WORKSPACE/.stignore"

if [ ! -f "$WORKSPACE/wiki.config.json" ]; then
  cp "$REPO_ROOT/wiki.config.json" "$WORKSPACE/wiki.config.json"
fi

python3 - "$WORKSPACE/wiki.config.json" "$QDRANT_HOST" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
host = sys.argv[2]
cfg = json.loads(path.read_text(encoding="utf-8"))
cfg["workspace"] = str(path.parent)
cfg.setdefault("qdrant", {})
cfg["qdrant"]["host"] = host
cfg["qdrant"].setdefault("port", 6333)
cfg["qdrant"].setdefault("collection", "wiki_pages")
path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
print("wiki.config.json updated: qdrant.host =", cfg["qdrant"]["host"])
PY

echo ""
echo "=== Remaining manual steps ==="
echo "1. Open Syncthing UI: http://localhost:8384"
echo "2. Add this device to the server's Syncthing"
echo "3. Share the workspace folder ($WORKSPACE) from the server to this device"
echo "4. Wait for the initial sync to complete"
echo "5. Install the wiki plugin in OpenClaw"
echo "6. Verify: python3 '$WORKSPACE/scripts/wiki_context.py' --workspace '$WORKSPACE' --q 'test'"
