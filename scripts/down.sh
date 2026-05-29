#!/usr/bin/env bash
# Tear everything down to free RAM. PostgreSQL is left running (shared with dev).
set -euo pipefail
cd "$(dirname "$0")/.."

DESKTOP_SERVICE="${DESKTOP_SERVICE:-sway-headless}"

echo "==> Stopping Docker stack"
docker compose down

echo "==> Stopping headless Sway desktop (systemctl --user stop ${DESKTOP_SERVICE})"
systemctl --user stop "${DESKTOP_SERVICE}" || true

echo "==> Down. PostgreSQL left running."
