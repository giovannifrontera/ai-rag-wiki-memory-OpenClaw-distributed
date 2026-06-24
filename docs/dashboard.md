# Dashboard

`wiki.py serve` starts a local FastAPI dashboard for inspecting the wiki.

```bash
python scripts/wiki.py serve --workspace ~/.openclaw/workspace --port 7331 --no-auth
```

Open `http://localhost:7331`.

## What It Shows

- Graph view of Markdown pages and links.
- Semantic edges from Qdrant.
- Page detail view.
- Query activity from `.wiki-query-log.jsonl`.
- Stats tab with page counts, embedded/unembedded pages, lint status, and top queried pages.
- Manual lint trigger.

## Where To Run It

Server:

- Best place for operational monitoring.
- Reads local Qdrant.

Client:

- OK for local inspection.
- Reads remote Qdrant through Tailscale.

The dashboard is not required for ingest/query. It is a visual and maintenance surface.
