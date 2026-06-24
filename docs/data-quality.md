# Data Quality

## Double `.md.md` Files

Files such as `riti-goetia-infernal-summoning.md.md` are ingest artifacts. They usually come from creating a temporary page with a slug that already includes `.md`, then appending `.md.tmp`.

Correct pattern:

```text
wiki-works/<project>/concepts/riti-goetia-infernal-summoning.md.tmp
```

Wrong pattern:

```text
wiki-works/<project>/concepts/riti-goetia-infernal-summoning.md.md.tmp
```

## Detect

```bash
find ~/.openclaw/workspace/wiki ~/.openclaw/workspace/wiki-works -name '*.md.md'
```

## Clean

Use the built-in cleanup command:

```bash
python scripts/wiki.py cleanup --workspace ~/.openclaw/workspace
```

It removes stale `.tmp` files and renames `.md.md` files to `.md` when the destination does not already exist. If a destination already exists, it reports the conflict and leaves both files untouched.

After cleanup, run:

```bash
python scripts/wiki.py lint --workspace ~/.openclaw/workspace --full
```
