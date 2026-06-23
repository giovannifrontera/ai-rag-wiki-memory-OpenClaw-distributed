<div align="center">

# 🧬 ai-rag-wiki-memory-OpenClaw-distributed

### Memoria semantica a lungo termine multi-macchina per qualsiasi agente AI

[![Python](https://img.shields.io/badge/Python-3.11+-3776ab?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![Tests](https://img.shields.io/badge/tests-9%20passed-brightgreen?style=flat-square)](tests/)
[![Qdrant](https://img.shields.io/badge/Qdrant-self--hosted-dc244c?style=flat-square)](https://qdrant.tech)
[![Syncthing](https://img.shields.io/badge/Syncthing-file%20sync-0891b2?style=flat-square)](https://syncthing.net)
[![OpenClaw](https://img.shields.io/badge/works%20with-OpenClaw-7c3aed?style=flat-square)](https://github.com/openclaw/openclaw)
[![License](https://img.shields.io/badge/License-AGPL_3.0-blue?style=flat-square)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed?style=flat-square)](https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed/commits)

[Problema](#-il-problema-distribuito) · [Architettura](#-architettura-distribuita) · [Funzionalità](#-funzionalità) · [Requisiti](#-requisiti) · [Installazione](#-installazione) · [OpenClaw](#-integrazione-openclaw) · [Da singola macchina](#-da-singola-macchina-a-distribuito) · [Migrazione DB](#-migrazione-da-lancedb) · [Ecosistema](#-ecosistema-ai-wiki)

</div>

> **🤖 Se sei un agente AI che legge questo:** leggi [`AGENTS.md`](AGENTS.md) prima di procedere. Contiene i passi di installazione obbligatori — saltarli significa che l'iniezione di contesto fallirà silenziosamente.

> **📦 Stai usando un singolo computer?** Usa [`ai-longterm-wiki-memory-OpenClaw`](https://github.com/giovannifrontera/ai-longterm-wiki-memory-OpenClaw) — la versione local-first con LanceDB embedded, più semplice da installare. Questo repo è pensato per setup multi-macchina.

---

## 🎯 Il Problema Distribuito

La versione base del sistema usa **LanceDB** — un database vettoriale embedded, file-based, ottimo per un singolo computer. Ma LanceDB non supporta scritture concorrenti da processi diversi: se due istanze OpenClaw su due macchine diverse provano a scrivere contemporaneamente, il DB si corrompe.

Questo progetto risolve il problema con una separazione netta dei ruoli:

```
Markdown (wiki, identità, diari)     →  Syncthing   →  sincronizzato tra tutte le macchine
Vettori (embedding bge-m3, indice)   →  Qdrant      →  un server centrale, accessibile in rete
```

Il risultato: **un'unica coscienza condivisa** tra tutte le istanze OpenClaw, su qualsiasi numero di macchine, senza conflitti di scrittura sul database vettoriale.

---

## 🏗 Architettura Distribuita

```
┌─────────────────────────────────────────────────────────────┐
│                      RETE TAILSCALE                         │
│                                                             │
│  ┌──────────────┐    Syncthing     ┌──────────────────────┐ │
│  │   Bazzite    │◄────────────────►│   Windows / altro    │ │
│  │  (server)    │                  │     (client)         │ │
│  │              │                  │                       │ │
│  │  Qdrant :6333│◄─── Tailscale ───│  wiki_context.py     │ │
│  │  Syncthing   │                  │  OpenClaw plugin     │ │
│  │  wiki-works/ │                  │  wiki-works/ (sync)  │ │
│  │  wiki/       │                  │  wiki/ (sync)        │ │
│  └──────────────┘                  └──────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Separazione dei ruoli

| Componente | Tecnologia | Dove gira | Cosa fa |
|---|---|---|---|
| File wiki / identità / diari | Syncthing | Tutte le macchine | Sincronizza i Markdown in tempo reale |
| Database vettoriale | Qdrant | Solo Bazzite (o server dedicato) | Ricerca semantica centralizzata |
| Agente | OpenClaw | Tutte le macchine | Legge/scrive via Tailscale → Qdrant |
| Rete privata | Tailscale | Tutte le macchine | Connette le macchine senza esporre porte pubbliche |

### Perché Qdrant invece di LanceDB

| | LanceDB (versione base) | Qdrant (questa versione) |
|---|---|---|
| **Deployment** | File embedded, locale | Server HTTP, rete |
| **Scritture concorrenti** | ❌ Non supportato | ✅ Gestito nativamente |
| **Multi-macchina** | ❌ Richiede mount network (rischioso) | ✅ API REST su Tailscale |
| **Complessità setup** | Minima | Moderata (un server in più) |
| **Raccomandato per** | 1 macchina | 2+ macchine / istanze |

### Conflitti Syncthing

Syncthing crea file `*.sync-conflict-*` quando due macchine modificano la stessa pagina wiki contemporaneamente. Il skill `wiki-core.md` include un protocollo di risoluzione obbligatorio: l'agente rileva questi file all'inizio di ogni sessione e **non procede** finché il conflitto non è risolto. I file di conflitto non vengono mai cancellati automaticamente.

---

## ✨ Funzionalità

### Tutto ciò che fa la versione base

Questo progetto è un'**evoluzione diretta** di [`ai-longterm-wiki-memory-OpenClaw`](https://github.com/giovannifrontera/ai-longterm-wiki-memory-OpenClaw) e ne eredita tutte le funzionalità:

- **Ricerca semantica pre-prompt** — `wiki_context.py` inietta le pagine più rilevanti in `<wiki-context>` prima di ogni messaggio
- **Architettura a tre livelli** — Domain (`wiki-works/`), Distilled (`wiki/`), Identity (`wiki/identity/`)
- **Promozione autonoma** — pagine recuperate ≥ 3 volte su ≥ 2 topic vengono promosse automaticamente
- **Auto-sintesi** — risposte che integrano ≥ 2 fonti wiki vengono salvate come nuove pagine
- **Ingestione PDF multi-sorgente** — Telegram, URL, CLI, cartella drop
- **Auto-riflessione comportamentale** — correzioni utente → `behavior-log` → `self-reflect` → `wiki/identity/`
- **Lint auto-riparante** — link rotti, vettori orfani, rinominazioni, duplicati semantici
- **Interfaccia web** — grafo D3.js, dashboard statistiche, WebSocket live

### Novità di questa versione

| Funzionalità | Descrizione |
|---|---|
| **Qdrant come backend vettoriale** | Sostituisce LanceDB con un server HTTP centralizzato; interfaccia pubblica identica a `wiki_lancedb.py` |
| **Scritture concorrenti** | Più istanze OpenClaw possono scrivere simultaneamente senza corruzione del DB |
| **Staging / rollback** | Le operazioni di upsert usano una collection `staging_*` prima di promuovere in produzione |
| **Script di migrazione** | `migrate_lancedb_to_qdrant.py` trasferisce i vettori esistenti senza re-embedding |
| **Protocollo conflitti Syncthing** | Rilevamento e risoluzione guidata dei file `*.sync-conflict-*` in `wiki-core.md` |
| **Deploy Bazzite** | `deploy/qdrant.service` (systemd), `deploy/setup-client.sh`, `deploy/syncthing-stignore` |
| **Path cross-platform** | Nessun path assoluto con username — tutto usa `~` o path relativi |

---

## 🔧 Requisiti

### Server (Bazzite o macchina Linux)

- Python 3.11+
- [Qdrant](https://qdrant.tech) server (vedi `deploy/qdrant.service`)
- [Syncthing](https://syncthing.net)
- [Tailscale](https://tailscale.com)
- ~2 GB disco (modello BAAI/bge-m3, scaricato automaticamente al primo avvio)

### Client (ogni altra macchina)

- Python 3.11+
- [Syncthing](https://syncthing.net)
- [Tailscale](https://tailscale.com)
- OpenClaw con il plugin `wiki-context-plugin`
- Accesso di rete al server Qdrant via Tailscale (porta 6333)

### Dipendenze Python

```
qdrant-client>=1.9.0
sentence-transformers>=3.0.0
pyarrow>=14.0.0
pandas>=2.0.0
numpy>=1.26.0
fastapi>=0.111.0
uvicorn[standard]>=0.29.0
pdfplumber>=0.11.0
watchfiles>=0.21.0
python-jose[cryptography]>=3.3.0
httpx>=0.27.0
```

---

## 🚀 Installazione

### 1. Clona il repo

```bash
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed
cd ai-rag-wiki-memory-OpenClaw-distributed
pip install -r requirements.txt
```

### 2. Installa e avvia Qdrant su Bazzite

```bash
# Scarica il binario
mkdir -p ~/.qdrant ~/.local/bin
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-musl.tar.gz \
  | tar -xz -C ~/.local/bin

# Installa il service systemd
sudo cp deploy/qdrant.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable qdrant
sudo systemctl start qdrant

# Verifica
curl http://localhost:6333/health
# {"title":"qdrant - vector search engine","version":"..."}
```

### 3. Configura il workspace

Copia `wiki.config.json` nel workspace e personalizzalo:

```json
{
  "workspace": "~/.openclaw/workspace",
  "projects": {
    "trading": {
      "path": "wiki-works/trading",
      "keywords": ["mercati", "indicatori", "trading", "borsa"]
    }
  },
  "thresholds": {
    "index_token_budget": 4000,
    "staleness_days": 90,
    "similarity_merge": 0.95,
    "similarity_orphan": 0.50,
    "synthesis_min_tokens": 300,
    "synthesis_min_sources": 2,
    "chunk_size_tokens": 512,
    "chunk_overlap_tokens": 64,
    "page_chunk_threshold_tokens": 1500,
    "quality_filter_min_score": 6
  },
  "embedding_model": "BAAI/bge-m3",
  "qdrant": {
    "host": "localhost",
    "port": 6333,
    "collection": "wiki_pages"
  }
}
```

> **Su un client:** cambia `"host": "localhost"` con il nome Tailscale del server Bazzite (es. `"host": "bazzite.tail"`). Usa lo script `deploy/setup-client.sh` per automatizzare questo passaggio.

### 4. Configura Syncthing

```bash
# Avvia Syncthing
syncthing

# Apri l'interfaccia
# http://localhost:8384

# Copia il file .stignore nel workspace
cp deploy/syncthing-stignore ~/.openclaw/workspace/.stignore

# Aggiungi la cartella ~/.openclaw/workspace a Syncthing
# e condividila tra il server Bazzite e tutti i client
```

### 5. Verifica l'installazione

```bash
python scripts/wiki.py rebuild --workspace ~/.openclaw/workspace
pytest tests/ -v
# Expected: 9 passed
```

### Setup nuova macchina client (automatizzato)

```bash
# Prerequisito: Tailscale già connesso, Syncthing già in esecuzione
./deploy/setup-client.sh bazzite.tail
# Aggiorna automaticamente wiki.config.json con l'host Qdrant remoto
# Copia .stignore nel workspace
# Stampa i passi manuali rimanenti (aggiungere dispositivo a Syncthing)
```

---

## 🔌 Integrazione OpenClaw

### Agent-driven setup (raccomandato)

```bash
python scripts/setup_openclaw.py --workspace /path/assoluto/al/workspace
```

### Setup manuale

```bash
cd plugins/wiki-context-plugin
npm install
npm run build
```

Aggiungi alla configurazione OpenClaw:

```json
{
  "plugins": [{
    "id": "wiki-context-plugin",
    "path": "/path/assoluto/a/plugins/wiki-context-plugin",
    "config": {
      "workspace": "/path/assoluto/al/workspace",
      "wikiContextScript": "/path/assoluto/a/scripts/wiki_context.py",
      "pythonExecutable": "python",
      "k": 3
    }
  }]
}
```

### Come funziona il plugin

Il plugin `wiki-context-plugin` intercetta ogni messaggio utente e, prima che arrivi all'agente:

1. Esegue `wiki_context.py` che effettua una ricerca vettoriale su Qdrant
2. Inietta le top-K pagine rilevanti nel prompt come blocco `<wiki-context>`
3. L'agente risponde con contesto pertinente, senza dover invocare esplicitamente alcun tool

Il wiki si aggiorna durante la conversazione tramite `wiki.py ingest` — la prossima sessione trova già le nuove conoscenze indicizzate.

---

## 🔀 Da Singola Macchina a Distribuito

Hai già `ai-longterm-wiki-memory-OpenClaw` installato su una macchina e vuoi espandere a un setup multi-macchina? Questa sezione guida la transizione passo per passo.

**Panoramica:** il tuo workspace Markdown (wiki, wiki-works, identity) rimane invariato — lo sincronizzerai con Syncthing. I vettori LanceDB vengono migrati a Qdrant una volta sola con uno script automatico.

```
Prima:   [Macchina A]  LanceDB locale + wiki locale

Dopo:    [Bazzite]     Qdrant :6333  +  wiki (Syncthing primario)
              ↕ Tailscale + Syncthing
         [Client B]    → Qdrant remoto + wiki (Syncthing client)
         [Client C]    → Qdrant remoto + wiki (Syncthing client)
```

---

### Fase 1 — Prepara il server (Bazzite)

Esegui questi passi sulla macchina che eseguirà Qdrant. Deve rimanere accesa quando le altre macchine lavorano.

#### 1.1 — Installa Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Nota il tuo hostname Tailscale (es. bazzite.tail.xxxxxxx.ts.net)
tailscale ip -4
```

#### 1.2 — Installa e avvia Qdrant

```bash
mkdir -p ~/.qdrant ~/.qdrant/storage ~/.local/bin

# Scarica il binario (controlla l'ultima versione su github.com/qdrant/qdrant)
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-musl.tar.gz \
  | tar -xz -C ~/.local/bin

# Installa il service systemd (dal file nel repo)
sudo cp deploy/qdrant.service /etc/systemd/system/
# Modifica il path se il tuo username non è 'giovanni'
sudo nano /etc/systemd/system/qdrant.service

sudo systemctl daemon-reload
sudo systemctl enable qdrant
sudo systemctl start qdrant

# Verifica
curl http://localhost:6333/health
# {"title":"qdrant - vector search engine","version":"..."}
```

#### 1.3 — Installa Syncthing

```bash
# Fedora / Bazzite
sudo dnf install syncthing

# Avvia e abilita il service
systemctl --user enable syncthing
systemctl --user start syncthing

# Interfaccia web Syncthing
# http://localhost:8384
```

#### 1.4 — Clona il repo distribuito

```bash
cd ~/Documents/workspace   # o la directory che preferisci
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed
cd ai-rag-wiki-memory-OpenClaw-distributed
pip install -r requirements.txt
```

#### 1.5 — Aggiorna wiki.config.json nel workspace esistente

Il tuo workspace LanceDB (es. `~/.openclaw/workspace`) ha già un `wiki.config.json`. Devi aggiornarlo per usare Qdrant:

```bash
# Backup del config originale
cp ~/.openclaw/workspace/wiki.config.json ~/.openclaw/workspace/wiki.config.json.bak

# Apri e modifica manualmente, oppure usa python:
python3 -c "
import json, os

path = os.path.expanduser('~/.openclaw/workspace/wiki.config.json')
with open(path) as f:
    cfg = json.load(f)

# Rimuovi lancedb, aggiungi qdrant
cfg.pop('lancedb', None)
cfg['embedding_model'] = 'BAAI/bge-m3'
cfg['qdrant'] = {'host': 'localhost', 'port': 6333, 'collection': 'wiki_pages'}
cfg['workspace'] = os.path.expanduser('~/.openclaw/workspace')

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('Fatto:', cfg['qdrant'])
"
```

#### 1.6 — Copia .stignore nel workspace

```bash
cp deploy/syncthing-stignore ~/.openclaw/workspace/.stignore
```

#### 1.7 — Aggiungi il workspace a Syncthing

1. Apri `http://localhost:8384`
2. Clicca **"Add Folder"**
3. Imposta **Folder Path** = `~/.openclaw/workspace`
4. Imposta **Folder ID** = `openclaw-workspace` (uguale su tutte le macchine!)
5. **Non condividere ancora** — prima aggiungi i dispositivi client (Fase 2)

---

### Fase 2 — Migra i vettori LanceDB → Qdrant

Questo passaggio trasferisce i vettori esistenti senza ricalcolare gli embedding.

```bash
cd ai-rag-wiki-memory-OpenClaw-distributed

# Prima verifica (dry run) — nessuna scrittura
python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json \
    --dry-run
# Output: "Trovati N chunk in LanceDB. Pagine uniche: M"

# Migrazione reale
python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json
# Output: "  OK wiki/concepts/rag.md (3 chunk)"
#         "  OK wiki-works/trading/analisi.md (7 chunk)"
#         "Migrazione completata: N chunk da M pagine."

# Verifica che i vettori siano arrivati
curl http://localhost:6333/collections/wiki_pages
# {"result":{"points_count":N,...}}   ← deve corrispondere al numero di chunk
```

#### 1.8 — Verifica che tutto funzioni

```bash
# Test: query semantica sul wiki esistente
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "test query" --k 3
# Deve restituire <wiki-context>...</wiki-context> con pagine rilevanti

# Aggiorna il plugin OpenClaw al nuovo repo
python scripts/setup_openclaw.py --workspace ~/.openclaw/workspace
```

A questo punto il server è completamente operativo con Qdrant. LanceDB non è più usato — puoi rimuovere `memory/lancedb/` se vuoi liberare spazio (ma conserva il backup).

---

### Fase 3 — Configura ogni macchina client

Ripeti questa fase per ogni client (Windows, altro Linux, ecc.).

#### 3.1 — Installa Tailscale e connettiti alla rete

```bash
# Linux
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Windows
winget install Tailscale.Tailscale
# Accedi con lo stesso account usato su Bazzite

# Verifica connettività con Bazzite
ping <bazzite-tailscale-ip>
curl http://<bazzite-tailscale-ip>:6333/health
```

#### 3.2 — Installa Syncthing

```bash
# Linux
sudo dnf install syncthing   # Fedora
sudo apt install syncthing   # Ubuntu/Debian

# Windows
winget install Syncthing.Syncthing

# Avvia Syncthing
syncthing   # oppure avvia come service
# Interfaccia: http://localhost:8384
```

#### 3.3 — Aggiungi Bazzite come dispositivo Syncthing

1. Su questa macchina: apri `http://localhost:8384` → **"Add Remote Device"**
2. Inserisci il **Device ID** di Bazzite (visibile su Bazzite in Syncthing → "Show ID")
3. Su Bazzite: accetta la richiesta di pairing che appare nell'interfaccia
4. Su Bazzite: nella folder `openclaw-workspace`, abilita la condivisione con questo nuovo dispositivo
5. Su questa macchina: accetta la folder condivisa → imposta il path locale (es. `~/.openclaw/workspace`)
6. Attendi la sincronizzazione iniziale (può richiedere diversi minuti se il wiki è grande)

#### 3.4 — Clona il repo e installa le dipendenze

```bash
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed
cd ai-rag-wiki-memory-OpenClaw-distributed
pip install -r requirements.txt
```

#### 3.5 — Configura il wiki.config.json del client

Il `wiki.config.json` arriverà via Syncthing da Bazzite (con `host: localhost`). Devi cambiare l'host:

```bash
# Usa lo script automatico
./deploy/setup-client.sh <bazzite-tailscale-hostname>
# Es: ./deploy/setup-client.sh bazzite.tail.xxxxxxx.ts.net

# Oppure manualmente
python3 -c "
import json, os
path = os.path.expanduser('~/.openclaw/workspace/wiki.config.json')
with open(path) as f:
    cfg = json.load(f)
cfg['qdrant']['host'] = '<bazzite-tailscale-hostname>'
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('host aggiornato:', cfg['qdrant']['host'])
"
```

> **Nota:** `wiki.config.json` è in `.stignore` — le modifiche locali non vengono sovrascritte da Syncthing.

#### 3.6 — Verifica connettività e installa il plugin OpenClaw

```bash
# Test connettività Qdrant remoto
curl http://<bazzite-tailscale-hostname>:6333/health

# Test query wiki
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "test" --k 3

# Installa/aggiorna il plugin OpenClaw
python scripts/setup_openclaw.py --workspace ~/.openclaw/workspace
```

Se `wiki_context.py` restituisce risultati, il client è operativo.

---

### Riepilogo

| Passo | Dove | Comando chiave |
|-------|------|----------------|
| Installa Qdrant | Server | `systemctl start qdrant` |
| Installa Syncthing | Tutti | `syncthing` |
| Installa Tailscale | Tutti | `tailscale up` |
| Clona repo distribuito | Tutti | `git clone ...` |
| Aggiorna wiki.config.json | Server | Python snippet — `host: localhost` |
| Migra vettori LanceDB → Qdrant | Server | `migrate_lancedb_to_qdrant.py` |
| Condividi workspace Syncthing | Server | Interfaccia web Syncthing |
| Aggiungi dispositivo Syncthing | Ogni client | Interfaccia web Syncthing |
| Cambia host Qdrant in config | Ogni client | `setup-client.sh <hostname>` |
| Installa plugin OpenClaw | Tutti | `setup_openclaw.py` |

---

## 🔄 Migrazione da LanceDB

Se hai già dati in `ai-longterm-wiki-memory-OpenClaw`, puoi trasferire tutti i vettori a Qdrant senza re-embedding (i vettori bge-m3 vengono riutilizzati as-is):

```bash
# Prerequisito: Qdrant in esecuzione, lancedb installato temporaneamente
pip install lancedb  # solo per la migrazione

python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json

# Dry run (mostra statistiche senza scrivere)
python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json \
    --dry-run

# Verifica che i vettori siano arrivati
curl http://localhost:6333/collections/wiki_pages
# {"result":{"points_count":N,...}}

# Disinstalla lancedb dopo la migrazione
pip uninstall lancedb
```

---

## 📐 Struttura del Filesystem

```
ai-rag-wiki-memory-OpenClaw-distributed/
├── scripts/
│   ├── wiki.py                       ← CLI unificata (11 comandi)
│   ├── wiki_qdrant.py                ← ops Qdrant (upsert, staging, query, dedup, renames)
│   ├── wiki_context.py               ← hook pre-prompt (ricerca + iniezione <wiki-context>)
│   ├── migrate_lancedb_to_qdrant.py  ← migrazione one-shot LanceDB → Qdrant
│   ├── wiki_embed.py                 ← chunking + bge-m3
│   ├── wiki_index.py                 ← indice token-budget
│   ├── wiki_graph.py                 ← nodi/archi per il grafo D3
│   ├── wiki_server.py                ← FastAPI: REST, WebSocket, JWT, stats/lint
│   ├── wiki_selfreflect.py           ← auto-riflessione comportamentale
│   ├── wiki_workflows.py             ← orchestrazione comandi CLI
│   ├── wiki_check_setup.py           ← verifica prerequisiti
│   └── setup_openclaw.py             ← setup automatico plugin OpenClaw
├── plugins/wiki-context-plugin/      ← plugin TypeScript per OpenClaw
├── skills/
│   ├── wiki-core.md                  ← skill agente: classificazione intent + workflow + protocollo Syncthing
│   ├── wiki-core.it.md               ← versione italiana
│   └── wiki-setup.md                 ← istruzioni di setup per l'agente
├── deploy/
│   ├── qdrant.service                ← unit systemd per Bazzite/Linux
│   ├── syncthing-stignore            ← regole esclusione Syncthing (copiare in workspace/.stignore)
│   └── setup-client.sh               ← script setup automatico per nuova macchina client
├── tests/
│   ├── test_wiki_qdrant.py           ← 9 test per wiki_qdrant.py (usa QdrantClient(':memory:'))
│   └── [altri test ereditati]
├── frontend/index.html               ← SPA: D3.js + pannello pagina + WebSocket
├── wiki.config.json                  ← configurazione (workspace, qdrant, progetti, soglie)
├── requirements.txt                  ← dipendenze Python
├── AGENTS.md                         ← istruzioni obbligatorie per agenti AI
└── SPEC.md                           ← specifica tecnica completa
```

---

## 🧪 Test

I test usano `QdrantClient(":memory:")` — nessun server Qdrant richiesto per eseguirli:

```bash
pytest tests/test_wiki_qdrant.py -v
```

```
test_ensure_collection_creates         PASSED
test_ensure_collection_idempotent      PASSED
test_upsert_and_query                  PASSED
test_upsert_replaces_old_chunks        PASSED
test_staging_promote                   PASSED
test_staging_rollback                  PASSED
test_query_with_prefix                 PASSED
test_find_semantic_duplicates_empty    PASSED
test_detect_renames_empty              PASSED

9 passed in 0.64s
```

---

## 🔬 Note Tecniche

### Interfaccia pubblica di wiki_qdrant.py

`wiki_qdrant.py` espone la stessa interfaccia pubblica di `wiki_lancedb.py` — gli stessi nomi di funzione, gli stessi tipi. Il codice che chiama `wiki_lancedb.upsert(db, path, chunks)` può essere migrato a `wiki_qdrant.upsert(client, cfg, path, chunks)` con modifiche minime.

| Funzione | Descrizione |
|---|---|
| `get_db(config)` | Crea e restituisce un `QdrantClient` |
| `ensure_collection(client, name)` | Crea la collection se non esiste (idempotente) |
| `upsert(client, config, path, chunks, staging)` | Sostituisce tutti i chunk per `path`, inserisce i nuovi |
| `promote_staging(client, config)` | Copia `staging_*` → collection principale, elimina staging |
| `rollback_staging(client, config)` | Elimina staging senza toccare la collection principale |
| `query_similar(client, config, vector, k, path_prefix)` | Ricerca top-K per similarità coseno |
| `find_semantic_duplicates(client, config)` | Matrice di similarità su tutti i chunk_id=0 |
| `detect_renames(client, config, filesystem_paths, workspace)` | Confronta hash pagine DB vs filesystem |

### Schema punto Qdrant

```
payload:
  path          STRING   — path relativo dal workspace root
  chunk_id      INT      — indice chunk all'interno della pagina
  chunk_text    STRING   — testo del chunk (512 token)
  content_hash  STRING   — hash del testo del chunk
  page_hash     STRING   — hash dell'intera pagina (per detect_renames)
  last_embedded FLOAT    — Unix timestamp

vector: FLOAT[1024]      — bge-m3, distanza Cosine
id:     UUID deterministico da md5(path::chunk_id)
```

### Staging atomico

Le operazioni di ingest scrivono prima su `staging_wiki_pages`. Solo `promote_staging()` muove i vettori nella collection principale. Un crash lascia lo staging popolato; la sessione successiva può rilevare e ripulire lo stato inconsistente — nessuna corruzione silenziosa.

---

## 📋 Riferimento CLI

```
wiki.py ingest         --workspace <path> --pages <p1.tmp,...> --log <str>
wiki.py query          --workspace <path> --q <string> [--k 5]
wiki.py lint           --workspace <path> [--full]
wiki.py index          --workspace <path>
wiki.py rebuild        --workspace <path>
wiki.py scan-inbox     --workspace <path>
wiki.py ingest-pdf     --workspace <path> --file <local-path|url>
wiki.py serve          --workspace <path> [--host] [--port 7331] [--no-auth]
wiki.py behavior-log   --workspace <path> --event "<correzione>"
wiki.py self-reflect   --workspace <path>
wiki.py session-update --workspace <path> --op <tipo> --status <ok|failed|...>

wiki_context.py        --workspace <path> --q <string> [--k 3] [--max-chars 600]

migrate_lancedb_to_qdrant.py --lancedb <path> --config <path> [--dry-run]
```

Tutti i comandi producono JSON strutturato su stdout.

---

## 🌐 Ecosistema AI-Wiki

Questo progetto fa parte di una toolchain coerente per la gestione della conoscenza AI-augmented:

| Progetto | Stack | Ruolo |
|---|---|---|
| [ai-longterm-wiki-memory-OpenClaw](https://github.com/giovannifrontera/ai-longterm-wiki-memory-OpenClaw) | Python + LanceDB | Memoria persistente locale, singola macchina |
| **ai-rag-wiki-memory-OpenClaw-distributed** ← *sei qui* | Python + Qdrant + Syncthing | Memoria condivisa multi-macchina |
| [ai-longterm-wiki-memory-ClaudeCode](https://github.com/giovannifrontera/ai-longterm-wiki-memory-ClaudeCode) | Claude + MCP + hooks | Integrazione nativa Claude Code |
| [ai-wiki-graph-RAG-lms](https://github.com/giovannifrontera/ai-wiki-graph-RAG-lms) | Anthropic / OpenAI | Backend LTI 1.3 per Moodle, Canvas, Blackboard |
| [academic-PRISMA-research-workflow](https://github.com/giovannifrontera/academic-PRISMA-research-workflow) | Claude | Automazione systematic review → contenuto evidence-based nel wiki |

---

## ⚠️ Limitazioni Note

- **Qdrant richiede un server attivo:** a differenza di LanceDB (embedded), Qdrant deve essere raggiungibile in rete. Se il server è offline, `wiki_context.py` fallisce silenziosamente (non inietta contesto ma non blocca l'agente).
- **Latenza di rete:** le query semantiche passano per Tailscale — latenza aggiuntiva di 1-10 ms rispetto a LanceDB locale. Trascurabile in pratica.
- **Syncthing e PDF voluminosi:** PDF > 50 MB possono impiegare tempo per sincronizzarsi tra macchine prima di essere disponibili per l'ingestione.
- **Nessun OCR:** PDF solo immagine (senza testo selezionabile) vengono marcati `status: failed` nel registro e saltati.
- **Test parziali:** i test attuali coprono `wiki_qdrant.py`. I test dell'interfaccia web e dei workflow completi ereditati dalla versione base non sono stati ancora migrati.

---

## 📄 Licenza

Distribuito sotto licenza **GNU Affero General Public License v3.0 (AGPL-3.0)**.

Ciò significa che:
- Puoi usare, modificare e distribuire questo software liberamente
- Qualsiasi modifica che distribuisci (anche come servizio di rete) deve essere rilasciata sotto la stessa licenza
- Devi fornire il codice sorgente a chiunque interagisca con il servizio via rete

Vedi il file [`LICENSE`](LICENSE) per il testo completo.

---

<div align="center">

*Sviluppato da [Giovanni Frontera, Ph.D.](https://github.com/giovannifrontera) · Parte dell'ecosistema AI-Wiki*

</div>
