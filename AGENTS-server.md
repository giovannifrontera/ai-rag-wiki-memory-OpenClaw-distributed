# AGENTS-server.md — Server Machine

> ## ⛔ STOP — READ THIS BEFORE ANY ACTION
>
> **Every session, before any action:**
> 1. `Read wiki-session.md` in the workspace — check the status
> 2. `Read skills/wiki-core.md` — load the full protocol
> 3. Verify Qdrant is running: `curl http://localhost:6333/health`
> 4. Scan `wiki/` and `wiki-works/` for `*.sync-conflict-*` files — if found, **stop and alert the user**
>
> These are local files. Use the **Read** tool, not a Skill or Tool call.
>
> ---

This is the **server machine**: it runs Qdrant, manages the vector database, and is the primary Syncthing node. Clients connect to Qdrant via Tailscale.

---

## Installation — first-time setup (Step 0)

Clone the repo to get the scripts, then copy them to the workspace:

```bash
git clone https://github.com/giovannifrontera/ai-rag-wiki-memory-OpenClaw-distributed /tmp/wiki-repo
mkdir -p ~/.openclaw/workspace/scripts ~/.openclaw/workspace/skills
cp -r /tmp/wiki-repo/scripts/. ~/.openclaw/workspace/scripts/
cp -r /tmp/wiki-repo/skills/.  ~/.openclaw/workspace/skills/
cp /tmp/wiki-repo/wiki.config.json ~/.openclaw/workspace/wiki.config.json
pip install -r /tmp/wiki-repo/requirements.txt
rm -rf /tmp/wiki-repo
```

Edit `~/.openclaw/workspace/wiki.config.json` and set `qdrant.host` to `localhost` (server) or your Tailscale hostname (client).

**Optional but recommended:** set `HF_TOKEN` to avoid Hugging Face anonymous rate limits when downloading the embedding model (`BAAI/bge-m3`):

```bash
echo 'export HF_TOKEN=hf_...' >> ~/.bashrc   # or ~/.zshrc
# Get your token at: https://huggingface.co/settings/tokens
```

The model is cached after the first download (~1.2 GB in `~/.cache/huggingface/`), so subsequent starts are fast.

To run Qdrant:
- **Native binary**: use `deploy/qdrant.service`
- **Podman (Fedora/Bazzite)**: use `deploy/qdrant-podman.service`
  ```bash
  cp deploy/qdrant-podman.service ~/.config/systemd/user/
  systemctl --user enable --now qdrant-podman
  ```

---

## Health check — run before every session

```bash
# Is Qdrant running?
curl http://localhost:6333/health
# Expected: {"title":"qdrant - vector search engine","version":"..."}

# Is the collection present?
curl http://localhost:6333/collections/wiki_pages
# Expected: {"result":{"points_count":N,...}}

# Is Syncthing running?
curl http://localhost:8384/rest/system/ping -H "X-API-Key: <your-api-key>"

# Qdrant service status
systemctl status qdrant
```

If Qdrant does not respond:
```bash
sudo systemctl start qdrant
sudo systemctl status qdrant
# Check logs if the service fails to start
journalctl -u qdrant -n 50
```

---

## Workspace structure

```
~/.openclaw/workspace/
├── wiki.config.json          ← qdrant.host = "localhost" (server uses localhost)
├── wiki-session.md           ← current session state
├── wiki/                     ← Distilled layer + Identity (Syncthing sync)
│   └── identity/             ← only wiki.py self-reflect writes here
├── wiki-works/<topic>/       ← Domain layer (Syncthing sync)
└── .stignore                 ← Syncthing exclusion rules
```

The vector database is **not in the workspace** — it lives in Qdrant at `localhost:6333`.

---

## Available commands

### Ingest

```bash
# Standard ingest (from .tmp files written by the agent)
python scripts/wiki.py ingest \
    --workspace ~/.openclaw/workspace \
    --pages wiki-works/research/concepts/new-concept.md.tmp \
    --log "ingest | New research concept"

# PDF ingest
python scripts/wiki.py ingest-pdf \
    --workspace ~/.openclaw/workspace \
    --file /path/to/document.pdf

# Scan PDF inbox
python scripts/wiki.py scan-inbox --workspace ~/.openclaw/workspace
```

### Query and context

```bash
# Manual semantic search
python scripts/wiki.py query \
    --workspace ~/.openclaw/workspace \
    --q "purification ritual" --k 5

# Pre-prompt context injection (used automatically by the plugin)
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "user question" --k 3
```

### Maintenance (preferred on server)

```bash
# Lint — detect and repair inconsistencies
python scripts/wiki.py lint --workspace ~/.openclaw/workspace
python scripts/wiki.py lint --workspace ~/.openclaw/workspace --full

# Rebuild — rewrites the ENTIRE vector DB from scratch (heavy operation)
# Run ONLY on server, never on clients
python scripts/wiki.py rebuild --workspace ~/.openclaw/workspace

# Token-budget index
python scripts/wiki.py index --workspace ~/.openclaw/workspace
```

### Web dashboard

```bash
python scripts/wiki.py serve \
    --workspace ~/.openclaw/workspace \
    --port 7331 --no-auth
# http://localhost:7331
```

### Behavioural self-reflection

