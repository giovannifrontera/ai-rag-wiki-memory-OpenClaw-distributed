#!/bin/bash
# setup-client.sh — configure a new machine as a distributed wiki client
# Prerequisites: Tailscale already installed and connected to the private network

set -e

QDRANT_HOST="${1:-qdrant-server}"
WORKSPACE="$HOME/.openclaw/workspace"

echo "=== Distributed wiki client setup ==="
echo "Qdrant host: $QDRANT_HOST"
echo "Workspace: $WORKSPACE"

# 1. Check Syncthing is installed
if ! command -v syncthing &>/dev/null; then
    echo "Syncthing is not installed. Install it with your OS package manager:"
    echo "  Fedora/RHEL:  sudo dnf install syncthing"
    echo "  Ubuntu/Debian: sudo apt install syncthing"
    echo "  macOS:        brew install syncthing"
    echo "  Windows:      winget install Syncthing.Syncthing"
    echo "Then re-run this script."
    exit 1
fi

# 2. Create workspace directory
mkdir -p "$WORKSPACE"

# 3. Copy .stignore
cp "$(dirname "$0")/syncthing-stignore" "$WORKSPACE/.stignore"

# 4. Update wiki.config.json with remote Qdrant host
if [ -f "$WORKSPACE/wiki.config.json" ]; then
    python3 -c "
import json, sys
with open('$WORKSPACE/wiki.config.json') as f:
    cfg = json.load(f)
cfg['qdrant']['host'] = '$QDRANT_HOST'
with open('$WORKSPACE/wiki.config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
print('wiki.config.json updated: qdrant.host =', cfg['qdrant']['host'])
"
fi

echo ""
echo "=== Remaining manual steps ==="
echo "1. Open Syncthing UI: http://localhost:8384"
echo "2. Add this device to the server's Syncthing"
echo "3. Share the workspace folder ($WORKSPACE) from the server to this device"
echo "4. Wait for the initial sync to complete"
echo "5. Install the wiki plugin in OpenClaw"
echo "6. Verify: python scripts/wiki_context.py --workspace $WORKSPACE --q 'test'"
