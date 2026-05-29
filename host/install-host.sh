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
waybar_dir="$HOME/.config/waybar"
foot_dir="$HOME/.config/foot"
fuzzel_dir="$HOME/.config/fuzzel"
wallpaper_dir="$HOME/.config/wallpapers"
wallpaper="$wallpaper_dir/mocha.png"
gtk3_dir="$HOME/.config/gtk-3.0"
gtk4_dir="$HOME/.config/gtk-4.0"
qt5ct_dir="$HOME/.config/qt5ct"
qt6ct_dir="$HOME/.config/qt6ct"
swaync_dir="$HOME/.config/swaync"
nwgdrawer_dir="$HOME/.config/nwg-drawer"
envd_dir="$HOME/.config/environment.d"

echo "==> Creating config directories"
mkdir -p "$sway_dir" "$wayvnc_dir" "$unit_dir" \
    "$waybar_dir" "$foot_dir" "$fuzzel_dir" "$wallpaper_dir" \
    "$gtk3_dir" "$gtk4_dir" "$qt5ct_dir/colors" "$qt6ct_dir/colors" \
    "$swaync_dir" "$nwgdrawer_dir" "$envd_dir"

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

echo "==> Installing wallpaper"
cp "$src/wallpapers/mocha.png" "$wallpaper"

echo "==> Installing Sway config (binding wayvnc to ${gateway}:5901)"
# Substitute the wayvnc bind address and the absolute wallpaper path. Escape
# the wallpaper path for sed since it contains '/'.
wallpaper_esc="${wallpaper//\//\\/}"
sed -e "s/@DOCKER_BRIDGE_GATEWAY@/${gateway}/" \
    -e "s/@WALLPAPER@/${wallpaper_esc}/" \
    "$src/sway/config" > "$sway_dir/config"

echo "==> Installing wayvnc config"
cp "$src/wayvnc/config" "$wayvnc_dir/config"

echo "==> Installing Waybar config + style"
cp "$src/waybar/config.jsonc" "$waybar_dir/config.jsonc"
cp "$src/waybar/style.css" "$waybar_dir/style.css"

echo "==> Installing foot + fuzzel themes"
cp "$src/foot/foot.ini" "$foot_dir/foot.ini"
cp "$src/fuzzel/fuzzel.ini" "$fuzzel_dir/fuzzel.ini"

echo "==> Installing GTK 3/4 theming (dark Adwaita + Catppuccin accents, no animations)"
cp "$src/gtk/gtk-3.0/settings.ini" "$gtk3_dir/settings.ini"
cp "$src/gtk/gtk-3.0/gtk.css"     "$gtk3_dir/gtk.css"
cp "$src/gtk/gtk-4.0/settings.ini" "$gtk4_dir/settings.ini"
cp "$src/gtk/gtk-4.0/gtk.css"     "$gtk4_dir/gtk.css"

echo "==> Installing Qt 5/6 theming (qt5ct/qt6ct Fusion + Catppuccin palette)"
cp "$src/qt/qt5ct/colors/Catppuccin-Mocha.conf" "$qt5ct_dir/colors/Catppuccin-Mocha.conf"
cp "$src/qt/qt6ct/colors/Catppuccin-Mocha.conf" "$qt6ct_dir/colors/Catppuccin-Mocha.conf"
qt5ct_colors_esc="${qt5ct_dir//\//\\/}\\/colors\\/Catppuccin-Mocha.conf"
qt6ct_colors_esc="${qt6ct_dir//\//\\/}\\/colors\\/Catppuccin-Mocha.conf"
sed -e "s/@QT5CT_COLORS@/${qt5ct_colors_esc}/" "$src/qt/qt5ct/qt5ct.conf" > "$qt5ct_dir/qt5ct.conf"
sed -e "s/@QT6CT_COLORS@/${qt6ct_colors_esc}/" "$src/qt/qt6ct/qt6ct.conf" > "$qt6ct_dir/qt6ct.conf"

echo "==> Installing swaync notification center config + style"
cp "$src/swaync/config.json" "$swaync_dir/config.json"
cp "$src/swaync/style.css"   "$swaync_dir/style.css"

echo "==> Installing nwg-drawer (start-menu grid) style"
cp "$src/nwg-drawer/drawer.css" "$nwgdrawer_dir/drawer.css"

echo "==> Installing session environment + gsettings helper"
cp "$src/environment.d/desktop.conf" "$envd_dir/desktop.conf"
cp "$src/sway/apply-gsettings.sh" "$sway_dir/apply-gsettings.sh"
chmod +x "$sway_dir/apply-gsettings.sh"

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
    $waybar_dir/config.jsonc
    $waybar_dir/style.css
    $foot_dir/foot.ini
    $fuzzel_dir/fuzzel.ini
    $gtk3_dir/{settings.ini,gtk.css}
    $gtk4_dir/{settings.ini,gtk.css}
    $qt5ct_dir/{qt5ct.conf,colors/Catppuccin-Mocha.conf}
    $qt6ct_dir/{qt6ct.conf,colors/Catppuccin-Mocha.conf}
    $swaync_dir/{config.json,style.css}
    $nwgdrawer_dir/drawer.css
    $envd_dir/desktop.conf
    $sway_dir/apply-gsettings.sh
    $wallpaper

==> Remaining one-time host steps (run manually; they need sudo):

    # ttf-iosevkaterm-nerd: bar/terminal glyphs; papirus-icon-theme: app icons;
    # swaync: notifications; nwg-drawer: start-menu grid; qt5ct/qt6ct + Fusion:
    # Qt theming; gnome-themes-extra: Adwaita-dark; xdg-desktop-portal[-gtk]:
    # surfaces dark + reduced-motion to Firefox/Chromium.
    sudo pacman -S --needed sway swaybg waybar wayvnc foot fuzzel \
        xorg-xwayland seatd ttf-iosevkaterm-nerd papirus-icon-theme \
        swaync nwg-drawer qt5ct qt6ct gnome-themes-extra \
        xdg-desktop-portal xdg-desktop-portal-gtk

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
