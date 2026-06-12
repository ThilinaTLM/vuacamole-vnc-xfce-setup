#!/usr/bin/env bash
# Install and configure the host desktop stack for XFCE over xrdp/xorgxrdp.
#
# This script performs both user-level config install and the required sudo host
# setup. Run it interactively so sudo can prompt for your password.
#
# Idempotent: re-running overwrites ~/.xinitrc, the XFCE xfconf appearance
# config, refreshes xrdp settings, and removes old repo-managed
# LXQt/Openbox/Sway/wayvnc user config artifacts.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo_root/host"

xfconf_dir="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
gtk3_dir="$HOME/.config/gtk-3.0"
gtk4_dir="$HOME/.config/gtk-4.0"
unit_dir="$HOME/.config/systemd/user"
polkit_power_rule_src="$src/polkit-1/rules.d/49-web-remote-desktop-no-power.rules"
polkit_power_rule_dst="/etc/polkit-1/rules.d/49-web-remote-desktop-no-power.rules"

packages=(
    xrdp xorgxrdp
    xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-settings xfconf
    xfce4-whiskermenu-plugin
    thunar xfce4-terminal xfce4-appfinder xfce4-notifyd garcon
    flameshot
    breeze-icons noto-fonts
)

old_package_candidates=(
    lxqt-session lxqt-panel lxqt-config lxqt-globalkeys lxqt-menu-data
    lxqt-notificationd lxqt-policykit lxqt-qtplugin lxqt-runner lxqt-themes
    pcmanfm-qt qterminal openbox obconf-qt
    sway swaybg waybar wayvnc foot fuzzel xorg-xwayland seatd
    ttf-iosevkaterm-nerd papirus-icon-theme swaync nwg-drawer
    qt5ct qt6ct xdg-desktop-portal xdg-desktop-portal-gtk
    autotiling swayr wl-clipboard cliphist grim slurp swappy wlogout neatvnc
    tigervnc
)

confirm_default_yes() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [Y/n] " reply
    case "${reply,,}" in
        n|no) return 1 ;;
        *) return 0 ;;
    esac
}

confirm_default_no() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N] " reply
    case "${reply,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Detect Docker bridge gateway for the xrdp bind address.
gateway="$(ip -4 addr show docker0 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}' || true)"
if [ -z "$gateway" ]; then
    gateway="172.17.0.1"
    echo "==> docker0 not found; defaulting xrdp bind to ${gateway}"
    echo "    Verify later with: ip -4 addr show docker0"
else
    echo "==> Detected Docker bridge gateway: ${gateway}"
fi

echo "==> Removing old repo-managed LXQt/Openbox/PCManFM user configs"
rm -rf \
    "$HOME/.config/lxqt" \
    "$HOME/.config/openbox" \
    "$HOME/.config/pcmanfm-qt"

echo "==> Removing old repo-managed Sway/wayvnc/Wayland user configs"
systemctl --user disable --now sway-headless.service 2>/dev/null || true
rm -f "$unit_dir/sway-headless.service"
systemctl --user daemon-reload 2>/dev/null || true
rm -rf \
    "$HOME/.config/sway" \
    "$HOME/.config/wayvnc" \
    "$HOME/.config/waybar" \
    "$HOME/.config/foot" \
    "$HOME/.config/fuzzel" \
    "$HOME/.config/swaync" \
    "$HOME/.config/nwg-drawer" \
    "$HOME/.config/swayr" \
    "$HOME/.config/wlogout"
rm -f "$HOME/.config/wallpapers/mocha.png"
rm -f "$HOME/.config/environment.d/desktop.conf"

echo "==> Removing old repo-managed Qt theme files"
rm -f \
    "$HOME/.config/qt5ct/qt5ct.conf" \
    "$HOME/.config/qt5ct/colors/Catppuccin-Mocha.conf" \
    "$HOME/.config/qt6ct/qt6ct.conf" \
    "$HOME/.config/qt6ct/colors/Catppuccin-Mocha.conf"

echo "==> Removing old TigerVNC user configs from previous remote-desktop setups"
rm -rf "$HOME/.vnc"

# Start from a clean XFCE config so stale settings from earlier setups do not
# linger, then install the repo-tracked appearance. Move the old directory out
# of the way instead of rm -rf so this works even if xfconfd is running and
# recreating files during the installer.
echo "==> Resetting and installing XFCE config"
if [ -e "$HOME/.config/xfce4" ]; then
    xfce_backup="$HOME/.config/xfce4.bak.$(date +%Y%m%d%H%M%S)"
    mv "$HOME/.config/xfce4" "$xfce_backup"
    echo "    Moved existing XFCE config to: $xfce_backup"
fi
mkdir -p "$xfconf_dir" "$gtk3_dir" "$gtk4_dir"

