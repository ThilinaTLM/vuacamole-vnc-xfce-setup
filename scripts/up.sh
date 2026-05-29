#!/usr/bin/env bash
# Start the remote desktop on demand: host Sway/wayvnc session + Docker stack.
set -euo pipefail
cd "$(dirname "$0")/.."

DESKTOP_SERVICE="${DESKTOP_SERVICE:-sway-headless}"

echo "==> Starting headless Sway desktop (systemctl --user start ${DESKTOP_SERVICE})"
systemctl --user start "${DESKTOP_SERVICE}"

echo "==> Starting Docker stack (caddy + guacamole + guacd)"
docker compose up -d

DOMAIN="$(grep -E '^GUAC_DOMAIN=' .env 2>/dev/null | cut -d= -f2-)"
echo "==> Up. Open: https://${DOMAIN:-<GUAC_DOMAIN>}"
