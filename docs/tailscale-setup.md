# Tailscale Setup

Tailscale provides the private network between clients and the Qdrant server.

## Install

Ubuntu/Debian:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Fedora:

```bash
sudo dnf install tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

macOS:

```bash
brew install --cask tailscale
```

Windows:

```powershell
winget install Tailscale.Tailscale
```

## Find The Server Address

On the server:

```bash
tailscale status
tailscale ip -4
```

Use either the Tailscale hostname or the `100.x.y.z` address in client `wiki.config.json`.

## Verify Client Access

On every client:

```bash
tailscale status
curl http://<server-tailscale-hostname-or-ip>:6333/health
```

If this fails:

- Confirm Qdrant is running on the server.
- Confirm Qdrant is bound to an interface reachable from Tailscale, not only `127.0.0.1`.
- Check the host firewall and allow TCP `6333` from the Tailscale interface.

## Client Config

```bash
./deploy/setup-client.sh <server-tailscale-hostname-or-ip>
```

This updates `qdrant.host` in the local `wiki.config.json`.
