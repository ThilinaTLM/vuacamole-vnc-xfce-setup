#!/usr/bin/env bash
# Install repo-tracked host desktop configs (Sway + wayvnc + user systemd unit)
# into the current user's home directory, then reload the user systemd manager.
#
# Idempotent: re-running overwrites the installed copies with the repo versions.
# Does NOT install packages, enable linger, or start the service — those steps
# require sudo or a deliberate action and are only printed at the end.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo_root/host"

sway_dir="$HOME/.config/sway"
wayvnc_dir="$HOME/.config/wayvnc"
unit_dir="$HOME/.config/systemd/user"

echo "==> Creating config directories"
mkdir -p "$sway_dir" "$wayvnc_dir" "$unit_dir"

# Detect the Docker bridge gateway so wayvnc binds to the host-internal address
# that guacd reaches via host.docker.internal (host-gateway).
gateway="$(ip -4 addr show docker0 2>/dev/null | grep -oP 'inet \K[\d.]+' || true)"
if [ -z "$gateway" ]; then
    gateway="172.17.0.1"
    echo "==> docker0 not found; defaulting wayvnc bind to ${gateway}"
    echo "    Verify later with: ip -4 addr show docker0"
else
    echo "==> Detected Docker bridge gateway: ${gateway}"
fi

echo "==> Installing Sway config (binding wayvnc to ${gateway}:5901)"
sed "s/@DOCKER_BRIDGE_GATEWAY@/${gateway}/" "$src/sway/config" > "$sway_dir/config"

echo "==> Installing wayvnc config"
cp "$src/wayvnc/config" "$wayvnc_dir/config"

echo "==> Installing user systemd unit"
cp "$src/systemd/sway-headless.service" "$unit_dir/sway-headless.service"

echo "==> Reloading user systemd manager"
if systemctl --user daemon-reload 2>/dev/null; then
    echo "    daemon-reload OK"
else
    echo "    WARNING: 'systemctl --user daemon-reload' failed."
    echo "    You likely need a user systemd manager (see linger note below)."
fi

cat <<EOF

==> Installed:
    $sway_dir/config
    $wayvnc_dir/config
    $unit_dir/sway-headless.service

==> Remaining one-time host steps (run manually; they need sudo):

    # Packages
    sudo pacman -S --needed sway wayvnc foot fuzzel xorg-xwayland seatd

    # Allow the user systemd manager to run without an interactive login
    sudo loginctl enable-linger "\$USER"

    # Optional/fallback only — if Sway complains about seat/session access:
    # sudo systemctl enable --now seatd
    # sudo usermod -aG seat "\$USER"

==> Then start the desktop on demand:

    systemctl --user start sway-headless
    systemctl --user status sway-headless
    ss -ltnp | grep 5901    # expect wayvnc on ${gateway}:5901

EOF
