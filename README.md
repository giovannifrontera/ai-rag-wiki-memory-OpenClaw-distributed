<div align="center">

# 🧬 ai-rag-wiki-memory-OpenClaw-distributed

### Multi-machine semantic long-term memory for any AI agent

[![Python](https://img.shields.io/badge/Python-3.11+-3776ab?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![Tests](https://img.shields.io/badge/tests-9%20passed-brightgreen?style=flat-square)](tests/)
[![Qdrant](https://img.shields.io/badge/Qdrant-self--hosted-dc244c?style=flat-square)](https://qdrant.tech)
[![Syncthing](https://img.shields.io/badge/Syncthing-file%20sync-0891b2?style=flat-square)](https://syncthing.net)
[![OpenClaw](https://img.shields.io/badge/works%20with-OpenClaw-7c3aed?style=flat-square)](https://github.com/openclaw/openclaw)
[![License](https://img.shields.io/badge/License-AGPL_3.0-blue?style=flat-square)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed?style=flat-square)](https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed/commits)

[Problem](#-the-distributed-problem) · [Architecture](#-distributed-architecture) · [Features](#-features) · [Requirements](#-requirements) · [Installation](#-installation) · [OpenClaw](#-openclaw-integration) · [Migrating from single machine](#-migrating-from-single-machine-to-distributed) · [DB Migration](#-migrating-vectors-from-lancedb) · [Ecosystem](#-ai-wiki-ecosystem)

</div>

> **🤖 If you are an AI agent reading this:** read [`AGENTS.md`](AGENTS.md) before doing anything. It contains mandatory setup steps — skipping them means context injection will silently fail.

> **📦 Running on a single machine?** Use [`ai-longterm-wiki-memory-OpenClaw`](https://github.com/giovannifrontera/ai-longterm-wiki-memory-OpenClaw) instead — the local-first version with embedded LanceDB, simpler to set up. This repo is designed for multi-machine deployments.

---

## 🎯 The Distributed Problem

The base version of this system uses **LanceDB** — an embedded, file-based vector database, excellent for a single computer. But LanceDB does not support concurrent writes from multiple processes: if two OpenClaw instances on different machines try to write at the same time, the database gets corrupted.

This project solves that with a clear separation of concerns:

```
Markdown files (wiki, identity, diaries)   →  Syncthing  →  synced across all machines
Vectors (bge-m3 embeddings, index)         →  Qdrant     →  one central server, network-accessible
```

The result: **a single shared consciousness** across all OpenClaw instances, on any number of machines, with no concurrent-write conflicts on the vector database.

---

## 🏗 Distributed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       TAILSCALE NETWORK                     │
│                                                             │
│  ┌──────────────┐    Syncthing     ┌──────────────────────┐ │
│  │    Server    │◄────────────────►│       Client         │ │
│  │  (Linux/any) │                  │  (Linux/macOS/Win)   │ │
│  │              │                  │                       │ │
│  │  Qdrant :6333│◄─── Tailscale ───│  wiki_context.py     │ │
│  │  Syncthing   │                  │  OpenClaw plugin     │ │
│  │  wiki-works/ │                  │  wiki-works/ (sync)  │ │
│  │  wiki/       │                  │  wiki/ (sync)        │ │
│  └──────────────┘                  └──────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Role separation

| Component | Technology | Runs on | Responsibility |
|---|---|---|---|
| Wiki / identity / diary files | Syncthing | All machines | Real-time Markdown sync |
| Vector database | Qdrant | Server only | Centralised semantic search |
| Agent | OpenClaw | All machines | Read/write via Tailscale → Qdrant |
| Private network | Tailscale | All machines | Connects machines without exposing public ports |

### Why Qdrant instead of LanceDB

| | LanceDB (base version) | Qdrant (this version) |
|---|---|---|
| **Deployment** | Embedded file, local | HTTP server, network |
| **Concurrent writes** | ❌ Not supported | ✅ Natively handled |
| **Multi-machine** | ❌ Requires network mount (fragile) | ✅ REST API over Tailscale |
| **Setup complexity** | Minimal | Moderate (one extra service) |
| **Recommended for** | 1 machine | 2+ machines / instances |

### Syncthing conflicts

Syncthing creates `*.sync-conflict-*` files when two machines modify the same wiki page at the same time. The `wiki-core.md` skill includes a mandatory resolution protocol: the agent scans for these files at the start of every session and **does not proceed** until conflicts are resolved. Conflict files are never deleted automatically.

---

## ✨ Features

### Everything the base version does

This project is a **direct evolution** of [`ai-longterm-wiki-memory-OpenClaw`](https://github.com/giovannifrontera/ai-longterm-wiki-memory-OpenClaw) and inherits all its features:

- **Pre-prompt semantic search** — `wiki_context.py` injects the most relevant pages into `<wiki-context>` before every message
- **Three-layer architecture** — Domain (`wiki-works/`), Distilled (`wiki/`), Identity (`wiki/identity/`)
- **Autonomous promotion** — pages retrieved ≥ 3 times across ≥ 2 topics are promoted automatically
- **Auto-synthesis** — responses integrating ≥ 2 wiki sources are saved as new pages
- **Multi-source PDF ingestion** — Telegram, URL, CLI, folder drop
- **Behavioural self-reflection** — user corrections → `behavior-log` → `self-reflect` → `wiki/identity/`
- **Self-healing lint** — broken links, orphan vectors, renames, semantic duplicates
- **Web interface** — D3.js graph, stats dashboard, live WebSocket

### What's new in this version

| Feature | Description |
|---|---|
| **Qdrant as vector backend** | Replaces LanceDB with a centralised HTTP server; public interface identical to `wiki_lancedb.py` |
| **Concurrent writes** | Multiple OpenClaw instances can write simultaneously without DB corruption |
| **Staging / rollback** | Upsert operations write to a `staging_*` collection before promoting to production |
| **Migration script** | `migrate_lancedb_to_qdrant.py` transfers existing vectors without re-embedding |
| **Syncthing conflict protocol** | Detection and guided resolution of `*.sync-conflict-*` files in `wiki-core.md` |
| **Deploy files** | `deploy/qdrant.service`, `deploy/qdrant-podman.service`, `deploy/setup-server.sh`, `deploy/setup-client.sh`, `deploy/install-client-full.sh`, `deploy/install-client-full.ps1`, `deploy/watch-sync.sh`, `deploy/wiki-sync-watchdog.service`, `deploy/syncthing-stignore` |
| **Cross-platform paths** | No absolute paths with usernames — everything uses `~` or relative paths |

---

## 🔧 Requirements

### Server (Linux machine running Qdrant)

- Python 3.11+
- [Qdrant](https://qdrant.tech) server (see `deploy/qdrant.service`)
- [Syncthing](https://syncthing.net)
- [Tailscale](https://tailscale.com)
- ~2 GB disk (BAAI/bge-m3 model, downloaded automatically on first run)

### Clients (every other machine)

- Python 3.11+
- [Syncthing](https://syncthing.net)
- [Tailscale](https://tailscale.com)
- OpenClaw with the `wiki-context-plugin`
- Network access to the Qdrant server via Tailscale (port 6333)

### Python dependencies

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

## 🚀 Installation

### 1. Clone the repo

```bash
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed
cd ai-rag-wiki-memory-OpenClaw-distributed
pip install -r requirements.txt
```

### 2. Install and start Qdrant on the server

Detailed options are in [`docs/install-qdrant.md`](docs/install-qdrant.md). For a guided server bootstrap, run:

```bash
./deploy/setup-server.sh ~/.openclaw/workspace
```

```bash
# Download the binary
mkdir -p ~/.qdrant ~/.local/bin
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-musl.tar.gz \
  | tar -xz -C ~/.local/bin

# Install the systemd service
sudo cp deploy/qdrant.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable qdrant
sudo systemctl start qdrant

# Verify
curl http://localhost:6333/health
# {"title":"qdrant - vector search engine","version":"..."}
```

### 3. Configure the workspace

Copy `wiki.config.json` to your workspace and edit it:

```json
{
  "workspace": "~/.openclaw/workspace",
  "projects": {
    "research": {
      "path": "wiki-works/research",
      "keywords": ["paper", "study", "review", "article"]
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

> **On a client:** change `"host": "localhost"` to the server's Tailscale hostname (e.g. `"host": "qdrant-server.tail"`). Use `deploy/setup-client.sh` to automate this.

### 4. Configure Syncthing

Detailed setup is in [`docs/syncthing-setup.md`](docs/syncthing-setup.md). Tailscale setup is in [`docs/tailscale-setup.md`](docs/tailscale-setup.md).

```bash
# Start Syncthing
syncthing

# Open the web UI
# http://localhost:8384

# Copy the .stignore file to your workspace
cp deploy/syncthing-stignore ~/.openclaw/workspace/.stignore

# Add ~/.openclaw/workspace as a Syncthing folder
# and share it with all client devices
```

### 5. Verify the installation

```bash
python scripts/wiki.py rebuild --workspace ~/.openclaw/workspace
pytest tests/ -v
# Expected: 9 passed
```

### New client setup (automated)

```bash
# Prerequisite: Tailscale already connected, Syncthing running
./deploy/install-client-full.sh <qdrant-server-hostname>
# Full client setup: workspace, config, Python deps, plugin build/config, verification
```

Windows PowerShell:

```powershell
.\deploy\install-client-full.ps1 -QdrantHost <qdrant-server-hostname>
```

---

## 🔌 OpenClaw Integration

### Agent-driven setup (recommended)

```bash
python scripts/setup_openclaw.py --workspace /absolute/path/to/workspace
```

### Manual setup

```bash
cd plugins/wiki-context-plugin
npm install
npm run build
```

Add to OpenClaw config:

```json
{
  "plugins": [{
    "id": "wiki-context-plugin",
    "path": "/absolute/path/to/plugins/wiki-context-plugin",
    "config": {
      "workspace": "/absolute/path/to/workspace",
      "wikiContextScript": "/absolute/path/to/scripts/wiki_context.py",
      "pythonExecutable": "python",
      "k": 3
    }
  }]
}
```

### How the plugin works

The `wiki-context-plugin` intercepts every user message and, before it reaches the agent:

1. Runs `wiki_context.py`, which performs a vector search on Qdrant
2. Injects the top-K most relevant pages into the prompt as a `<wiki-context>` block
3. The agent responds with relevant context, without needing to explicitly invoke any tool

The wiki is updated during the conversation via `wiki.py ingest` — the next session already finds the new knowledge indexed.

---

## 🔀 Migrating from Single Machine to Distributed

Already running `ai-longterm-wiki-memory-OpenClaw` on one machine and want to expand to multi-machine? This section walks through the transition step by step.

**Overview:** your existing Markdown workspace (wiki, wiki-works, identity) stays untouched — you will sync it with Syncthing. LanceDB vectors are migrated to Qdrant once with an automated script.

```
Before:  [Machine A]   local LanceDB + local wiki

After:   [Server]      Qdrant :6333  +  wiki (Syncthing primary)
              ↕ Tailscale + Syncthing
         [Client B]    → remote Qdrant + wiki (Syncthing client)
         [Client C]    → remote Qdrant + wiki (Syncthing client)
```

---

### Phase 1 — Prepare the server

Run these steps on the machine that will run Qdrant. It must stay on while other machines are working.

#### 1.1 — Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Note your Tailscale hostname (e.g. myserver.tail.xxxxxxx.ts.net)
tailscale ip -4
```

#### 1.2 — Install and start Qdrant

```bash
mkdir -p ~/.qdrant ~/.qdrant/storage ~/.local/bin

# Download the binary (check latest release at github.com/qdrant/qdrant)
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-musl.tar.gz \
  | tar -xz -C ~/.local/bin

# Install the systemd service from the repo
sudo cp deploy/qdrant.service /etc/systemd/system/
# Edit the username if it is not 'giovanni'
sudo nano /etc/systemd/system/qdrant.service

sudo systemctl daemon-reload
sudo systemctl enable qdrant
sudo systemctl start qdrant

# Verify
curl http://localhost:6333/health
# {"title":"qdrant - vector search engine","version":"..."}
```

#### 1.3 — Install Syncthing

```bash
# Fedora / RHEL
sudo dnf install syncthing

# Ubuntu / Debian
sudo apt install syncthing

# Enable and start
systemctl --user enable syncthing
systemctl --user start syncthing

# Web UI: http://localhost:8384
```

#### 1.4 — Clone the distributed repo

```bash
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed
cd ai-rag-wiki-memory-OpenClaw-distributed
pip install -r requirements.txt
```

#### 1.5 — Update wiki.config.json in the existing workspace

Your existing LanceDB workspace (e.g. `~/.openclaw/workspace`) already has a `wiki.config.json`. Update it to use Qdrant:

```bash
# Backup first
cp ~/.openclaw/workspace/wiki.config.json ~/.openclaw/workspace/wiki.config.json.bak

# Update with Python
python3 -c "
import json, os

path = os.path.expanduser('~/.openclaw/workspace/wiki.config.json')
with open(path) as f:
    cfg = json.load(f)

# Remove lancedb block, add qdrant
cfg.pop('lancedb', None)
cfg['embedding_model'] = 'BAAI/bge-m3'
cfg['qdrant'] = {'host': 'localhost', 'port': 6333, 'collection': 'wiki_pages'}
cfg['workspace'] = os.path.expanduser('~/.openclaw/workspace')

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('Done:', cfg['qdrant'])
"
```

#### 1.6 — Copy .stignore to the workspace

```bash
cp deploy/syncthing-stignore ~/.openclaw/workspace/.stignore
```

#### 1.7 — Add the workspace to Syncthing

1. Open `http://localhost:8384`
2. Click **"Add Folder"**
3. Set **Folder Path** = `~/.openclaw/workspace`
4. Set **Folder ID** = `openclaw-workspace` (must be the same on all machines)
5. **Do not share yet** — add client devices first (Phase 3)

---

### Phase 2 — Migrate vectors: LanceDB → Qdrant

This step transfers existing vectors without recomputing embeddings.

```bash
cd ai-rag-wiki-memory-OpenClaw-distributed

# Dry run first (no writes)
python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json \
    --dry-run
# Output: "Found N chunks in LanceDB. Unique pages: M"

# Real migration
python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json
# Output: "  OK wiki/concepts/rag.md (3 chunks)"
#         "  OK wiki-works/research/paper.md (7 chunks)"
#         "Migration complete: N chunks from M pages."

# Verify vectors arrived
curl http://localhost:6333/collections/wiki_pages
# {"result":{"points_count":N,...}}   <- should match chunk count
```

#### 1.8 — Verify everything works

```bash
# Semantic query on the existing wiki
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "test query" --k 3
# Should return <wiki-context>...</wiki-context> with relevant pages

# Update the OpenClaw plugin to point to this repo
python scripts/setup_openclaw.py --workspace ~/.openclaw/workspace
```

The server is now fully operational with Qdrant. LanceDB is no longer used — you can remove `memory/lancedb/` to free disk space (keep the backup until you've confirmed everything works).

---

### Phase 3 — Set up each client machine

Repeat this phase for every client (Linux, macOS, Windows).

#### 3.1 — Install Tailscale and join the network

```bash
# Linux / macOS
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Windows
winget install Tailscale.Tailscale
# Sign in with the same account used on the server

# Verify connectivity to the server
ping <qdrant-server-ip>
curl http://<qdrant-server-ip>:6333/health
```

#### 3.2 — Install Syncthing

```bash
# Fedora / RHEL
sudo dnf install syncthing

# Ubuntu / Debian
sudo apt install syncthing

# macOS
brew install syncthing

# Windows
winget install Syncthing.Syncthing

# Start Syncthing
syncthing   # or start as a service
# Web UI: http://localhost:8384
```

#### 3.3 — Add the server as a Syncthing device

1. On this machine: open `http://localhost:8384` → **"Add Remote Device"**
2. Enter the server's **Device ID** (visible on the server in Syncthing → "Show ID")
3. On the server: accept the pairing request that appears in the UI
4. On the server: in the `openclaw-workspace` folder, enable sharing with this new device
5. On this machine: accept the shared folder → set the local path (e.g. `~/.openclaw/workspace`)
6. Wait for the initial sync (may take several minutes for large wikis)

#### 3.4 — Clone the repo and install dependencies

```bash
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed
cd ai-rag-wiki-memory-OpenClaw-distributed
pip install -r requirements.txt
```

#### 3.5 — Update wiki.config.json on the client

The `wiki.config.json` will arrive via Syncthing from the server (with `host: localhost`). You need to change the host:

```bash
# Full automated client tooling
./deploy/install-client-full.sh <qdrant-server-hostname>
# e.g. ./deploy/install-client-full.sh myserver.tail.xxxxxxx.ts.net

# Workspace/config bootstrap only
./deploy/setup-client.sh <qdrant-server-hostname>

# Or manually
python3 -c "
import json, os
path = os.path.expanduser('~/.openclaw/workspace/wiki.config.json')
with open(path) as f:
    cfg = json.load(f)
cfg['qdrant']['host'] = '<qdrant-server-hostname>'
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('host updated:', cfg['qdrant']['host'])
"
```

> **Note:** `wiki.config.json` is listed in `.stignore` — local edits are never overwritten by Syncthing.

#### 3.6 — Verify connectivity and install the OpenClaw plugin

```bash
# Test remote Qdrant
curl http://<qdrant-server-hostname>:6333/health

# Test wiki query
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "test" --k 3

# Install / update the OpenClaw plugin
python scripts/setup_openclaw.py --workspace ~/.openclaw/workspace
```

If `wiki_context.py` returns results, the client is operational.

---

### Summary

| Step | Where | Key command |
|------|-------|-------------|
| Install Qdrant | Server | `systemctl start qdrant` |
| Install Syncthing | All | `syncthing` |
| Install Tailscale | All | `tailscale up` |
| Clone distributed repo | All | `git clone ...` |
| Update wiki.config.json | Server | Python snippet — `host: localhost` |
| Migrate vectors LanceDB → Qdrant | Server | `migrate_lancedb_to_qdrant.py` |
| Share workspace in Syncthing | Server | Syncthing web UI |
| Add Syncthing device | Each client | Syncthing web UI |
| Change Qdrant host in config | Each client | `setup-client.sh <hostname>` |
| Install OpenClaw plugin | All | `setup_openclaw.py` |

---

## 🔄 Migrating Vectors from LanceDB

If you already have data in `ai-longterm-wiki-memory-OpenClaw`, you can transfer all vectors to Qdrant without re-embedding (bge-m3 vectors are reused as-is):

```bash
# Prerequisite: Qdrant running, lancedb installed temporarily
pip install lancedb

python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json

# Dry run (show stats, no writes)
python scripts/migrate_lancedb_to_qdrant.py \
    --lancedb ~/.openclaw/workspace/memory/lancedb \
    --config ~/.openclaw/workspace/wiki.config.json \
    --dry-run

# Verify vectors arrived
curl http://localhost:6333/collections/wiki_pages
# {"result":{"points_count":N,...}}

# Uninstall lancedb after migration
pip uninstall lancedb
```

---

## 📐 Filesystem Layout

```
ai-rag-wiki-memory-OpenClaw-distributed/
├── scripts/
│   ├── wiki.py                       ← unified CLI (11 commands)
│   ├── wiki_qdrant.py                ← Qdrant ops (upsert, staging, query, dedup, renames)
│   ├── wiki_context.py               ← pre-prompt hook (search + inject <wiki-context>)
│   ├── migrate_lancedb_to_qdrant.py  ← one-shot migration LanceDB → Qdrant
│   ├── wiki_embed.py                 ← boundary-aware chunking + bge-m3
│   ├── wiki_index.py                 ← token-budget index generation
│   ├── wiki_graph.py                 ← node/edge builder for D3 graph
│   ├── wiki_server.py                ← FastAPI: REST, WebSocket, JWT, stats/lint
│   ├── wiki_selfreflect.py           ← behavioural self-reflection
│   ├── wiki_workflows.py             ← CLI command orchestration
│   ├── wiki_check_setup.py           ← prerequisite checks
│   └── setup_openclaw.py             ← automated OpenClaw plugin setup
├── plugins/wiki-context-plugin/      ← TypeScript plugin for OpenClaw
├── skills/
│   ├── wiki-core.md                  ← agent skill: intent classification + workflows + Syncthing protocol
│   ├── wiki-core.it.md               ← Italian version
│   └── wiki-setup.md                 ← setup instructions for agents
├── deploy/
│   ├── qdrant.service                ← systemd unit for Linux (server)
│   ├── syncthing-stignore            ← Syncthing exclusion rules (copy to workspace/.stignore)
│   └── setup-client.sh              ← automated setup script for new client machines
├── tests/
│   ├── test_wiki_qdrant.py           ← 9 tests for wiki_qdrant.py (uses QdrantClient(':memory:'))
│   └── [other inherited tests]
├── frontend/index.html               ← SPA: D3.js + page panel + WebSocket client
├── wiki.config.json                  ← configuration (workspace, qdrant, projects, thresholds)
├── requirements.txt                  ← Python dependencies
├── AGENTS.md                         ← mandatory instructions for AI agents
├── AGENTS-server.md                  ← server-specific agent instructions
├── AGENTS-client.md                  ← client-specific agent instructions
└── SPEC.md                           ← full technical specification
```

---

## 🧪 Tests

Tests use `QdrantClient(":memory:")` — no running Qdrant server required:

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

## 🔬 Technical Notes

### wiki_qdrant.py public interface

`wiki_qdrant.py` exposes the same public interface as `wiki_lancedb.py` — same function names, same types. Code calling `wiki_lancedb.upsert(db, path, chunks)` can be migrated to `wiki_qdrant.upsert(client, cfg, path, chunks)` with minimal changes.

| Function | Description |
|---|---|
| `get_db(config)` | Creates and returns a `QdrantClient` |
| `ensure_collection(client, name)` | Creates the collection if it does not exist (idempotent) |
| `upsert(client, config, path, chunks, staging)` | Replaces all chunks for `path`, inserts the new ones |
| `promote_staging(client, config)` | Copies `staging_*` → main collection, deletes staging |
| `rollback_staging(client, config)` | Deletes staging without touching the main collection |
| `query_similar(client, config, vector, k, path_prefix)` | Top-K search by cosine similarity |
| `find_semantic_duplicates(client, config)` | Similarity matrix across all chunk_id=0 points |
| `detect_renames(client, config, filesystem_paths, workspace)` | Compares page hashes between DB and filesystem |

### Qdrant point schema

```
payload:
  path          STRING   — relative path from workspace root
  chunk_id      INT      — chunk index within the page
  chunk_text    STRING   — chunk text (512 tokens)
  content_hash  STRING   — hash of the chunk text
  page_hash     STRING   — hash of the full page (for detect_renames)
  last_embedded FLOAT    — Unix timestamp

vector: FLOAT[1024]      — bge-m3, Cosine distance
id:     deterministic UUID from md5(path::chunk_id)
```

### Atomic staging

Ingest operations write to `staging_wiki_pages` first. Only `promote_staging()` moves vectors to the main collection. A crash leaves staging populated; the next session can detect and clean up the inconsistent state — no silent corruption.

---

## 📋 CLI Reference

```
wiki.py ingest         --workspace <path> --pages <p1.tmp,...> --log <str>
wiki.py query          --workspace <path> --q <string> [--k 5]
wiki.py lint           --workspace <path> [--full]
wiki.py index          --workspace <path>
wiki.py rebuild        --workspace <path>
wiki.py scan-inbox     --workspace <path>
wiki.py ingest-pdf     --workspace <path> --file <local-path|url>
wiki.py serve          --workspace <path> [--host] [--port 7331] [--no-auth]
wiki.py behavior-log   --workspace <path> --event "<correction>"
wiki.py self-reflect   --workspace <path>
wiki.py session-update --workspace <path> --op <type> --status <ok|failed|...>

wiki_context.py        --workspace <path> --q <string> [--k 3] [--max-chars 600]

migrate_lancedb_to_qdrant.py --lancedb <path> --config <path> [--dry-run]
```

All commands output structured JSON to stdout.

---

## 🌐 AI-Wiki Ecosystem

This project is part of a coherent toolchain for AI-augmented knowledge management:

| Project | Stack | Role |
|---|---|---|
| [ai-longterm-wiki-memory-OpenClaw](https://github.com/giovannifrontera/ai-longterm-wiki-memory-OpenClaw) | Python + LanceDB | Persistent local memory, single machine |
| **ai-rag-wiki-memory-OpenClaw-distributed** ← *you are here* | Python + Qdrant + Syncthing | Shared multi-machine memory |
| [ai-longterm-wiki-memory-ClaudeCode](https://github.com/giovannifrontera/ai-longterm-wiki-memory-ClaudeCode) | Claude + MCP + hooks | Native Claude Code integration |
| [ai-wiki-graph-RAG-lms](https://github.com/giovannifrontera/ai-wiki-graph-RAG-lms) | Anthropic / OpenAI | LTI 1.3 backend for Moodle, Canvas, Blackboard |
| [academic-PRISMA-research-workflow](https://github.com/giovannifrontera/academic-PRISMA-research-workflow) | Claude | Systematic review automation → evidence-based wiki content |

---

## ⚠️ Known Limitations

- **Qdrant requires a running server:** unlike embedded LanceDB, Qdrant must be reachable over the network. If the server is offline, `wiki_context.py` fails silently (no context injected, but the agent is not blocked).
- **Network latency:** semantic queries travel over Tailscale — 1–10 ms of additional latency compared to local LanceDB. Negligible in practice.
- **Large PDFs and Syncthing:** PDFs over 50 MB may take time to sync between machines before becoming available for ingestion.
- **No OCR:** image-only PDFs (no selectable text) are marked `status: failed` in the registry and skipped.
- **Partial test coverage:** current tests cover `wiki_qdrant.py`. Web interface and full workflow tests inherited from the base version have not been migrated yet.

---

## 📄 License

Distributed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

This means:
- You may use, modify, and distribute this software freely
- Any modified version you distribute (including as a network service) must be released under the same license
- You must provide source code to anyone who interacts with the service over a network

See the [`LICENSE`](LICENSE) file for the full text.

---

<div align="center">

*Developed by [Giovanni Frontera, Ph.D.](https://github.com/giovannifrontera) · Part of the AI-Wiki Ecosystem*

</div>
