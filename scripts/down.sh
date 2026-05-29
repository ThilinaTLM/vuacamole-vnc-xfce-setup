#!/usr/bin/env bash
# Tear down the Docker gateway stack, host xrdp services, and any running XFCE
# sessions. PostgreSQL is left running.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Stopping Docker stack"
docker compose down

echo "==> Stopping host xrdp/xrdp-sesman services"
sudo systemctl stop xrdp xrdp-sesman

echo "==> Stopping running XFCE sessions"
sudo pkill -x xfce4-session || true

echo "==> Down. PostgreSQL left running."
