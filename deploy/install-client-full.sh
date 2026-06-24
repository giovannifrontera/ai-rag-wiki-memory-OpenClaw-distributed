#!/usr/bin/env bash
# install-client-full.sh - full client installer for the distributed wiki.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./deploy/install-client-full.sh <qdrant-host> [workspace] [openclaw-config]

Examples:
  ./deploy/install-client-full.sh myserver.tailnet.ts.net
  ./deploy/install-client-full.sh 100.75.198.53 ~/.openclaw/workspace ~/.openclaw/config.json
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -lt 1 ]; then
  usage
  exit 0
fi

QDRANT_HOST="$1"
WORKSPACE="${2:-$HOME/.openclaw/workspace}"
OPENCLAW_CONFIG="${3:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/wiki-context-plugin"

step() {
  echo ""
  echo "=== $* ==="
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    echo "Install it, then re-run this installer." >&2
    exit 1
  fi
}

step "Preflight"
need_cmd python3
need_cmd syncthing
need_cmd node
need_cmd npm

if ! curl -fsS "http://$QDRANT_HOST:6333/health" >/dev/null; then
  echo "ERROR: Qdrant is not reachable at http://$QDRANT_HOST:6333/health" >&2
  echo "Fix Tailscale/hostname/firewall before continuing." >&2
  exit 1
fi
echo "Qdrant reachable: $QDRANT_HOST:6333"

step "Workspace bootstrap"
"$REPO_ROOT/deploy/setup-client.sh" "$QDRANT_HOST" "$WORKSPACE"

step "Python dependencies"
python3 -m pip install -r "$REPO_ROOT/requirements.txt"

step "OpenClaw plugin build"
npm install --prefix "$PLUGIN_DIR"
npm run build --prefix "$PLUGIN_DIR"

step "OpenClaw plugin config"
SETUP_ARGS=( "$REPO_ROOT/scripts/setup_openclaw.py" --workspace "$WORKSPACE" --python "$(python3 -c 'import sys; print(sys.executable)')" )
if [ -n "$OPENCLAW_CONFIG" ]; then
  SETUP_ARGS+=( --config "$OPENCLAW_CONFIG" )
fi
python3 "${SETUP_ARGS[@]}"

step "Verification"
python3 "$WORKSPACE/scripts/wiki_check_setup.py" --workspace "$WORKSPACE"
python3 "$WORKSPACE/scripts/wiki_context.py" --workspace "$WORKSPACE" --q "setup smoke test" --k 1 >/dev/null
python3 "$WORKSPACE/scripts/wiki.py" query --workspace "$WORKSPACE" --q "setup smoke test" --k 1 >/dev/null

echo ""
echo "Client install complete."
echo "Workspace: $WORKSPACE"
echo "Qdrant:    $QDRANT_HOST:6333"
echo "Next manual checks:"
echo "1. Pair Syncthing with the server if not already paired."
echo "2. Restart OpenClaw so the plugin config is loaded."
