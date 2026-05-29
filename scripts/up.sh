#!/usr/bin/env bash
# Start the remote desktop gateway on demand. Host xrdp/xrdp-sesman are started
# here; XFCE sessions start when a user logs in over RDP.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Starting host xrdp/xrdp-sesman services"
sudo systemctl start xrdp xrdp-sesman

echo "==> Starting Docker stack (caddy + guacamole + guacd)"
docker compose up -d

DOMAIN="$(grep -E '^GUAC_DOMAIN=' .env 2>/dev/null | cut -d= -f2-)"
echo "==> Up. Open: https://${DOMAIN:-<GUAC_DOMAIN>}"
