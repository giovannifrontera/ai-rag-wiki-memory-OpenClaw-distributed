---
name: wiki-setup
description: Rigid step-by-step installation and verification for the distributed OpenClaw wiki memory system with Qdrant, Tailscale, Syncthing, the OpenClaw context plugin, and the server-side Syncthing ingest watchdog. Use when an agent must install, repair, verify, or explain setup on a server or client machine.
---

# Wiki Setup - Rigid Installer Protocol

This is a local skill file. Access it with `Read skills/wiki-setup.md`; do not call a Skill tool.

Follow every step in order. Do not skip verification. If a check fails, stop, report the exact failing command/output, and do not continue with later steps.

## Operating Rules

- Identify the machine role first: server or client.
- Use the repo root as `<REPO>` and the wiki workspace as `<WORKSPACE>`.
- Default `<WORKSPACE>` is `~/.openclaw/workspace`.
- Server means the machine that runs Qdrant locally.
- Client means any other machine that reaches Qdrant through Tailscale.
- Never edit `wiki.config.json` by hand when a script exists, unless the script failed and the user approves a manual fix.
- Never run destructive commands such as deleting old vector data, removing Syncthing folders, or resetting Git unless the user explicitly asks.
- Treat Tailscale login, Syncthing device pairing, and sudo/system package installation as user-assisted steps.

## Step 0 - Locate The Repo And Workspace

1. Find the repo root:

```bash
pwd
test -f requirements.txt
test -d scripts
test -d plugins/wiki-context-plugin
test -d skills
```

If any command fails, ask the user for the path to the cloned repo.

2. Choose workspace:

```bash
WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
echo "$WORKSPACE"
```

3. Check Python:

```bash
python3 --version || python --version || py --version
```

Use `python3` on Linux/macOS. Use `py` or the absolute Python executable on Windows.

## Step 1 - Choose Server Or Client

Ask or infer from the host:

```bash
curl -fsS http://localhost:6333/health >/dev/null 2>&1 && echo SERVER || echo CLIENT_OR_NOT_READY
```

- If this machine should host Qdrant, follow `Server Install`.
- If this machine should connect to another Qdrant host, follow `Client Install`.
- If unsure, ask the user: "Is this machine the Qdrant server or a client?"

## Server Install

Run this section only on the Qdrant server.

### S1 - Full Blind Installer

Prefer the full installer. It performs preflight checks, bootstraps the workspace, starts or verifies Qdrant, initializes the collection, starts Syncthing, enables the ingest watchdog, builds/configures the OpenClaw plugin, and runs final checks.

Linux:

```bash
./deploy/install-server-full.sh
```

With explicit workspace and OpenClaw config:

```bash
./deploy/install-server-full.sh ~/.openclaw/workspace <OPENCLAW_CONFIG_PATH>
```

Stop if the installer fails. Report the failed section and exact command output. Do not continue with fallback steps unless the user asks.

### S2 - Manual Preflight Fallback

Use this only if the full installer cannot be used.

Verify required commands:

```bash
python3 --version
git --version
```

Install optional OS tools with user approval:

```bash
sudo apt-get install syncthing inotify-tools
```

For Fedora use `sudo dnf install syncthing inotify-tools`. For macOS use `brew install syncthing`.

### S3 - Bootstrap Workspace

From `<REPO>`:

```bash
./deploy/setup-server.sh "$WORKSPACE"
```

Verify files were copied:

```bash
test -f "$WORKSPACE/wiki.config.json"
test -f "$WORKSPACE/scripts/wiki.py"
test -f "$WORKSPACE/scripts/wiki_context.py"
test -f "$WORKSPACE/scripts/watch-sync.sh"
test -f "$WORKSPACE/deploy/wiki-sync-watchdog.service"
test -d "$WORKSPACE/wiki"
test -d "$WORKSPACE/wiki-works"
```

### S4 - Start Qdrant

If Qdrant is already running, this passes:

```bash
curl -fsS http://localhost:6333/health
```

If it fails and Podman is available:

```bash
mkdir -p ~/.config/systemd/user
cp deploy/qdrant-podman.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now qdrant-podman
loginctl enable-linger "$USER"
curl -fsS http://localhost:6333/health
```

If using Docker:

```bash
docker volume create qdrant_data
docker run -d --name qdrant --restart unless-stopped -p 6333:6333 -p 6334:6334 -v qdrant_data:/qdrant/storage qdrant/qdrant:latest
curl -fsS http://localhost:6333/health
```

If using native systemd, follow `docs/install-qdrant.md`, then verify with the same curl command.

### S5 - Initialize Or Rebuild Qdrant Collection

If the workspace already has Markdown pages, rebuild the vector collection:

