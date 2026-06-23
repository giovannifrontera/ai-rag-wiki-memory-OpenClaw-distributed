#!/bin/bash
# setup-client.sh — configura una nuova macchina come client Virginia
# Prerequisiti: Tailscale già installato e collegato alla rete privata

set -e

BAZZITE_HOST="${1:-bazzite.tail}"
WORKSPACE="$HOME/.openclaw/workspace"

echo "=== Setup Virginia client ==="
echo "Bazzite host: $BAZZITE_HOST"
echo "Workspace: $WORKSPACE"

# 1. Installa Syncthing
if ! command -v syncthing &>/dev/null; then
    echo "Installa Syncthing dal gestore pacchetti del tuo OS:"
    echo "  Fedora/Bazzite: sudo dnf install syncthing"
    echo "  Ubuntu: sudo apt install syncthing"
    echo "  Windows: winget install Syncthing.Syncthing"
    echo "Poi riesegui questo script."
    exit 1
fi

# 2. Crea workspace
mkdir -p "$WORKSPACE"

# 3. Copia stignore
cp "$(dirname "$0")/syncthing-stignore" "$WORKSPACE/.stignore"

# 4. Aggiorna wiki.config.json con host Qdrant remoto
if [ -f "$WORKSPACE/wiki.config.json" ]; then
    python3 -c "
import json, sys
with open('$WORKSPACE/wiki.config.json') as f:
    cfg = json.load(f)
cfg['qdrant']['host'] = '$BAZZITE_HOST'
with open('$WORKSPACE/wiki.config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
print('wiki.config.json aggiornato: qdrant.host =', cfg['qdrant']['host'])
"
fi

echo ""
echo "=== Passi manuali rimanenti ==="
echo "1. Apri Syncthing UI: http://localhost:8384"
echo "2. Aggiungi questo dispositivo al Syncthing di Bazzite"
echo "3. Condividi la cartella $WORKSPACE da Bazzite verso questo dispositivo"
echo "4. Attendi la sincronizzazione iniziale"
echo "5. Installa il plugin wiki in OpenClaw"
echo "6. Verifica: python scripts/wiki_context.py --workspace $WORKSPACE --q 'test'"
