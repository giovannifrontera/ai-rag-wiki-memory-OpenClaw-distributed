# Syncthing Setup

Syncthing syncs Markdown files. Qdrant vectors are not synced.

## Install

Ubuntu/Debian:

```bash
sudo apt install syncthing
```

Fedora:

```bash
sudo dnf install syncthing
```

macOS:

```bash
brew install syncthing
```

Windows:

```powershell
winget install Syncthing.Syncthing
```

## Start

Linux user service:

```bash
systemctl --user enable --now syncthing
loginctl enable-linger "$USER"
```

Manual start:

```bash
syncthing
```

Open the UI at `http://localhost:8384`.

## Folder Layout

Use one shared folder:

```text
~/.openclaw/workspace
```

It contains:

```text
wiki/
wiki-works/
.stignore
```

Copy the ignore file on each machine:

```bash
cp deploy/syncthing-stignore ~/.openclaw/workspace/.stignore
```

`wiki.config.json` is intentionally ignored so each machine can keep its own `qdrant.host`.

## Server As Primary Node

1. On the server, add `~/.openclaw/workspace` as folder `openclaw-workspace`.
2. On each client, add the server's Syncthing Device ID.
3. On the server, accept the client device.
4. On the server folder settings, share `openclaw-workspace` with the client.
5. On the client, accept the folder and set the local path to `~/.openclaw/workspace`.

Use bidirectional sync for normal operation. The server is "primary" operationally because it runs Qdrant and maintenance jobs, not because Syncthing should be send-only.

## Conflict Handling

If a file named `*.sync-conflict-*` appears under `wiki/` or `wiki-works/`, stop wiki operations. Compare the original and conflict copy, choose or merge manually, then run:

```bash
python scripts/wiki.py lint --workspace ~/.openclaw/workspace --full
python scripts/wiki.py session-update --workspace ~/.openclaw/workspace --op sync-conflict --status ok
```
