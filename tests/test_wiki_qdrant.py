"""Test per wiki_qdrant.py — usa QdrantClient(':memory:') senza server."""
import os
import sys
import time
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from wiki_qdrant import (
    get_db, ensure_collection, upsert, promote_staging,
    rollback_staging, query_similar, find_semantic_duplicates,
    detect_renames, _collection_name,
)

CONFIG = {
    "qdrant": {"host": "localhost", "port": 6333, "collection": "wiki_pages"},
    "embedding_model": "BAAI/bge-m3",
}

FAKE_VECTOR = [0.1] * 1024

def make_chunks(path, n=1):
    return [
        {
            "chunk_id": i,
            "chunk_text": f"testo chunk {i} di {path}",
            "content_hash": f"hash_{path}_{i}",
            "page_hash": f"pagehash_{path}",
            "vector": FAKE_VECTOR,
        }
        for i in range(n)
    ]


@pytest.fixture
def client():
    from qdrant_client import QdrantClient
    return QdrantClient(":memory:")


def test_ensure_collection_creates(client):
    ensure_collection(client, "wiki_pages")
    names = [c.name for c in client.get_collections().collections]
    assert "wiki_pages" in names


def test_ensure_collection_idempotent(client):
    ensure_collection(client, "wiki_pages")
    ensure_collection(client, "wiki_pages")
    names = [c.name for c in client.get_collections().collections]
    assert names.count("wiki_pages") == 1


def test_upsert_and_query(client):
    upsert(client, CONFIG, "wiki/test.md", make_chunks("wiki/test.md", 2))
    results = query_similar(client, CONFIG, FAKE_VECTOR, k=5)
    assert any(r["path"] == "wiki/test.md" for r in results)


def test_upsert_replaces_old_chunks(client):
    upsert(client, CONFIG, "wiki/test.md", make_chunks("wiki/test.md", 3))
    upsert(client, CONFIG, "wiki/test.md", make_chunks("wiki/test.md", 1))
    results = query_similar(client, CONFIG, FAKE_VECTOR, k=10)
    paths_found = [r for r in results if r["path"] == "wiki/test.md"]
    assert len(paths_found) == 1


def test_staging_promote(client):
    upsert(client, CONFIG, "wiki/page.md", make_chunks("wiki/page.md"), staging=True)
    staging_name = _collection_name(CONFIG, staging=True)
    names = [c.name for c in client.get_collections().collections]
    assert staging_name in names
    promote_staging(client, CONFIG)
    names_after = [c.name for c in client.get_collections().collections]
    assert staging_name not in names_after
    results = query_similar(client, CONFIG, FAKE_VECTOR, k=5)
    assert any(r["path"] == "wiki/page.md" for r in results)


def test_staging_rollback(client):
    upsert(client, CONFIG, "wiki/page.md", make_chunks("wiki/page.md"), staging=True)
    rollback_staging(client, CONFIG)
    names = [c.name for c in client.get_collections().collections]
    assert _collection_name(CONFIG, staging=True) not in names
    results = query_similar(client, CONFIG, FAKE_VECTOR, k=5)
    assert not any(r["path"] == "wiki/page.md" for r in results)


def test_query_with_prefix(client):
    upsert(client, CONFIG, "wiki/magia.md", make_chunks("wiki/magia.md"))
    upsert(client, CONFIG, "wiki-works/trading/analisi.md", make_chunks("wiki-works/trading/analisi.md"))
    results = query_similar(client, CONFIG, FAKE_VECTOR, k=5, path_prefix="wiki-works/")
    assert all(r["path"].startswith("wiki-works/") for r in results)


def test_find_semantic_duplicates_empty(client):
    result = find_semantic_duplicates(client, CONFIG)
    assert result == []


def test_detect_renames_empty(client, tmp_path):
    result = detect_renames(client, CONFIG, set(), str(tmp_path))
    assert result == []
