"""Chunking boundary-aware + embedding bge-m3."""

import hashlib
import re

_model = None
_tokenizer = None


def _load_tokenizer(model_name: str = "BAAI/bge-m3"):
    """Tokenizer leggero per il chunking (~2MB, niente torch): preciso al 100%
    perché è lo stesso tokenizer di bge-m3. Usato a prescindere dal backend di
    embedding, così col backend ollama non si carica mai sentence-transformers."""
    global _tokenizer
    if _tokenizer is None:
        from transformers import AutoTokenizer
        _tokenizer = AutoTokenizer.from_pretrained(model_name)
    return _tokenizer


def _load_model(model_name: str = "BAAI/bge-m3", device: str | None = None):
    """Carica sentence-transformers (con torch): solo per il backend di embedding
    'sentence-transformers'. Il chunking usa _load_tokenizer, non questo."""
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(model_name, device=device)
    return _model


def _embed_opts(cfg: dict) -> dict:
    """Estrae la config di embedding con default retrocompatibili.

    Backward-compat: se manca la sezione "embedding", usa sentence-transformers
    con il vecchio campo top-level "embedding_model" e device auto (None).
    """
    emb = cfg.get("embedding", {})
    return {
        "backend": emb.get("backend", "sentence-transformers"),
        "model": emb.get("model") or cfg.get("embedding_model", "BAAI/bge-m3"),
        "device": emb.get("device"),  # None = auto-select (GPU se disponibile)
        "ollama_host": emb.get("ollama_host", "http://localhost:11434"),
    }


def _embed_ollama(texts: list[str], model: str, host: str, retries: int = 3) -> list[list[float]]:
    import time
    import requests
    url = host.rstrip("/") + "/api/embeddings"
    out = []
    # ponytail: chiamata per-testo; il rebuild è raro/one-shot, batch solo se serve
    for t in texts:
        last_err = None
        for attempt in range(retries):
            try:
                r = requests.post(url, json={"model": model, "prompt": t}, timeout=120)
                r.raise_for_status()
                out.append(r.json()["embedding"])
                break
            except Exception as e:  # rete/Ollama transitori: ritenta con backoff
                last_err = e
                if attempt < retries - 1:
                    time.sleep(2 ** attempt)
        else:
            raise RuntimeError(f"Ollama embedding fallito dopo {retries} tentativi: {last_err}")
    return out


def embed_texts(texts: list[str], cfg: dict) -> list[list[float]]:
    """Embedda una lista di testi col backend configurato. Qdrant usa COSINE,
    quindi la normalizzazione non influenza il ranking (la facciamo solo lato
    sentence-transformers per parità coi vettori storici già indicizzati)."""
    opts = _embed_opts(cfg)
    if opts["backend"] == "ollama":
        return _embed_ollama(texts, opts["model"], opts["ollama_host"])
    model = _load_model(opts["model"], opts["device"])
    vecs = model.encode(texts, normalize_embeddings=True)
    return [v.tolist() for v in vecs]


def embed_query(text: str, cfg: dict) -> list[float]:
    return embed_texts([text], cfg)[0]


def count_tokens(text: str, model_name: str = "BAAI/bge-m3") -> int:
    tokenizer = _load_tokenizer(model_name)
    return len(tokenizer.encode(text, add_special_tokens=False))


def _split_on_headings(text: str) -> list[str]:
    """Splitta il testo sui boundary ## e ### mantenendo il testo prima del primo heading."""
    parts = re.split(r'(?=^#{2,3} )', text, flags=re.MULTILINE)
    return [p for p in parts if p.strip()]


def _tail_text(text: str, n_tokens: int, tokenizer) -> str:
    """Restituisce gli ultimi n_tokens del testo (per implementare l'overlap)."""
    if n_tokens <= 0 or not text.strip():
        return ""
    ids = tokenizer.encode(text, add_special_tokens=False)
    if len(ids) <= n_tokens:
        return text
    return tokenizer.decode(ids[-n_tokens:])


def _emit_chunk(chunks: list, current: str, overlap: int, tokenizer) -> tuple[str, int]:
    """Aggiunge current a chunks e restituisce il prefisso di overlap per il chunk successivo."""
    stripped = current.strip()
    if stripped:
        chunks.append(stripped)
    prefix = _tail_text(stripped, overlap, tokenizer) if overlap > 0 else ""
    prefix_with_sep = prefix + "\n\n" if prefix else ""
    return prefix_with_sep, len(tokenizer.encode(prefix_with_sep, add_special_tokens=False))


def chunk_text(
    text: str,
    chunk_size: int = 512,
    overlap: int = 64,
    threshold: int = 1500,
    model_name: str = "BAAI/bge-m3",
) -> list[str]:
    """Ritorna lista di chunk con overlap reale. Se il testo è sotto soglia, ritorna [text]."""
    tokenizer = _load_tokenizer(model_name)

    if count_tokens(text, model_name) <= threshold:
        return [text]

    sections = _split_on_headings(text)
    chunks: list[str] = []
    current: str = ""
    current_tokens: int = 0

    for section in sections:
        sec_tokens = count_tokens(section, model_name)

        if current_tokens + sec_tokens <= chunk_size:
            current += section
            current_tokens += sec_tokens
        else:
            current, current_tokens = _emit_chunk(chunks, current, overlap, tokenizer)

            if sec_tokens <= chunk_size:
                current += section
                current_tokens += sec_tokens
            else:
                # Sezione più grande del chunk_size: splitta per paragrafi
                paragraphs = section.split('\n\n')
                para_acc: str = current
                para_tokens: int = current_tokens
                for para in paragraphs:
                    pt = count_tokens(para, model_name)
                    if para_tokens + pt <= chunk_size:
                        para_acc += para + '\n\n'
                        para_tokens += pt
                    else:
                        para_acc, para_tokens = _emit_chunk(chunks, para_acc, overlap, tokenizer)
                        para_acc += para + '\n\n'
                        para_tokens += pt
                current = para_acc
                current_tokens = para_tokens

    _emit_chunk(chunks, current, 0, tokenizer)  # ultimo chunk: no overlap in coda

    return chunks if chunks else [text]


_MAX_CHARS = 30_000


def embed_file(
    path: str,
    chunk_size: int = 512,
    overlap: int = 64,
    threshold: int = 1500,
    model_name: str = "BAAI/bge-m3",
    cfg: dict | None = None,
) -> list[dict]:
    """Legge un file .md e ritorna lista di chunk con vettori e hash.

    cfg, se passato, seleziona il backend di embedding (sentence-transformers o
    ollama). Senza cfg usa sentence-transformers col model_name dato (path legacy
    usato dai test)."""
    with open(path, encoding="utf-8") as f:
        text = f.read()

    page_hash = hashlib.sha256(text.encode()).hexdigest()  # hash del file reale, prima del troncamento

    if len(text) > _MAX_CHARS:
        text = text[:_MAX_CHARS] + "\n\n[... file troncato per limite embedding]"
    chunks = chunk_text(text, chunk_size, overlap, threshold, model_name)
    _embed_cfg = cfg if cfg is not None else {"embedding_model": model_name}
    vectors = embed_texts(chunks, _embed_cfg)

    result = []
    for i, chunk in enumerate(chunks):
        vector = vectors[i]
        content_hash = hashlib.sha256(chunk.encode()).hexdigest()
        result.append({
            "chunk_id": i,
            "chunk_text": chunk,
            "vector": vector,
            "content_hash": content_hash,
            "page_hash": page_hash,
        })
    return result
