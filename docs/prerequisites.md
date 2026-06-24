# Prerequisites

Use this checklist before installing the distributed wiki.

## Server

- Linux host that stays online while clients work.
- Python 3.11 or newer.
- Qdrant reachable on port `6333`.
- Tailscale installed and connected to the same tailnet as clients.
- Syncthing installed.
- 4 GB RAM minimum, 8 GB recommended. `BAAI/bge-m3` can use roughly 1-2 GB while embedding.
- 5 GB free disk minimum for Python dependencies, Hugging Face model cache, wiki files, and Qdrant storage.

## Client

- Python 3.11 or newer.
- Tailscale installed and connected.
- Syncthing installed.
- Network access to `http://<qdrant-server>:6333/health`.
- OpenClaw configured to run the wiki context hook.

## Python Dependencies

Install from the repo root:

```bash
python3 -m pip install -r requirements.txt
```

The first embedding run downloads `BAAI/bge-m3` from Hugging Face. Set `HF_TOKEN` when possible to avoid anonymous rate limits:

```bash
export HF_TOKEN=hf_...
```

## Configuration

Server `wiki.config.json`:

```json
"qdrant": {
  "host": "localhost",
  "port": 6333,
  "collection": "wiki_pages"
}
```

Client `wiki.config.json`:

```json
"qdrant": {
  "host": "<server-tailscale-hostname-or-ip>",
  "port": 6333,
  "collection": "wiki_pages"
}
```
