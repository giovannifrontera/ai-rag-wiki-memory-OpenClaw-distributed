# AGENTS.md — ai-rag-wiki-memory-OpenClaw-distributed

> ## ⛔ STOP — READ THIS BEFORE ANY ACTION
>
> This is a distributed system. Instructions vary depending on which machine you are on.
>
> **Before anything else: determine which machine you are running on.**
>
> ---

## Which machine am I on?

Run this check:

```bash
# Is Qdrant running locally?
curl http://localhost:6333/health 2>/dev/null && echo "YOU ARE ON THE SERVER" || echo "YOU ARE ON A CLIENT"
```

Then read the correct file:

| Machine | File to read |
|---------|-------------|
| **Server** (machine running local Qdrant) | [`AGENTS-server.md`](AGENTS-server.md) |
| **Client** (any other machine) | [`AGENTS-client.md`](AGENTS-client.md) |

---

## Key differences: server vs client

| | Server | Client |
|---|---|---|
| Qdrant | `localhost:6333` | `<qdrant-server>:6333` via Tailscale |
| `wiki.py rebuild` | ✅ Run here | ⛔ Avoid (heavy operation) |
| Syncthing | Primary node | Receives files from server |
| `wiki.py ingest` | ✅ Yes | ✅ Yes (writes local files + remote vectors) |
| LanceDB → Qdrant migration | Run here | Not applicable |

---

## Common preconditions (all machines)

Before every session:

1. `Read wiki-session.md` — check `status`
2. `Read skills/wiki-core.md` — load the full protocol
3. Verify Qdrant is reachable (local or remote)
4. Scan for `*.sync-conflict-*` in `wiki/` and `wiki-works/` — if found, **stop**
5. If `status ≠ ok` — alert the user before proceeding

---

## Repo structure

```
scripts/
├── wiki.py                       ← unified CLI
├── wiki_qdrant.py                ← Qdrant ops (replaces wiki_lancedb.py)
├── wiki_context.py               ← pre-prompt hook
├── migrate_lancedb_to_qdrant.py  ← one-shot migration (server only)
└── ...

deploy/
├── qdrant.service                ← systemd unit for the server
├── syncthing-stignore            ← copy to workspace/.stignore
└── setup-client.sh               ← automated client setup

AGENTS-server.md                  ← instructions for the server machine
AGENTS-client.md                  ← instructions for client machines
skills/wiki-core.md               ← agent protocol (all machines read this)
```