```bash
python3 "$WORKSPACE/scripts/wiki.py" rebuild --workspace "$WORKSPACE"
```

If the workspace is empty, create at least one test page through ingest:

```bash
mkdir -p "$WORKSPACE/wiki/concepts"
printf '# Setup Smoke Test\n\nTemporary setup validation page.\n' > "$WORKSPACE/wiki/concepts/setup-smoke-test.md.tmp"
python3 "$WORKSPACE/scripts/wiki.py" ingest --workspace "$WORKSPACE" --pages wiki/concepts/setup-smoke-test.md.tmp --log "setup | smoke test"
```

Verify query works:

```bash
python3 "$WORKSPACE/scripts/wiki.py" query --workspace "$WORKSPACE" --q "setup smoke test" --k 1
```

### S6 - Configure Tailscale

Install and log in with the user present. Use `docs/tailscale-setup.md` for OS-specific commands.

Verify Qdrant is reachable on the Tailscale interface:

```bash
tailscale status
tailscale ip -4
curl -fsS http://$(tailscale ip -4):6333/health
```

If the curl fails, check firewall rules. Do not expose Qdrant to the public internet.

### S7 - Configure Syncthing

Start Syncthing:

```bash
systemctl --user enable --now syncthing
loginctl enable-linger "$USER"
```

Open `http://localhost:8384` with the user present. Add `<WORKSPACE>` as folder `openclaw-workspace` and share it with clients.

Verify the ignore file exists:

```bash
test -f "$WORKSPACE/.stignore"
```

### S8 - Enable Server Ingest Watchdog

The watchdog closes the offline laptop gap: when Syncthing receives `.md` files, the server re-ingests them into Qdrant.

```bash
command -v inotifywait
mkdir -p ~/.config/systemd/user
cp "$WORKSPACE/deploy/wiki-sync-watchdog.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now wiki-sync-watchdog
systemctl --user status wiki-sync-watchdog --no-pager
```

Verify the script syntax if Bash is available:

```bash
bash -n "$WORKSPACE/scripts/watch-sync.sh"
```

### S9 - Install OpenClaw Plugin On Server

Build the plugin from `<REPO>`:

```bash
cd plugins/wiki-context-plugin
npm install
npm run build
cd ../..
```

Inject the plugin config:

```bash
python3 scripts/setup_openclaw.py --workspace "$WORKSPACE"
```

If auto-detection fails, rerun with:

```bash
python3 scripts/setup_openclaw.py --workspace "$WORKSPACE" --config <OPENCLAW_CONFIG_PATH>
```

Restart OpenClaw.

### S10 - Server Final Verification

Run all checks:

```bash
python3 "$WORKSPACE/scripts/wiki_check_setup.py" --workspace "$WORKSPACE"
python3 "$WORKSPACE/scripts/wiki_context.py" --workspace "$WORKSPACE" --q "setup smoke test" --k 1
python3 "$WORKSPACE/scripts/wiki.py" lint --workspace "$WORKSPACE" --full
```

Expected:

- `wiki_check_setup.py` prints `<wiki-briefing>`, not `<wiki-setup-required>`.
- `wiki_context.py` prints a `<wiki-context>` block or a valid no-context result.
- `wiki.py lint` returns JSON with `"status": "ok"`.

## Client Install

Run this section only on laptops/clients.

### C1 - Full Blind Installer

Prefer the full installer. It performs preflight checks, verifies Qdrant reachability, bootstraps the workspace, installs Python dependencies, builds the OpenClaw plugin, injects the plugin config, and runs final checks.

Linux/macOS/Git Bash:

```bash
./deploy/install-client-full.sh <QDRANT_SERVER_TAILSCALE_HOST_OR_IP>
```

Windows PowerShell:

```powershell
.\deploy\install-client-full.ps1 -QdrantHost <QDRANT_SERVER_TAILSCALE_HOST_OR_IP>
```

If OpenClaw config auto-detection fails, pass the config path explicitly:

```bash
./deploy/install-client-full.sh <QDRANT_SERVER_TAILSCALE_HOST_OR_IP> ~/.openclaw/workspace <OPENCLAW_CONFIG_PATH>
```

```powershell
.\deploy\install-client-full.ps1 -QdrantHost <QDRANT_SERVER_TAILSCALE_HOST_OR_IP> -OpenClawConfig <OPENCLAW_CONFIG_PATH>
```

Stop if the installer fails. Report the failed section and exact command output. Do not continue with fallback steps unless the user asks.

### C2 - Manual Preflight Fallback

Use this only if the full installer cannot be used.

Install or verify Tailscale and Syncthing with the user present:

```bash
tailscale status
syncthing --version
python3 --version || python --version || py --version
```