echo "==> Installing XFCE xrdp session launcher"
cp "$src/xfce/xinitrc" "$HOME/.xinitrc"
chmod +x "$HOME/.xinitrc"

echo "==> Installing XFCE appearance, panel, session, and keyboard config"
cp "$src/xfce/xfconf/xfce-perchannel-xml/"*.xml "$xfconf_dir/"

# Minimal GTK dark preference for GTK dialogs/apps.
echo "==> Installing GTK dark-mode preference"
cp "$src/gtk-3.0/settings.ini" "$gtk3_dir/settings.ini"
cp "$src/gtk-4.0/settings.ini" "$gtk4_dir/settings.ini"

echo "==> Requesting sudo credentials for host package/service setup"
sudo -v

echo "==> Installing lightweight XFCE + xrdp/X11 host stack"
sudo pacman -S --needed "${packages[@]}"

echo "==> Installing polkit rule to block remote shutdown/reboot/sleep"
sudo install -D -m 0644 "$polkit_power_rule_src" "$polkit_power_rule_dst"
sudo systemctl try-reload-or-restart polkit.service 2>/dev/null || true

echo "==> Configuring xrdp to bind only to ${gateway}:3389"
ts="$(date +%Y%m%d%H%M%S)"
sudo cp /etc/xrdp/xrdp.ini "/etc/xrdp/xrdp.ini.bak.${ts}"
sudo sed -i -E "0,/^port=.*/s|^port=.*|port=tcp://${gateway}:3389|" /etc/xrdp/xrdp.ini

if ! sudo grep -q "^port=tcp://${gateway}:3389$" /etc/xrdp/xrdp.ini; then
    echo "ERROR: Failed to set xrdp bind address in /etc/xrdp/xrdp.ini" >&2
    exit 1
fi

echo "==> Configuring xrdp-sesman Xorg path for Arch"
sudo cp /etc/xrdp/sesman.ini "/etc/xrdp/sesman.ini.bak.${ts}"
sudo awk '
  BEGIN { in_xorg=0; replaced=0 }
  /^\[Xorg\]/ { in_xorg=1; replaced=0; print; next }
  /^\[/ && $0 !~ /^\[Xorg\]/ { in_xorg=0; print; next }
  in_xorg && !replaced && /^param=/ { print "param=/usr/lib/Xorg"; replaced=1; next }
  { print }
' /etc/xrdp/sesman.ini | sudo tee /etc/xrdp/sesman.ini.tmp >/dev/null
sudo mv /etc/xrdp/sesman.ini.tmp /etc/xrdp/sesman.ini

echo "==> Enabling and starting xrdp services"
sudo systemctl enable --now xrdp xrdp-sesman

if confirm_default_yes "Remove old LXQt/Openbox/Sway/Wayland/TigerVNC packages now?"; then
    echo "==> Removing old desktop packages if installed"
    remove_pkgs=()
    for p in "${old_package_candidates[@]}"; do
        pacman -Q "$p" >/dev/null 2>&1 && remove_pkgs+=("$p")
    done

    if ((${#remove_pkgs[@]})); then
        printf '    %s\n' "${remove_pkgs[@]}"
        sudo pacman -Rns -- "${remove_pkgs[@]}"
    else
        echo "    No old LXQt/Sway/Wayland/TigerVNC packages found."
    fi

    echo "==> Removing old TigerVNC system service/config if present"
    sudo systemctl disable --now 'vncserver@:1.service' 2>/dev/null || true
    sudo rm -f /etc/tigervnc/vncserver.users
else
    echo "==> Skipped old package removal. Re-run this script later or see docs/xfce-xrdp.md."
fi

if confirm_default_no "Remove all pacman orphan packages now? This may include unrelated packages"; then
    mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
    if ((${#orphans[@]})); then
        printf '    %s\n' "${orphans[@]}"
        sudo pacman -Rns -- "${orphans[@]}"
    else
        echo "    No orphan packages found."
    fi
fi

cat <<EOF

==> Installed and configured:
    $HOME/.xinitrc
    $xfconf_dir/xsettings.xml
    $xfconf_dir/xfwm4.xml
    $xfconf_dir/xfce4-panel.xml
    $xfconf_dir/xfce4-desktop.xml
    $xfconf_dir/xfce4-session.xml
    $xfconf_dir/keyboard-shortcuts.xml
    $gtk3_dir/settings.ini
    $gtk4_dir/settings.ini
    $polkit_power_rule_dst
    /etc/xrdp/xrdp.ini      (backup: /etc/xrdp/xrdp.ini.bak.${ts})
    /etc/xrdp/sesman.ini    (backup: /etc/xrdp/sesman.ini.bak.${ts})

==> Verify xrdp is active and bound to the Docker bridge IP, not 0.0.0.0:
    systemctl status xrdp xrdp-sesman --no-pager
    ss -ltnp | grep ':3389'

==> Then start the web gateway:
    make up

EOF
