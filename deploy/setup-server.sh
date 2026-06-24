#!/usr/bin/env bash
# setup-server.sh - configure the current machine as the distributed wiki server.
# Prerequisites: git, Python 3.11+, and either Docker, Podman, or a native Qdrant install.

set -euo pipefail

WORKSPACE="${1:-$HOME/.openclaw/workspace}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Distributed wiki server setup ==="
echo "Repo:      $REPO_ROOT"
echo "Workspace: $WORKSPACE"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required. Install Python 3.11+ and re-run this script." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/scripts" "$WORKSPACE/skills" "$WORKSPACE/wiki" "$WORKSPACE/wiki-works"
cp -R "$REPO_ROOT/scripts/." "$WORKSPACE/scripts/"
cp -R "$REPO_ROOT/skills/." "$WORKSPACE/skills/"

if [ ! -f "$WORKSPACE/wiki.config.json" ]; then
  cp "$REPO_ROOT/wiki.config.json" "$WORKSPACE/wiki.config.json"
fi
cp "$REPO_ROOT/deploy/syncthing-stignore" "$WORKSPACE/.stignore"

python3 -m pip install -r "$REPO_ROOT/requirements.txt"

python3 - "$WORKSPACE/wiki.config.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
cfg = json.loads(path.read_text(encoding="utf-8"))
cfg["workspace"] = str(path.parent)
cfg.setdefault("qdrant", {})
cfg["qdrant"]["host"] = "localhost"
cfg["qdrant"]["port"] = 6333
cfg["qdrant"].setdefault("collection", "wiki_pages")
path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
print(f"wiki.config.json updated: qdrant.host={cfg['qdrant']['host']} port={cfg['qdrant']['port']}")
PY

echo ""
echo "=== Qdrant check ==="
if curl -fsS http://localhost:6333/health >/dev/null 2>&1; then
  echo "Qdrant is already reachable at http://localhost:6333"
else
  echo "Qdrant is not reachable yet."
  if command -v podman >/dev/null 2>&1; then
    echo "Podman detected. Start Qdrant with:"
    echo "  mkdir -p ~/.config/systemd/user"
    echo "  cp '$REPO_ROOT/deploy/qdrant-podman.service' ~/.config/systemd/user/"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable --now qdrant-podman"
  elif command -v docker >/dev/null 2>&1; then
    echo "Docker detected. Start Qdrant with:"
    echo "  docker volume create qdrant_data"
    echo "  docker run -d --name qdrant --restart unless-stopped -p 6333:6333 -p 6334:6334 -v qdrant_data:/qdrant/storage qdrant/qdrant:latest"
  else
    echo "Install Qdrant with one of the methods in docs/install-qdrant.md."
  fi
fi

echo ""
echo "=== Remaining manual steps ==="
echo "1. Configure Tailscale: docs/tailscale-setup.md"
echo "2. Configure Syncthing for $WORKSPACE: docs/syncthing-setup.md"
echo "3. Verify: python3 '$WORKSPACE/scripts/wiki_check_setup.py' --workspace '$WORKSPACE'"
echo "4. If migrating from LanceDB: docs/migrate-lancedb-to-qdrant.md"