Verify Qdrant server reachability:

```bash
curl -fsS http://<QDRANT_SERVER_TAILSCALE_HOST_OR_IP>:6333/health
```

If this fails, do not continue. Fix Tailscale, hostname, or firewall first.

### C3 - Bootstrap Client Workspace

From `<REPO>`:

```bash
./deploy/setup-client.sh <QDRANT_SERVER_TAILSCALE_HOST_OR_IP>
```

Verify local config:

```bash
test -f "$HOME/.openclaw/workspace/wiki.config.json"
test -f "$HOME/.openclaw/workspace/scripts/wiki.py"
test -f "$HOME/.openclaw/workspace/scripts/wiki_context.py"
test -f "$HOME/.openclaw/workspace/skills/wiki-core.md"
python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path.home().joinpath(".openclaw/workspace/wiki.config.json").read_text())
assert cfg["qdrant"]["host"] not in ("localhost", "127.0.0.1")
print(cfg["qdrant"])
PY
```

### C4 - Pair Syncthing

Open `http://localhost:8384` with the user present.

1. Add the server device.
2. Accept the shared `openclaw-workspace` folder.
3. Set local path to `~/.openclaw/workspace`.
4. Wait until Syncthing reports "Up to Date".

Verify files arrived:

```bash
test -d "$HOME/.openclaw/workspace/wiki"
test -d "$HOME/.openclaw/workspace/wiki-works"
test -f "$HOME/.openclaw/workspace/.stignore"
```

### C5 - Install Python Dependencies

From `<REPO>`:

```bash
python3 -m pip install -r requirements.txt
```

On Windows use:

```powershell
py -m pip install -r requirements.txt
```

### C6 - Install OpenClaw Plugin On Client

Build the plugin:

```bash
cd plugins/wiki-context-plugin
npm install
npm run build
cd ../..
```

Inject the plugin config:

```bash
python3 scripts/setup_openclaw.py --workspace "$HOME/.openclaw/workspace"
```

If OpenClaw runs with a different Python, set it explicitly:

```bash
python3 scripts/setup_openclaw.py --workspace "$HOME/.openclaw/workspace" --python "$(python3 -c 'import sys; print(sys.executable)')"
```

Restart OpenClaw.

### C7 - Client Final Verification

Run:

```bash
python3 "$HOME/.openclaw/workspace/scripts/wiki_check_setup.py" --workspace "$HOME/.openclaw/workspace"
python3 "$HOME/.openclaw/workspace/scripts/wiki_context.py" --workspace "$HOME/.openclaw/workspace" --q "setup smoke test" --k 1
python3 "$HOME/.openclaw/workspace/scripts/wiki.py" query --workspace "$HOME/.openclaw/workspace" --q "setup smoke test" --k 1
```

Expected:

- Qdrant queries go to the remote host configured in `wiki.config.json`.
- `wiki_check_setup.py` prints `<wiki-briefing>`.
- Query returns JSON with `"status": "ok"`.

## Offline-Reconnect Validation

Use this on a client after server watchdog is enabled.

1. Disconnect Tailscale or go offline.
2. Create a local page:

```bash
mkdir -p "$HOME/.openclaw/workspace/wiki/concepts"
printf '# Offline Sync Test\n\nCreated while the client was offline.\n' > "$HOME/.openclaw/workspace/wiki/concepts/offline-sync-test.md"
```

3. Reconnect Tailscale and Syncthing.
4. On the server, watch logs:

```bash
journalctl --user -u wiki-sync-watchdog -n 50 --no-pager
```

5. Query from either machine:

```bash
python3 "$HOME/.openclaw/workspace/scripts/wiki.py" query --workspace "$HOME/.openclaw/workspace" --q "offline sync test" --k 1
```

Expected: the new page appears in query results. If it does not, check Syncthing status first, then watchdog logs, then Qdrant health.

## Stop Conditions

Stop and report before continuing if any of these are true:

- `wiki.config.json` is missing or invalid JSON.
- Qdrant health check fails on the server.
- Client cannot reach server Qdrant through Tailscale.
- Syncthing shows conflicts matching `*.sync-conflict-*`.
- `wiki_check_setup.py` prints `<wiki-setup-required>`.
- OpenClaw config cannot be found by `setup_openclaw.py`.
- The OpenClaw plugin build fails.

## Handoff Summary

At the end, report:

- Machine role: server or client.
- Workspace path.
- Qdrant host and port from `wiki.config.json`.
- Syncthing status: paired and up to date, or pending user action.
- OpenClaw plugin status: installed and OpenClaw restarted, or pending user action.
- Watchdog status on server: enabled/running, or not applicable on client.
- Verification commands run and their pass/fail result.
