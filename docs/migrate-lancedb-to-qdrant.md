# Migrate LanceDB To Qdrant

Run this once on the server when moving from the single-machine LanceDB repo to this distributed Qdrant repo.

## Preconditions

- Qdrant is running and reachable at `http://localhost:6333/health`.
- Markdown workspace has already been copied or synced to the server.
- `wiki.config.json` contains a `qdrant` section.
- `lancedb` is installed temporarily:

```bash
python3 -m pip install lancedb
```

## Config During Transition

The migration script only needs the old LanceDB path as an argument and the new Qdrant config:

```json
"qdrant": {
  "host": "localhost",
  "port": 6333,
  "collection": "wiki_pages"
}
```

If your old `wiki.config.json` still has a `lancedb` section, keep it until the migration is verified, but the distributed runtime uses `qdrant`.

## Dry Run

```bash
python scripts/migrate_lancedb_to_qdrant.py \
  --lancedb ~/.openclaw/workspace/memory/lancedb \
  --config ~/.openclaw/workspace/wiki.config.json \
  --dry-run
```

## Migrate

```bash
python scripts/migrate_lancedb_to_qdrant.py \
  --lancedb ~/.openclaw/workspace/memory/lancedb \
  --config ~/.openclaw/workspace/wiki.config.json
```

## Verify

```bash
curl http://localhost:6333/collections/wiki_pages
python scripts/wiki.py query --workspace ~/.openclaw/workspace --q "test" --k 3
```

Keep `memory/lancedb/` as a backup until queries work from at least one client.
