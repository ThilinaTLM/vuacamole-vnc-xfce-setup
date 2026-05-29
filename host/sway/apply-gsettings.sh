#!/usr/bin/env bash
# Apply desktop appearance + reduced-motion preferences via gsettings.
# Installed to ~/.config/sway/apply-gsettings.sh and run from the Sway config
# with `exec_always` (so it re-applies on reload). Idempotent and best-effort:
# if gsettings/schemas are missing it exits 0 without breaking the session.
#
# These settings are surfaced to apps by xdg-desktop-portal-gtk, so Firefox /
# Chromium report prefers-color-scheme: dark and prefers-reduced-motion: reduce.

command -v gsettings >/dev/null 2>&1 || exit 0

iface="org.gnome.desktop.interface"

set_key() { gsettings set "$iface" "$1" "$2" 2>/dev/null || true; }

set_key color-scheme       "prefer-dark"
set_key enable-animations  false
set_key gtk-theme          "Adwaita-dark"
set_key icon-theme         "Papirus-Dark"
set_key cursor-theme       "Adwaita"
set_key cursor-size        24
set_key font-name          "IosevkaTerm Nerd Font 11"
set_key monospace-font-name "IosevkaTerm Nerd Font 11"

# Reduced motion for GNOME/accessibility-aware apps.
gsettings set org.gnome.desktop.a11y.interface high-contrast false 2>/dev/null || true

exit 0
