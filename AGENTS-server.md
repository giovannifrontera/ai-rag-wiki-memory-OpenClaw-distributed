# AGENTS-server.md — Macchina Server (Bazzite)

> ## ⛔ STOP — LEGGI PRIMA DI QUALSIASI AZIONE
>
> **Ogni sessione, prima di qualsiasi azione:**
> 1. `Read wiki-session.md` nel workspace — controlla lo status
> 2. `Read skills/wiki-core.md` — carica il protocollo completo
> 3. Verifica che Qdrant sia attivo: `curl http://localhost:6333/health`
> 4. Scansiona `wiki/` e `wiki-works/` per file `*.sync-conflict-*` — se trovati, **fermati e avvisa**
>
> Questi sono file locali. Usa il tool **Read**, non una Skill o Tool call.
>
> ---

Questa è la **macchina server**: esegue Qdrant, gestisce il DB vettoriale, ed è il nodo Syncthing primario. I client si connettono a Qdrant via Tailscale.

---

## Stato di salute — controlla prima di ogni sessione

```bash
# Qdrant attivo?
curl http://localhost:6333/health
# Atteso: {"title":"qdrant - vector search engine","version":"..."}

# Collezione presente?
curl http://localhost:6333/collections/wiki_pages
# Atteso: {"result":{"points_count":N,...}}

# Syncthing attivo?
curl http://localhost:8384/rest/system/ping -H "X-API-Key: <tua-api-key>"

# Service Qdrant status
systemctl status qdrant
```

Se Qdrant non risponde:
```bash
sudo systemctl start qdrant
sudo systemctl status qdrant
# Controlla i log se il service non parte
journalctl -u qdrant -n 50
```

---

## Struttura workspace

```
~/.openclaw/workspace/
├── wiki.config.json          ← qdrant.host = "localhost" (server usa localhost)
├── wiki-session.md           ← stato sessione corrente
├── wiki/                     ← livello Distillato + Identity (sync Syncthing)
│   └── identity/             ← solo wiki.py self-reflect scrive qui
├── wiki-works/<topic>/       ← livello Dominio (sync Syncthing)
└── .stignore                 ← regole esclusione Syncthing
```

Il DB vettoriale **non è nel workspace** — vive in Qdrant su `localhost:6333`.

---

## Comandi disponibili

### Ingestione

```bash
# Ingestione standard (da .tmp scritti dall'agente)
python scripts/wiki.py ingest \
    --workspace ~/.openclaw/workspace \
    --pages wiki-works/trading/concetti/nuovo.md.tmp \
    --log "ingest | Nuovo concetto trading"

# Ingestione PDF
python scripts/wiki.py ingest-pdf \
    --workspace ~/.openclaw/workspace \
    --file /path/al/documento.pdf

# Scansione PDF inbox
python scripts/wiki.py scan-inbox --workspace ~/.openclaw/workspace
```

### Query e contesto

```bash
# Ricerca semantica manuale
python scripts/wiki.py query \
    --workspace ~/.openclaw/workspace \
    --q "rituale di purificazione" --k 5

# Iniezione contesto pre-prompt (usata automaticamente dal plugin)
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "domanda utente" --k 3
```

### Manutenzione (preferibilmente su server)

```bash
# Lint — rileva e ripara inconsistenze
python scripts/wiki.py lint --workspace ~/.openclaw/workspace
python scripts/wiki.py lint --workspace ~/.openclaw/workspace --full

# Rebuild — riscrive TUTTO il DB vettoriale da zero (operazione pesante)
# Esegui SOLO su server, mai su client
python scripts/wiki.py rebuild --workspace ~/.openclaw/workspace

# Indice token-budget
python scripts/wiki.py index --workspace ~/.openclaw/workspace
```

### Dashboard web

```bash
python scripts/wiki.py serve \
    --workspace ~/.openclaw/workspace \
    --port 7331 --no-auth
# http://localhost:7331
```

### Self-reflection comportamentale

```bash
# Loggare una correzione utente
python scripts/wiki.py behavior-log \
    --workspace ~/.openclaw/workspace \
    --event "usare sempre il vouv in risposte formali"

# Self-reflect (esegui a fine sessione se ≥1 correzione ricevuta)
python scripts/wiki.py self-reflect --workspace ~/.openclaw/workspace
```

---

## Protocollo conflitti Syncthing

Se trovi file `*.sync-conflict-*` in `wiki/` o `wiki-works/`:

1. **Non procedere** con nessuna operazione wiki
2. Avvisa l'utente: "Conflitto Syncthing trovato: [lista file]. Due istanze hanno scritto la stessa pagina contemporaneamente. Quale versione vuoi tenere?"
3. Mostra il contenuto di entrambi i file
4. Aspetta la decisione dell'utente
5. Dopo la risoluzione: elimina il file scartato, esegui `wiki.py lint`
6. Aggiorna `wiki-session.md` con `status: ok`

Non cancellare mai file di conflitto automaticamente.

---

## Wiki context injection

Ogni prompt arriva preceduto da:

```
<wiki-context>
Contesto wiki pre-caricato (top 3 pagine per rilevanza semantica):
### wiki/concepts/rag.md  [rilevanza: 0.91]
[contenuto pagina...]
</wiki-context>
```

Usa questo direttamente. Non rieseguire `wiki.py query` per lo stesso prompt.
Se tutti i punteggi di rilevanza < 0.4 → il wiki non ha conoscenza rilevante, procedi normalmente.

---

## PDF ingestion — workflow obbligatorio

```bash
python scripts/wiki.py ingest-pdf --workspace <path> --file <path|url>
```

Questo deposita il testo estratto in `wiki-works/<progetto>/raw/`.

**Dopo `ingest-pdf`, l'agente deve:**
1. Leggere ogni file depositato in `raw/`
2. Scrivere pagine `.tmp` strutturate (vedi `skills/wiki-core.md §ingest`)
3. Chiamare `wiki.py ingest --workspace <path> --pages <file.tmp>`

Non usare mai `process-raw` come scorciatoia per il workflow INGEST.

---

## Architettura — tre livelli, un cervello

| Livello | Directory | Contenuti | Chi scrive |
|---------|-----------|-----------|------------|
| **Dominio** | `wiki-works/<topic>/` | Conoscenza profonda per topic | Workflow INGEST |
| **Distillato** | `wiki/` | Conoscenza cross-domain, promossa autonomamente | Agente (autonomo) |
| **Identità** | `wiki/identity/` | Valori, stile, pattern comportamentali | Solo `wiki.py self-reflect` |

Promuovi una pagina da `wiki-works/` a `wiki/` autonomamente quando è rilevante in ≥2 topic e recuperata in ≥3 query.

---

## Comandi disponibili (riferimento completo)

```
wiki.py ingest         --workspace <path> --pages <p1.tmp,...> --log <str>
wiki.py query          --workspace <path> --q <string> [--k 5]
wiki.py lint           --workspace <path> [--full]
wiki.py index          --workspace <path>
wiki.py rebuild        --workspace <path>          ← SOLO su server
wiki.py scan-inbox     --workspace <path>
wiki.py ingest-pdf     --workspace <path> --file <path|url>
wiki.py serve          --workspace <path> [--port 7331] [--no-auth]
wiki.py behavior-log   --workspace <path> --event "<correzione>"
wiki.py self-reflect   --workspace <path>
wiki.py session-update --workspace <path> --op <tipo> --status <ok|failed|...>

wiki_context.py        --workspace <path> --q <string> [--k 3] [--max-chars 600]
migrate_lancedb_to_qdrant.py --lancedb <path> --config <path> [--dry-run]
```
