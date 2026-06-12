#!/usr/bin/env bash
# Tear down the Docker gateway stack, host xrdp services, and any running XFCE
# sessions. PostgreSQL is left running.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Stopping Docker stack"
docker compose down

echo "==> Stopping host xrdp/xrdp-sesman services"
sudo systemctl stop xrdp xrdp-sesman

# Stopping xrdp does NOT clean up live desktop sessions. Killing only
# xfce4-session reparents its children (xfwm4, xfce4-panel, xfdesktop, ...) to
# init, where they linger and keep holding their D-Bus names — which then
# blocks the next session from starting and yields a black screen. So tear down
# the whole desktop tree and the xrdp Xorg display servers.
echo "==> Stopping running XFCE sessions and xrdp Xorg displays"
for proc in \
    xfce4-session xfwm4 xfce4-panel xfdesktop xfsettingsd \
    xfce4-appfinder xfce4-notifyd xfconfd Thunar; do
    sudo pkill -x "$proc" 2>/dev/null || true
done
sudo pkill -f 'xfce4/panel/wrapper' 2>/dev/null || true
# xrdp's per-session Xorg servers (e.g. "/usr/lib/Xorg :10 ... xrdp/xorg.conf").
sudo pkill -f '/usr/lib/Xorg .* xrdp/xorg.conf' 2>/dev/null || true

echo "==> Down. PostgreSQL left running."
