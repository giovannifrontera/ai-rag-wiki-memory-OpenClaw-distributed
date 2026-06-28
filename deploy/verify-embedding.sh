#!/usr/bin/env bash
# Verifica read-only del backend di embedding dopo l'allineamento al branch
# feat/configurable-embedding-backend. NON modifica dati: nessun ingest/rebuild.
#
# Uso:
#   ./deploy/verify-embedding.sh [WORKSPACE]
# WORKSPACE = dir che contiene wiki.config.json (default: ~/.openclaw/workspace)

set -uo pipefail

WORKSPACE="${1:-$HOME/.openclaw/workspace}"
CFG="$WORKSPACE/wiki.config.json"
FAIL=0

note() { printf '  %s\n' "$*"; }
ok()   { printf '✅ %s\n' "$*"; }
ko()   { printf '❌ %s\n' "$*"; FAIL=1; }

echo "== Verifica embedding backend =="
echo "workspace: $WORKSPACE"
echo

# 1. Config presente e leggibile
if [[ ! -f "$CFG" ]]; then
  ko "wiki.config.json non trovato in $WORKSPACE"; exit 1
fi
ok "wiki.config.json trovato"

# Estrai i campi embedding con python (no jq dependency)
read -r BACKEND MODEL DEVICE OLLAMA_HOST QHOST QPORT QCOLL <<EOF
$(python3 - "$CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
e = c.get("embedding", {})
q = c.get("qdrant", {})
print(
    e.get("backend", "sentence-transformers"),
    e.get("model") or c.get("embedding_model", "BAAI/bge-m3"),
    e.get("device", "auto"),
    e.get("ollama_host", "http://localhost:11434"),
    q.get("host", "localhost"),
    q.get("port", 6333),
    q.get("collection", "wiki_pages"),
)
PY
)
EOF
note "backend=$BACKEND model=$MODEL device=$DEVICE"
note "qdrant=$QHOST:$QPORT collection=$QCOLL ollama=$OLLAMA_HOST"
echo

# 2. Qdrant raggiungibile + conteggio punti (i dati in memoria)
PTS=$(curl -s "http://$QHOST:$QPORT/collections/$QCOLL" \
  | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); print(d["result"]["points_count"])
except Exception: print("ERR")' 2>/dev/null)
if [[ "$PTS" =~ ^[0-9]+$ ]]; then
  ok "Qdrant OK — collection '$QCOLL' ha $PTS punti"
  [[ "$PTS" -eq 0 ]] && ko "0 punti: i dati non ci sono! Indaga prima di procedere."
else
  ko "Qdrant non raggiungibile o collection assente ($QHOST:$QPORT/$QCOLL)"
fi
echo

# 3. Se backend=ollama: Ollama raggiungibile e modello presente
if [[ "$BACKEND" == "ollama" ]]; then
  if curl -s "$OLLAMA_HOST/api/tags" | grep -q "$MODEL"; then
    ok "Ollama OK — modello '$MODEL' disponibile"
  else
    ko "Ollama non ha il modello '$MODEL' (controlla: ollama list / ollama pull $MODEL)"
  fi
  # Embedding di prova: deve tornare 1024 dim
  DIM=$(curl -s "$OLLAMA_HOST/api/embeddings" \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"test\"}" \
    | python3 -c 'import sys,json;
try: print(len(json.load(sys.stdin)["embedding"]))
except Exception: print("ERR")' 2>/dev/null)
  if [[ "$DIM" == "1024" ]]; then
    ok "Embedding Ollama OK — $DIM dimensioni (compatibile coi vettori esistenti)"
  else
    ko "Embedding Ollama ha dimensione '$DIM', attese 1024 — vettori incompatibili!"
  fi
  echo
fi

# 4. wiki.py eseguito è quello del repo?
WPATH=$(command -v wiki.py 2>/dev/null && readlink -f "$(command -v wiki.py)" 2>/dev/null)
if [[ -n "$WPATH" ]]; then
  ok "wiki.py nel PATH -> $WPATH"
else
  note "wiki.py non nel PATH (ok se lo lanci con path esplicito)"
fi
echo

# 5. Query end-to-end (read-only): deve dare risultati pertinenti.
# Query generica, sovrascrivibile: VERIFY_QUERY="..." ./verify-embedding.sh
echo "== Query di prova (read-only) =="
QUERY="${VERIFY_QUERY:-test}"
WIKI_CMD=$(command -v wiki.py || echo "python3 $(dirname "$0")/../scripts/wiki.py")
$WIKI_CMD query --workspace "$WORKSPACE" --q "$QUERY" --k 3 2>&1 | head -40
echo

# 6. Conteggio punti DOPO: deve essere identico (nessuna verifica ha scritto dati)
PTS_AFTER=$(curl -s "http://$QHOST:$QPORT/collections/$QCOLL" \
  | python3 -c 'import sys,json;
try: print(json.load(sys.stdin)["result"]["points_count"])
except Exception: print("ERR")' 2>/dev/null)
if [[ "$PTS_AFTER" == "$PTS" ]]; then
  ok "Punti invariati: $PTS_AFTER (nessun dato perso o riscritto)"
else
  ko "Punti cambiati: prima=$PTS dopo=$PTS_AFTER — qualcosa ha scritto su Qdrant!"
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "🎉 Tutte le verifiche passate."
else
  echo "⚠️  Alcune verifiche FALLITE — vedi i ❌ sopra. Non procedere finché non sono risolte."
  exit 1
fi
