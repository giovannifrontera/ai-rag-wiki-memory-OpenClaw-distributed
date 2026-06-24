#!/usr/bin/env bash
# install-server-full.sh - full server installer for the distributed wiki.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./deploy/install-server-full.sh [workspace] [openclaw-config]

Examples:
  ./deploy/install-server-full.sh
  ./deploy/install-server-full.sh ~/.openclaw/workspace ~/.openclaw/config.json
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

WORKSPACE="${1:-$HOME/.openclaw/workspace}"
OPENCLAW_CONFIG="${2:-}"
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

qdrant_ready() {
  curl -fsS http://localhost:6333/health >/dev/null 2>&1
}

start_qdrant() {
  if qdrant_ready; then
    echo "Qdrant already reachable at localhost:6333"
    return
  fi

  if command -v podman >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/systemd/user"
    cp "$REPO_ROOT/deploy/qdrant-podman.service" "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable --now qdrant-podman
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
  elif command -v docker >/dev/null 2>&1; then
    docker volume inspect qdrant_data >/dev/null 2>&1 || docker volume create qdrant_data >/dev/null
    if ! docker ps --format '{{.Names}}' | grep -qx qdrant; then
      if docker ps -a --format '{{.Names}}' | grep -qx qdrant; then
        docker start qdrant >/dev/null
      else
        docker run -d --name qdrant --restart unless-stopped \
          -p 6333:6333 -p 6334:6334 \
          -v qdrant_data:/qdrant/storage \
          qdrant/qdrant:latest >/dev/null
      fi
    fi
  else
    echo "ERROR: Qdrant is not reachable and neither Podman nor Docker is available." >&2
    echo "Install Qdrant using docs/install-qdrant.md, then re-run this installer." >&2
    exit 1
  fi

  for _ in $(seq 1 30); do
    if qdrant_ready; then
      echo "Qdrant reachable at localhost:6333"
      return
    fi
    sleep 1
  done

  echo "ERROR: Qdrant did not become reachable at localhost:6333" >&2
  exit 1
}

ensure_smoke_page() {
  if find "$WORKSPACE/wiki" "$WORKSPACE/wiki-works" -name '*.md' -print -quit 2>/dev/null | grep -q .; then
    python3 "$WORKSPACE/scripts/wiki.py" rebuild --workspace "$WORKSPACE"
  else
    mkdir -p "$WORKSPACE/wiki/concepts"
    printf '# Setup Smoke Test\n\nTemporary setup validation page.\n' > "$WORKSPACE/wiki/concepts/setup-smoke-test.md.tmp"
    python3 "$WORKSPACE/scripts/wiki.py" ingest \
      --workspace "$WORKSPACE" \
      --pages wiki/concepts/setup-smoke-test.md.tmp \
      --log "setup | server smoke test"
  fi
}

step "Preflight"
need_cmd python3
need_cmd git
need_cmd curl
need_cmd node
need_cmd npm
need_cmd syncthing
need_cmd inotifywait
need_cmd systemctl

step "Workspace bootstrap"
"$REPO_ROOT/deploy/setup-server.sh" "$WORKSPACE"

step "Qdrant"
start_qdrant

step "Qdrant collection"
ensure_smoke_page
python3 "$WORKSPACE/scripts/wiki.py" query --workspace "$WORKSPACE" --q "setup smoke test" --k 1 >/dev/null

step "Syncthing"
systemctl --user enable --now syncthing
loginctl enable-linger "$USER" >/dev/null 2>&1 || true

step "Server ingest watchdog"
mkdir -p "$HOME/.config/systemd/user"
cp "$WORKSPACE/deploy/wiki-sync-watchdog.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now wiki-sync-watchdog
systemctl --user is-active --quiet wiki-sync-watchdog

step "OpenClaw plugin build"
npm install --prefix "$PLUGIN_DIR"
npm run build --prefix "$PLUGIN_DIR"

step "OpenClaw plugin config"
SETUP_ARGS=( "$REPO_ROOT/scripts/setup_openclaw.py" --workspace "$WORKSPACE" --python "$(python3 -c 'import sys; print(sys.executable)')" )
if [ -n "$OPENCLAW_CONFIG" ]; then
  SETUP_ARGS+=( --config "$OPENCLAW_CONFIG" )
fi
python3 "${SETUP_ARGS[@]}"

step "Final verification"
python3 "$WORKSPACE/scripts/wiki_check_setup.py" --workspace "$WORKSPACE"
python3 "$WORKSPACE/scripts/wiki_context.py" --workspace "$WORKSPACE" --q "setup smoke test" --k 1 >/dev/null
python3 "$WORKSPACE/scripts/wiki.py" lint --workspace "$WORKSPACE" --full >/dev/null
bash -n "$WORKSPACE/scripts/watch-sync.sh"

echo ""
echo "Server install complete."
echo "Workspace: $WORKSPACE"
echo "Qdrant:    localhost:6333"
echo "Manual checks still required:"
echo "1. Ensure Tailscale is logged in and clients can curl http://<server-tailnet-ip>:6333/health."
echo "2. Pair Syncthing client devices in http://localhost:8384."
echo "3. Restart OpenClaw so the plugin config is loaded."
