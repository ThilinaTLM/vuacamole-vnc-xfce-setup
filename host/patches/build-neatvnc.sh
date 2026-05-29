#!/usr/bin/env bash
# Rebuild a patched neatvnc that lets Guacamole/guacd dynamically resize the
# wayvnc desktop to match the browser viewport.
#
# Why: neatvnc advertises its ExtendedDesktopSize screen with id 0, but
# guacd's libvncclient discards any screen with id == 0 ("Screen data has not
# been initialized") and therefore never sends resize requests. The resize
# patch advertises a non-zero screen id (1), which also matches guacd's
# GUAC_VNC_SCREEN_ID, so the resize round-trip works.
#
# This overwrites the distro libneatvnc. A neatvnc package upgrade will revert
# it; re-run this script (and consider `IgnorePkg = neatvnc` in pacman.conf).
#
# Usage:  host/patches/build-neatvnc.sh
# Requires: git meson ninja gcc, plus neatvnc's build deps (already present if
# the neatvnc package is installed): aml pixman libdrm zlib gnutls
# libjpeg-turbo ffmpeg. The final install step uses sudo.
set -euo pipefail

# Match the installed neatvnc ABI (soname libneatvnc.so.0). Override if your
# distro moves on, but verify wayvnc still links libneatvnc.so.0 afterwards.
TAG="${NEATVNC_TAG:-v0.9.5}"
SRC_DIR="${NEATVNC_SRC:-$HOME/Projects/neatvnc}"

patches_dir="$(cd "$(dirname "$0")" && pwd)"

echo "==> Cloning neatvnc $TAG into $SRC_DIR"
rm -rf "$SRC_DIR"
git clone --depth 1 --branch "$TAG" https://github.com/any1/neatvnc.git "$SRC_DIR"
cd "$SRC_DIR"

echo "==> Applying Guacamole resize patch"
git apply "$patches_dir/neatvnc-guacd-resize.patch"

# nettle >= 4 build fix (EAX_DIGEST/aes128_digest signature + sha.h -> sha2.h).
# Guarded by NETTLE_VERSION_MAJOR, so it's a no-op on older nettle. Skip if it
# does not apply (e.g. already fixed upstream in a newer tag).
if git apply --check "$patches_dir/neatvnc-nettle-4.patch" 2>/dev/null; then
    echo "==> Applying nettle-4 build fix"
    git apply "$patches_dir/neatvnc-nettle-4.patch"
else
    echo "==> Skipping nettle-4 patch (does not apply / not needed)"
fi

echo "==> Building (features auto-detected to match the distro: tls/jpeg/h264)"
meson setup build --prefix=/usr --buildtype=release
ninja -C build

echo "==> Verifying soname + wayvnc symbols"
readelf -d build/libneatvnc.so.0.0.0 | grep -q 'libneatvnc.so.0' \
    && echo "    soname OK"
for s in $(nm -D /usr/bin/wayvnc 2>/dev/null | awk '/ U nvnc_/{print $2}'); do
    nm -D build/libneatvnc.so.0.0.0 | grep -qE " [TW] $s\$" \
        || { echo "    MISSING symbol: $s"; exit 1; }
done
echo "    all wayvnc-required symbols present"

echo "==> Installing patched library (sudo)"
sudo install -Dm755 build/libneatvnc.so.0.0.0 /usr/lib/libneatvnc.so.0.0.0
sudo ldconfig

echo "==> Done. Restart the desktop to load it:"
echo "    systemctl --user restart sway-headless"
