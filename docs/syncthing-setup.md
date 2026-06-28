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

## Server Ingest Watchdog

Syncthing only synchronizes Markdown files. It does not update Qdrant when a laptop creates or edits a page while offline and later reconnects. On the server, enable the bundled watchdog so every synced `.md` page is re-ingested into Qdrant.

Install the dependency:

```bash
sudo apt-get install inotify-tools
```

If you ran `deploy/setup-server.sh`, the script and service are already copied into the workspace. Enable the user service:

```bash
mkdir -p ~/.config/systemd/user
cp ~/.openclaw/workspace/deploy/wiki-sync-watchdog.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now wiki-sync-watchdog
loginctl enable-linger "$USER"
```

Check logs:

```bash
journalctl --user -u wiki-sync-watchdog -f
```

The watchdog monitors `wiki/` and `wiki-works/`, ignores `.tmp`, `*.sync-conflict-*`, and `wiki/index.md`, then runs:

```bash
python3 ~/.openclaw/workspace/scripts/wiki.py ingest \
  --workspace ~/.openclaw/workspace \
  --pages <relative-md-path>
```

It stores processed file hashes in `.synced-ingested.json`, so unchanged files do not trigger repeated ingest. `wiki.py ingest` replaces vectors by path, so reconnect races with a laptop-side ingest do not create duplicate vectors.

## Known Gotchas

### Windows: folder path defaults to the folder label, not the correct path

When the server shares a folder with a human-readable label (e.g. "Team Wiki"), Syncthing on Windows proposes that label as the local directory name. Files end up in `C:\Users\<you>\Team Wiki\` instead of `C:\Users\<you>\.openclaw\workspace\`.

**Fix:** immediately after accepting the shared folder in Syncthing UI, edit it and set the local path to `C:\Users\<you>\.openclaw\workspace`. Do this **before the first sync starts**. If the sync has already run in the wrong directory:

1. Pause the folder in Syncthing UI.
2. Remove the folder from the client's Syncthing config.
3. Re-accept the share from the server.
4. Set the correct local path this time.

### Ghost folders — server re-offers removed folders

If you remove a shared folder from the client's Syncthing config, the server will re-offer it on the next reconnect. Syncthing auto-accepts shares from trusted devices by default, so the folder silently reappears and consumes CPU generating spurious error logs.

**Workaround:** use **Pause** instead of Remove on the client side. To stop sync permanently, the server must remove this client from the folder's Sharing settings:

1. Server Syncthing UI → folder → Edit → Sharing tab.
2. Uncheck the client device.
3. Save.

After that the server stops offering the folder and the client can safely remove it.
