import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))

from wiki_embed import count_tokens, chunk_text

SHORT_TEXT = "Questo è un testo breve che non supera la soglia di chunking."

LONG_TEXT = "\n".join([
    "## Sezione A",
    "Contenuto della sezione A. " * 100,
    "",
    "## Sezione B",
    "Contenuto della sezione B. " * 100,
    "",
    "## Sezione C",
    "Contenuto della sezione C. " * 100,
])

def test_count_tokens_returns_int():
    n = count_tokens(SHORT_TEXT)
    assert isinstance(n, int)
    assert n > 0

def test_short_text_not_chunked():
    chunks = chunk_text(SHORT_TEXT, chunk_size=512, overlap=64, threshold=1500)
    assert len(chunks) == 1
    assert chunks[0] == SHORT_TEXT

def test_long_text_chunked():
    chunks = chunk_text(LONG_TEXT, chunk_size=512, overlap=64, threshold=1500)
    assert len(chunks) > 1

def test_all_content_preserved():
    chunks = chunk_text(LONG_TEXT, chunk_size=512, overlap=64, threshold=1500)
    combined = " ".join(chunks)
    assert "Sezione A" in combined
    assert "Sezione B" in combined
    assert "Sezione C" in combined


def test_overlap_between_adjacent_chunks():
    """Verifica che chunk adiacenti condividano effettivamente del testo (overlap reale)."""
    chunks = chunk_text(LONG_TEXT, chunk_size=512, overlap=64, threshold=1500)
    if len(chunks) < 2:
        return  # non applicabile
    for i in range(len(chunks) - 1):
        # Le prime parole del chunk successivo devono comparire anche nella coda del precedente
        next_words = chunks[i + 1].split()[:5]
        prev_tail = chunks[i][-300:]  # ultimi ~300 char del chunk precedente
        assert any(w in prev_tail for w in next_words), (
            f"Nessun overlap trovato tra chunk {i} e {i+1}"
        )


def test_page_hash_is_full_file_hash(tmp_path):
    """page_hash deve essere sha256 del file reale, anche se il testo è troncato."""
    import hashlib
    from wiki_embed import _MAX_CHARS
    # File più lungo del limite di troncamento
    content = "parola " * (_MAX_CHARS // 7 + 100)
    md = tmp_path / "big.md"
    md.write_text(content, encoding="utf-8")
    expected_hash = hashlib.sha256(content.encode()).hexdigest()
    chunks = embed_file(str(md))
    assert chunks[0]["page_hash"] == expected_hash


import tempfile
from wiki_embed import embed_file


def test_embed_file_short(tmp_path):
    md = tmp_path / "page.md"
    md.write_text("# Titolo\nContenuto breve.", encoding="utf-8")
    chunks = embed_file(str(md))
    assert len(chunks) == 1
    assert chunks[0]["chunk_id"] == 0
    assert len(chunks[0]["vector"]) == 1024
    assert len(chunks[0]["content_hash"]) == 64   # SHA256 hex
    assert len(chunks[0]["page_hash"]) == 64
    assert chunks[0]["chunk_text"] == "# Titolo\nContenuto breve."


def test_embed_file_content_hash_changes_with_content(tmp_path):
    md = tmp_path / "page.md"
    md.write_text("Contenuto A", encoding="utf-8")
    h1 = embed_file(str(md))[0]["content_hash"]
    md.write_text("Contenuto B", encoding="utf-8")
    h2 = embed_file(str(md))[0]["content_hash"]
    assert h1 != h2


def test_embed_file_path_does_not_affect_hash(tmp_path):
    md1 = tmp_path / "a.md"
    md2 = tmp_path / "b.md"
    content = "Stesso contenuto"
    md1.write_text(content, encoding="utf-8")
    md2.write_text(content, encoding="utf-8")
    h1 = embed_file(str(md1))[0]["content_hash"]
    h2 = embed_file(str(md2))[0]["content_hash"]
    assert h1 == h2  # hash = SHA256(testo), path non incluso


# --- backend di embedding configurabile ---
from wiki_embed import _embed_opts, embed_texts, embed_query


def test_embed_opts_defaults_backward_compat():
    # Senza sezione "embedding" usa il vecchio campo top-level e device auto.
    opts = _embed_opts({"embedding_model": "BAAI/bge-m3"})
    assert opts["backend"] == "sentence-transformers"
    assert opts["model"] == "BAAI/bge-m3"
    assert opts["device"] is None


def test_embed_opts_reads_embedding_section():
    cfg = {"embedding": {"backend": "ollama", "model": "bge-m3",
                         "device": "cuda", "ollama_host": "http://h:11434"}}
    opts = _embed_opts(cfg)
    assert opts == {"backend": "ollama", "model": "bge-m3",
                    "device": "cuda", "ollama_host": "http://h:11434"}


def test_embed_ollama_backend_dispatch(monkeypatch):
    """Backend ollama deve fare HTTP, NON caricare sentence-transformers."""
    import wiki_embed
    calls = []

    class FakeResp:
        def raise_for_status(self): pass
        def json(self): return {"embedding": [0.5] * 1024}

    def fake_post(url, json, timeout):
        calls.append((url, json))
        return FakeResp()

    monkeypatch.setattr("requests.post", fake_post)
    cfg = {"embedding": {"backend": "ollama", "model": "bge-m3",
                         "ollama_host": "http://srv:11434"}}
    vec = embed_query("hello world", cfg)
    assert len(vec) == 1024
    assert calls[0][0] == "http://srv:11434/api/embeddings"
    assert calls[0][1] == {"model": "bge-m3", "prompt": "hello world"}


def test_embed_ollama_retries_then_succeeds(monkeypatch):
    import wiki_embed
    monkeypatch.setattr("time.sleep", lambda *_: None)
    attempts = {"n": 0}

    class FakeResp:
        def raise_for_status(self): pass
        def json(self): return {"embedding": [0.1] * 1024}

    def flaky_post(url, json, timeout):
        attempts["n"] += 1
        if attempts["n"] < 3:
            raise ConnectionError("ollama down")
        return FakeResp()

    monkeypatch.setattr("requests.post", flaky_post)
    out = wiki_embed._embed_ollama(["x"], "bge-m3", "http://h:11434")
    assert len(out) == 1 and len(out[0]) == 1024
    assert attempts["n"] == 3  # ha ritentato fino al successo


def test_embed_ollama_raises_after_exhausting_retries(monkeypatch):
    import pytest, wiki_embed
    monkeypatch.setattr("time.sleep", lambda *_: None)

    def always_fail(url, json, timeout):
        raise ConnectionError("ollama down")

    monkeypatch.setattr("requests.post", always_fail)
    with pytest.raises(RuntimeError):
        wiki_embed._embed_ollama(["x"], "bge-m3", "http://h:11434", retries=2)
