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

## Installation / Repair Entry Point

If the user asks to install, repair, bootstrap, or verify the toolchain, read
[`skills/wiki-setup.md`](skills/wiki-setup.md) before doing anything else.

Use the full installers as the primary path:

```bash
# Server: Qdrant + workspace + Syncthing + watchdog + OpenClaw plugin + verification
./deploy/install-server-full.sh

# Client: workspace + remote Qdrant config + deps + OpenClaw plugin + verification
./deploy/install-client-full.sh <qdrant-server-hostname-or-tailnet-ip>
```

On Windows clients, use:

```powershell
.\deploy\install-client-full.ps1 -QdrantHost <qdrant-server-hostname-or-tailnet-ip>
```

Use `deploy/setup-server.sh` or `deploy/setup-client.sh` only for lightweight
workspace/config bootstrap when the user explicitly does not want full install.
If a full installer fails, stop and report the failing section/output; do not
continue manually unless the user asks.

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
├── install-server-full.sh        # full server install/verify path
├── install-client-full.sh        # full Linux/macOS/Git Bash client install/verify path
├── install-client-full.ps1       # full Windows PowerShell client install/verify path
├── setup-server.sh               # lightweight server workspace bootstrap
├── setup-client.sh               # lightweight client workspace/config bootstrap
├── watch-sync.sh                 # server Syncthing ingest watchdog
├── wiki-sync-watchdog.service    # user systemd service for watch-sync.sh
├── qdrant.service                # native systemd unit for the server
├── qdrant-podman.service         # rootless Podman unit for the server
└── syncthing-stignore            # copy to workspace/.stignore

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
skills/wiki-setup.md              # rigid install/repair/verification protocol
skills/wiki-core.md               # agent protocol, all machines read this
```