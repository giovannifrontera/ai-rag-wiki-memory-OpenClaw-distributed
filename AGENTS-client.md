# AGENTS-client.md — Client Machine

> ## ⛔ STOP — READ THIS BEFORE ANY ACTION
>
> **Every session, before any action:**
> 1. `Read wiki-session.md` in the workspace — check the status
> 2. `Read skills/wiki-core.md` — load the full protocol
> 3. Verify Qdrant connectivity: `curl http://<qdrant-server>:6333/health`
> 4. Verify Syncthing is synced (recent files present in `wiki/`)
> 5. Scan `wiki/` and `wiki-works/` for `*.sync-conflict-*` files — if found, **stop and alert**
>
> These are local files. Use the **Read** tool, not a Skill or Tool call.
>
> ---

This is a **client machine**: it does not run Qdrant locally. It connects to the server via Tailscale for vector queries, and receives wiki files via Syncthing.

---

## Health check — run before every session

```bash
# Is Qdrant reachable via Tailscale?
curl http://<qdrant-server>:6333/health
# Expected: {"title":"qdrant - vector search engine","version":"..."}
# If this fails: check that Tailscale is connected and Qdrant is running on the server

# Is Tailscale connected?
tailscale status

# Are recent Syncthing files present?
ls -lt ~/.openclaw/workspace/wiki/ | head -5
# Files should be up to date — if they are old, Syncthing may not be running
```

If Qdrant is not reachable:
- Check `tailscale status` — are you connected to the network?
- Verify Qdrant is running on the server: ask the user to check `systemctl status qdrant`
- **Do not proceed** with ingest if Qdrant does not respond — vectors would not be written

---

## Workspace structure

```
~/.openclaw/workspace/          ← synced via Syncthing from the server
├── wiki.config.json            ← qdrant.host = "<qdrant-server>" (NOT localhost)
├── wiki-session.md             ← current session state
├── wiki/                       ← Distilled layer + Identity (received via Syncthing)
│   └── identity/               ← only wiki.py self-reflect writes here
├── wiki-works/<topic>/         ← Domain layer (bidirectional Syncthing sync)
└── .stignore                   ← Syncthing exclusion rules
```

> **Important:** `wiki.config.json` on this machine must have `qdrant.host` set to the server's
> Tailscale hostname, **not** `localhost`. Verify with:
> ```bash
> python -c "import json; cfg=json.load(open('~/.openclaw/workspace/wiki.config.json'.replace('~', __import__('os').path.expanduser('~')))); print(cfg['qdrant']['host'])"
> # Expected: server hostname (e.g. myserver.tail.xxxxxxx.ts.net), NOT localhost
> ```

---

## Available commands

Clients run the same commands as the server, with one exception:

| Command | Client | Notes |
|---------|--------|-------|
| `ingest` | ✅ Yes | Writes Markdown files locally (Syncthing propagates them) + vectors to remote Qdrant |
| `query` | ✅ Yes | Queries remote Qdrant via Tailscale |
| `lint` | ✅ Yes (lightweight) | Checks local file consistency |
| `index` | ✅ Yes | Generates local index.md |
| `serve` | ✅ Yes | Local dashboard (reads remote Qdrant) |
| `ingest-pdf` | ✅ Yes | Extracts PDF locally, file goes to Syncthing |
| `self-reflect` | ✅ Yes | Writes to `wiki/identity/` (propagated by Syncthing) |
| `rebuild` | ⛔ Avoid | Heavy operation — run on the server instead |

### Ingest

```bash
python scripts/wiki.py ingest \
    --workspace ~/.openclaw/workspace \
    --pages wiki-works/research/concepts/new.md.tmp \
    --log "ingest | New research concept"
```

The Markdown file is written locally; Syncthing propagates it to the server within seconds. Vectors are written to Qdrant via Tailscale.

### Query and context

```bash
python scripts/wiki_context.py \
    --workspace ~/.openclaw/workspace \
    --q "user question" --k 3
```

---

## Syncthing conflict protocol

`*.sync-conflict-*` files are created when this machine and the server (or another machine) modify the same wiki page at the same time.

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

## PDF ingestion

```bash
python scripts/wiki.py ingest-pdf --workspace <path> --file <path|url>
```

The extracted text is deposited in `wiki-works/<project>/raw/` locally. Syncthing propagates it. Then follow the standard workflow:

1. Read every file in `raw/`
2. Write structured `.tmp` pages
3. Call `wiki.py ingest`

---

## Architecture — three layers, one brain

| Layer | Directory | Contents | Who writes |
|-------|-----------|----------|------------|
| **Domain** | `wiki-works/<topic>/` | Deep topic-specific knowledge | INGEST workflow |
| **Distilled** | `wiki/` | Cross-domain knowledge, autonomously promoted | Agent (autonomous) |
| **Identity** | `wiki/identity/` | Values, style, behavioural patterns | Only `wiki.py self-reflect` |

---

## Command reference

```
wiki.py ingest         --workspace <path> --pages <p1.tmp,...> --log <str>
wiki.py query          --workspace <path> --q <string> [--k 5]
wiki.py lint           --workspace <path> [--full]
wiki.py index          --workspace <path>
wiki.py scan-inbox     --workspace <path>
wiki.py ingest-pdf     --workspace <path> --file <path|url>
wiki.py process-raw    --workspace <path> [--project <name>]
wiki.py serve          --workspace <path> [--port 7331] [--no-auth]
wiki.py behavior-log   --workspace <path> --event "<correction>"
wiki.py self-reflect   --workspace <path>
wiki.py cleanup        --workspace <path>

wiki_context.py        --workspace <path> --q <string> [--k 3] [--max-chars 600]
```

`delete` and `rebuild` are server-only operations — run them on the server machine.
