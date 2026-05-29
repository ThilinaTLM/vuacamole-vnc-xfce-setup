#!/usr/bin/env bash
# Start the remote desktop gateway on demand. Host xrdp/xrdp-sesman run as
# system boot services; XFCE sessions start when a user logs in over RDP.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! systemctl is-active --quiet xrdp || ! systemctl is-active --quiet xrdp-sesman; then
    echo "WARNING: xrdp/xrdp-sesman are not active. Run:"
    echo "    sudo systemctl enable --now xrdp xrdp-sesman"
fi

echo "==> Starting Docker stack (caddy + guacamole + guacd)"
docker compose up -d

DOMAIN="$(grep -E '^GUAC_DOMAIN=' .env 2>/dev/null | cut -d= -f2-)"
echo "==> Up. Open: https://${DOMAIN:-<GUAC_DOMAIN>}"