```bash
# Log a user correction
python scripts/wiki.py behavior-log \
    --workspace ~/.openclaw/workspace \
    --event "always use formal address in formal replies"

# Self-reflect (run at end of session if ≥1 correction received)
python scripts/wiki.py self-reflect --workspace ~/.openclaw/workspace
```

---

## Syncthing conflict protocol

If you find `*.sync-conflict-*` files in `wiki/` or `wiki-works/`:

1. **Do not proceed** with any wiki operation
2. Alert the user: "Syncthing conflict found: [file list]. Two instances wrote to the same page simultaneously. Which version do you want to keep?"
3. Show the content of both files
4. Wait for the user's decision
5. After resolution: delete the discarded file, run `wiki.py lint`
6. Update `wiki-session.md` with `status: ok`

Never delete conflict files automatically.

---

## Wiki context injection

Every prompt arrives preceded by:

```
<wiki-context>
Pre-loaded wiki context (top 3 pages by semantic relevance):
### wiki/concepts/rag.md  [relevance: 0.91]
[page content...]
</wiki-context>
```

Use this directly. Do not re-run `wiki.py query` for the same prompt.
If all relevance scores < 0.4 → the wiki has no relevant knowledge, proceed normally.

---

## PDF ingestion — mandatory workflow

```bash
python scripts/wiki.py ingest-pdf --workspace <path> --file <path|url>
```

This deposits the extracted text in `wiki-works/<project>/raw/`.

**After `ingest-pdf`, the agent must:**
1. Read every file deposited in `raw/`
2. Write structured `.tmp` pages (see `skills/wiki-core.md §ingest`)
3. Call `wiki.py ingest --workspace <path> --pages <file.tmp>`

Never use `process-raw` as a shortcut for the INGEST workflow.

---

## Architecture — three layers, one brain

| Layer | Directory | Contents | Who writes |
|-------|-----------|----------|------------|
| **Domain** | `wiki-works/<topic>/` | Deep topic-specific knowledge | INGEST workflow |
| **Distilled** | `wiki/` | Cross-domain knowledge, autonomously promoted | Agent (autonomous) |
| **Identity** | `wiki/identity/` | Values, style, behavioural patterns | Only `wiki.py self-reflect` |

Promote a page from `wiki-works/` to `wiki/` autonomously when it is relevant in ≥2 topics and retrieved in ≥3 queries.

---

## Command reference (complete)

```
wiki.py ingest         --workspace <path> --pages <p1.tmp,...> --log <str>
wiki.py query          --workspace <path> --q <string> [--k 5]
wiki.py lint           --workspace <path> [--full]
wiki.py index          --workspace <path>
wiki.py rebuild        --workspace <path>          ← SERVER ONLY
wiki.py scan-inbox     --workspace <path>
wiki.py ingest-pdf     --workspace <path> --file <path|url>
wiki.py process-raw    --workspace <path> [--project <name>]
wiki.py serve          --workspace <path> [--port 7331] [--no-auth]
wiki.py behavior-log   --workspace <path> --event "<correction>"
wiki.py self-reflect   --workspace <path>
wiki.py session-update --workspace <path> --op <type> --status <ok|failed|...>
wiki.py delete         --workspace <path> --page <relative/path.md>
wiki.py cleanup        --workspace <path>

wiki_context.py        --workspace <path> --q <string> [--k 3] [--max-chars 600]
migrate_lancedb_to_qdrant.py --lancedb <path> --config <path> [--dry-run]
```

### delete

Removes a wiki page permanently: deletes the `.md` file and all its Qdrant vectors.
Use this for garbage pages, duplicates, or spam-injected content.

```bash
python scripts/wiki.py delete \
    --workspace ~/.openclaw/workspace \
    --page wiki-works/research/some-garbage-page.md
```

### cleanup

Removes all stale `.tmp` files from `wiki/` and `wiki-works/` (residues of failed ingests).

```bash
python scripts/wiki.py cleanup --workspace ~/.openclaw/workspace
```

### Spam / keyword-dump detection

`wiki.py ingest` automatically rejects files where ≥30% of content lines look like
comma-separated keyword dumps (e.g. SEO spam injected via unfiltered `web_fetch`).
The ingest will fail with `spam_content_detected` before any embedding happens.

If you need to remove already-embedded spam pages, use `wiki.py delete`.

---

## Related Setup Docs

- Automated server bootstrap: `./deploy/setup-server.sh ~/.openclaw/workspace`
- Qdrant install: [`docs/install-qdrant.md`](docs/install-qdrant.md)
- Tailscale setup: [`docs/tailscale-setup.md`](docs/tailscale-setup.md)
- Syncthing setup: [`docs/syncthing-setup.md`](docs/syncthing-setup.md)
- LanceDB to Qdrant migration: [`docs/migrate-lancedb-to-qdrant.md`](docs/migrate-lancedb-to-qdrant.md)
- Dashboard: [`docs/dashboard.md`](docs/dashboard.md)
- Data quality cleanup: [`docs/data-quality.md`](docs/data-quality.md)

For offline laptop edits, enable `deploy/wiki-sync-watchdog.service` on the server. Syncthing copies the `.md` file back to the server; the watchdog re-ingests it into Qdrant and records the content hash in `.synced-ingested.json`.
