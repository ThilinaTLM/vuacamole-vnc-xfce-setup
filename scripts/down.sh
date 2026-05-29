#!/usr/bin/env bash
# Tear down the Docker gateway stack. PostgreSQL and host xrdp services are left
# running; xrdp is a small boot service and XFCE sessions are connection-driven.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Stopping Docker stack"
docker compose down

echo "==> Down. PostgreSQL and xrdp/xrdp-sesman left running."
