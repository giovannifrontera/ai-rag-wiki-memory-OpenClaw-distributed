#!/usr/bin/env python3
"""
Migrazione one-shot: LanceDB -> Qdrant.

Legge tutti i vettori dal LanceDB esistente e li inserisce in Qdrant.
I vettori bge-m3 vengono riusati as-is — nessun re-embedding.

Uso:
    python scripts/migrate_lancedb_to_qdrant.py \
        --lancedb ~/.openclaw/workspace/memory/lancedb \
        --config ~/.openclaw/workspace/wiki.config.json
"""

import argparse
import json
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Migra vettori da LanceDB a Qdrant")
    parser.add_argument("--lancedb", required=True, help="Path alla cartella lancedb")
    parser.add_argument("--config", required=True, help="Path a wiki.config.json")
    parser.add_argument("--dry-run", action="store_true", help="Mostra statistiche senza scrivere")
    args = parser.parse_args()

    lancedb_path = os.path.expanduser(args.lancedb)
    config_path = os.path.expanduser(args.config)

    if not os.path.exists(lancedb_path):
        print(f"ERRORE: LanceDB non trovato in {lancedb_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, encoding="utf-8") as f:
        cfg = json.load(f)

    try:
        import lancedb
    except ImportError:
        print("ERRORE: lancedb non installato. Installa temporaneamente con: pip install lancedb", file=sys.stderr)
        sys.exit(1)

    import wiki_qdrant
    from qdrant_client import QdrantClient

    db_lance = lancedb.connect(lancedb_path)
    table_list = db_lance.list_tables()
    tables = getattr(table_list, "tables", None) or list(table_list)

    if "wiki_pages" not in tables:
        print("Nessuna tabella wiki_pages trovata in LanceDB. Nulla da migrare.")
        sys.exit(0)

    table = db_lance.open_table("wiki_pages")
    df = table.to_pandas()
    print(f"Trovati {len(df)} chunk in LanceDB.")

    if args.dry_run:
        print("DRY RUN — nessuna scrittura su Qdrant.")
        print(f"Pagine uniche: {df['path'].nunique()}")
        return

    client = QdrantClient(
        host=cfg["qdrant"]["host"],
        port=cfg["qdrant"]["port"],
    )
    wiki_qdrant.ensure_collection(client, cfg["qdrant"]["collection"])

    migrated = 0
    for path in df["path"].unique():
        rows = df[df["path"] == path].to_dict("records")
        chunks = [
            {
                "chunk_id": int(r["chunk_id"]),
                "chunk_text": r["chunk_text"],
                "content_hash": r["content_hash"],
                "page_hash": r["page_hash"],
                "vector": list(r["vector"]),
            }
            for r in rows
        ]
        wiki_qdrant.upsert(client, cfg, path, chunks)
        migrated += len(chunks)
        print(f"  OK {path} ({len(chunks)} chunk)")

    print(f"\nMigrazione completata: {migrated} chunk da {df['path'].nunique()} pagine.")


if __name__ == "__main__":
    main()
