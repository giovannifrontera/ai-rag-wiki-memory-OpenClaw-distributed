"""Operazioni Qdrant per il wiki system — rimpiazza wiki_lancedb.py."""

import hashlib
import os
import time
import uuid
import numpy as np

from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    FieldCondition,
    Filter,
    FilterSelector,
    MatchValue,
    PointStruct,
    VectorParams,
)

VECTOR_SIZE = 1024
DISTANCE = Distance.COSINE


def _point_id(path: str, chunk_id: int) -> str:
    """UUID deterministico da path + chunk_id."""
    key = f"{path}::{chunk_id}"
    return str(uuid.UUID(hashlib.md5(key.encode()).hexdigest()))


def _collection_name(config: dict, staging: bool = False) -> str:
    base = config.get("qdrant", {}).get("collection", "wiki_pages")
    return f"staging_{base}" if staging else base


def get_db(config: dict) -> QdrantClient:
    cfg = config.get("qdrant", {})
    host = cfg.get("host", "localhost")
    if cfg.get("path"):
        return QdrantClient(path=cfg["path"])
    if host == ":memory:":
        return QdrantClient(":memory:")
    return QdrantClient(host=host, port=cfg.get("port", 6333))


def ensure_collection(client: QdrantClient, name: str) -> None:
    existing = [c.name for c in client.get_collections().collections]
    if name not in existing:
        client.create_collection(
            collection_name=name,
            vectors_config=VectorParams(size=VECTOR_SIZE, distance=DISTANCE),
        )


def upsert(
    client: QdrantClient,
    config: dict,
    path: str,
    chunks: list[dict],
    staging: bool = False,
) -> None:
    """Cancella tutti i chunk per path, inserisce i nuovi."""
    coll = _collection_name(config, staging)
    ensure_collection(client, coll)
    client.delete(
        collection_name=coll,
        points_selector=FilterSelector(
            filter=Filter(must=[FieldCondition(key="path", match=MatchValue(value=path))])
        ),
    )
    if not chunks:
        return
    points = [
        PointStruct(
            id=_point_id(path, c["chunk_id"]),
            vector=[float(v) for v in c["vector"]],
            payload={
                "path": path,
                "chunk_id": c["chunk_id"],
                "chunk_text": c["chunk_text"],
                "content_hash": c["content_hash"],
                "page_hash": c["page_hash"],
                "last_embedded": time.time(),
            },
        )
        for c in chunks
    ]
    client.upsert(collection_name=coll, points=points)


def promote_staging(client: QdrantClient, config: dict) -> None:
    """Promuove staging → wiki_pages e svuota staging."""
    staging_coll = _collection_name(config, staging=True)
    main_coll = _collection_name(config, staging=False)
    existing = [c.name for c in client.get_collections().collections]
    if staging_coll not in existing:
        return
    ensure_collection(client, main_coll)
    offset = None
    while True:
        records, offset = client.scroll(
            collection_name=staging_coll,
            limit=100,
            offset=offset,
            with_vectors=True,
            with_payload=True,
        )
        if not records:
            break
        paths = {r.payload["path"] for r in records}
        for p in paths:
            client.delete(
                collection_name=main_coll,
                points_selector=FilterSelector(
                    filter=Filter(must=[FieldCondition(key="path", match=MatchValue(value=p))])
                ),
            )
        client.upsert(
            collection_name=main_coll,
            points=[PointStruct(id=r.id, vector=r.vector, payload=r.payload) for r in records],
        )
        if offset is None:
            break
    client.delete_collection(staging_coll)


def rollback_staging(client: QdrantClient, config: dict) -> None:
    """Svuota staging senza toccare wiki_pages."""
    staging_coll = _collection_name(config, staging=True)
    existing = [c.name for c in client.get_collections().collections]
    if staging_coll in existing:
        client.delete_collection(staging_coll)


def query_similar(
    client: QdrantClient,
    config: dict,
    vector: list[float],
    k: int = 5,
    path_prefix: str = None,
) -> list[dict]:
    coll = _collection_name(config)
    ensure_collection(client, coll)
    limit = k * 4 if path_prefix else k
    results = client.query_points(
        collection_name=coll,
        query=vector,
        limit=limit,
        with_payload=True,
        with_vectors=True,
    ).points
    if path_prefix:
        results = [r for r in results if r.payload.get("path", "").startswith(path_prefix)][:k]
    return [
        {
            "path": r.payload["path"],
            "chunk_id": r.payload["chunk_id"],
            "chunk_text": r.payload["chunk_text"],
            "content_hash": r.payload["content_hash"],
            "page_hash": r.payload["page_hash"],
            "vector": r.vector,
            "_distance": 1.0 - r.score,
        }
        for r in results
    ]


def find_semantic_duplicates(
    client: QdrantClient,
    config: dict,
    auto_threshold: float = 0.90,
    warn_threshold: float = 0.75,
) -> list[dict]:
    coll = _collection_name(config)
    ensure_collection(client, coll)
    records = []
    offset = None
    while True:
        batch, offset = client.scroll(
            collection_name=coll,
            scroll_filter=Filter(must=[FieldCondition(key="chunk_id", match=MatchValue(value=0))]),
            limit=100,
            offset=offset,
            with_vectors=True,
            with_payload=True,
        )
        records.extend(batch)
        if offset is None:
            break
    records = [r for r in records if not r.payload.get("path", "").startswith("wiki/")]
    if len(records) < 2:
        return []
    paths = [r.payload["path"] for r in records]
    vectors = np.array([r.vector for r in records], dtype=np.float32)
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    vectors = vectors / norms
    sim_matrix = vectors @ vectors.T
    results = []
    n = len(paths)
    for i in range(n):
        for j in range(i + 1, n):
            sim = float(sim_matrix[i, j])
            if sim >= auto_threshold:
                results.append({"page_a": paths[i], "page_b": paths[j], "similarity": round(sim, 4), "action": "auto_merge"})
            elif sim >= warn_threshold:
                results.append({"page_a": paths[i], "page_b": paths[j], "similarity": round(sim, 4), "action": "warn"})
    return sorted(results, key=lambda x: x["similarity"], reverse=True)


def detect_renames(
    client: QdrantClient,
    config: dict,
    filesystem_paths: set[str],
    workspace: str,
) -> list[dict]:
    coll = _collection_name(config)
    ensure_collection(client, coll)
    records, _ = client.scroll(
        collection_name=coll,
        scroll_filter=Filter(must=[FieldCondition(key="chunk_id", match=MatchValue(value=0))]),
        limit=10000,
        with_payload=True,
    )
    db_paths = {r.payload["path"] for r in records}
    abs_to_rel = {
        p: os.path.relpath(p, workspace).replace("\\", "/")
        for p in filesystem_paths
    }
    rel_fs_paths = set(abs_to_rel.values())
    only_in_db = db_paths - rel_fs_paths
    only_in_fs = rel_fs_paths - db_paths
    db_hash_to_path = {
        r.payload["page_hash"]: r.payload["path"]
        for r in records
        if r.payload["path"] in only_in_db
    }
    rel_to_abs = {v: k for k, v in abs_to_rel.items()}
    renames = []
    for rel_path in only_in_fs:
        abs_path = rel_to_abs.get(rel_path, rel_path)
        try:
            with open(abs_path, encoding="utf-8") as f:
                content = f.read()
            h = hashlib.sha256(content.encode()).hexdigest()
            if h in db_hash_to_path:
                renames.append({"old_path": db_hash_to_path[h], "new_path": rel_path})
        except OSError:
            pass
    return renames
