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

## Embedding backend (CPU / GPU / Ollama)

The embedding backend is configurable in `wiki.config.json` under `embedding`.
Default works everywhere with no extra setup:

```json
"embedding": {
  "backend": "sentence-transformers",
  "model": "BAAI/bge-m3",
  "device": "cpu",
  "ollama_host": "http://localhost:11434"
}
```

- **NVIDIA GPU**: set `"device": "cuda"` (keeps `sentence-transformers`). Requires a CUDA-enabled PyTorch.
- **AMD / Ryzen iGPU or any GPU via Ollama** (recommended on non-NVIDIA): set
  `"backend": "ollama"`. ROCm on `sentence-transformers` is unreliable on iGPUs;
  Ollama runs the model on the GPU and the toolchain only does an HTTP call.
  Install Ollama and pull the model once, then point `ollama_host` at it:

  ```bash
  ollama pull bge-m3
  # wiki.config.json -> "model": "bge-m3", "ollama_host": "http://localhost:11434"
  ```

  Clients without a local GPU can set `ollama_host` to the server's Ollama
  endpoint (e.g. `http://<server-tailnet-ip>:11434`) to share its GPU, the same
  way they share Qdrant. With the Ollama backend `sentence-transformers` is still
  used only for chunk tokenization, no embedding model is loaded in-process — so
  the pre-prompt hook does not reload a model on every prompt.

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
