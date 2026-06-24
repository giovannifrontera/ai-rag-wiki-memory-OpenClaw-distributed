# Install Qdrant

Qdrant runs only on the server. Clients reach it over Tailscale.

## Verify

```bash
curl http://localhost:6333/health
```

Expected: JSON containing `qdrant - vector search engine`.

## Docker

```bash
docker volume create qdrant_data
docker run -d \
  --name qdrant \
  --restart unless-stopped \
  -p 6333:6333 \
  -p 6334:6334 \
  -v qdrant_data:/qdrant/storage \
  qdrant/qdrant:latest
```

## Podman Rootless

```bash
mkdir -p ~/.config/systemd/user
cp deploy/qdrant-podman.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now qdrant-podman
loginctl enable-linger "$USER"
```

The bundled unit publishes `6333` and `6334` on all interfaces. If the host firewall is enabled, allow access from the Tailscale interface only.

## Native Binary With Systemd

Install the `qdrant` binary, then adjust paths and user in `deploy/qdrant.service`:

```ini
User=<your-user>
WorkingDirectory=/home/<your-user>/.qdrant
ExecStart=/home/<your-user>/.local/bin/qdrant
```

Then:

```bash
sudo cp deploy/qdrant.service /etc/systemd/system/qdrant.service
sudo systemctl daemon-reload
sudo systemctl enable --now qdrant
```

## Binding And Network

For a distributed install, Qdrant must be reachable from clients through Tailscale:

```bash
curl http://<server-tailscale-hostname-or-ip>:6333/health
```

Do not expose Qdrant directly to the public internet.
