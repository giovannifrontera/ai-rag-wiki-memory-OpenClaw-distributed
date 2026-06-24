# AGENTS.md - ai-rag-wiki-memory-OpenClaw-distributed

> ## STOP - READ THIS BEFORE ANY ACTION
>
> This is a distributed system. Instructions vary depending on which machine you are on.
>
> **Before anything else: determine which machine you are running on.**

---

## Which machine am I on?

Run this check:

```bash
# Is Qdrant running locally?
curl http://localhost:6333/health 2>/dev/null && echo "YOU ARE ON THE SERVER" || echo "YOU ARE ON A CLIENT"
```

Then read the correct file:

| Machine | File to read |
|---------|--------------|
| **Server** (machine running local Qdrant) | [`AGENTS-server.md`](AGENTS-server.md) |
| **Client** (any other machine) | [`AGENTS-client.md`](AGENTS-client.md) |

---

## Key Differences: Server vs Client

| | Server | Client |
|---|---|---|
| Qdrant | Runs locally at `localhost:6333` | Connects to `<qdrant-server>:6333` via Tailscale |
| `wiki_context.py` hook | Yes, reads local Qdrant | Yes, reads remote Qdrant |
| `wiki.py ingest` | Yes | Yes, writes local Markdown + remote vectors |
| `wiki.py query` | Yes | Yes |
| `wiki.py lint` | Preferred here for full checks | OK for light checks; full checks require Qdrant access |
| `wiki.py serve` | Yes, local dashboard for the server workspace | Yes, local dashboard reading remote Qdrant |
| `wiki.py rebuild` | Run here only | Avoid; heavy operation |
| Cron / night studio jobs | Run here to avoid duplicate maintenance | Do not schedule unless explicitly coordinated |
| Syncthing | Primary node; shares workspace | Receives `wiki/` and `wiki-works/`, keeps local config |
| LanceDB -> Qdrant migration | Run here | Not applicable |

---

## Common Preconditions

Before every session:

1. Read `wiki-session.md` and check `status`.
2. Read `skills/wiki-core.md` and load the full protocol.
3. Verify Qdrant is reachable, local on server or remote on client.
4. Scan for `*.sync-conflict-*` in `wiki/` and `wiki-works/`. If found, stop.
5. If `status != ok`, alert the user before proceeding.

---

## Repo Structure

```text
scripts/
├── wiki.py                       # unified CLI
├── wiki_qdrant.py                # Qdrant ops
├── wiki_context.py               # pre-prompt hook
├── migrate_lancedb_to_qdrant.py  # one-shot migration, server only
└── ...

deploy/
├── qdrant.service                # native systemd unit for the server
├── qdrant-podman.service         # rootless Podman unit for the server
├── setup-server.sh               # automated server setup
├── syncthing-stignore            # copy to workspace/.stignore
└── setup-client.sh               # automated client setup

docs/
├── prerequisites.md
├── install-qdrant.md
├── tailscale-setup.md
├── syncthing-setup.md
├── migrate-lancedb-to-qdrant.md
├── data-quality.md
└── dashboard.md

AGENTS-server.md                  # instructions for the server machine
AGENTS-client.md                  # instructions for client machines
skills/wiki-core.md               # agent protocol, all machines read this
```
