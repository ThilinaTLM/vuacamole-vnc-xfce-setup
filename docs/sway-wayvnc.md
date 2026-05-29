# Host desktop: Sway + wayvnc (headless)

The host-side remote desktop is a **headless Sway** compositor exposed over VNC by
**wayvnc** on port `5901`. guacd connects to it exactly like the old TigerVNC setup:

```text
guacd ─► VNC ─► wayvnc ─► Sway headless session (host :5901)
```

Everything is **on-demand** and runs as a **user** systemd service, so normal
`make up` / `make down` needs no `sudo` after the one-time setup below.

---

## 1. Install packages (one-time, sudo)

```bash
sudo pacman -S --needed sway swaybg waybar wayvnc foot fuzzel \
    xorg-xwayland seatd ttf-iosevkaterm-nerd papirus-icon-theme \
    swaync nwg-drawer qt5ct qt6ct gnome-themes-extra \
    xdg-desktop-portal xdg-desktop-portal-gtk
```

- `sway` — the Wayland compositor (uses the wlroots headless backend here).
- `swaybg` — draws the desktop wallpaper.
- `waybar` — bottom panel (Catppuccin Mocha; see *Appearance / theming* below).
- `wayvnc` — VNC server for wlroots compositors.
- `foot` — terminal; `fuzzel` — quick-run launcher (`$mod+Shift+d`).
- `nwg-drawer` — the start-menu **app grid** (start button / `$mod+d`).
- `swaync` — notification daemon + control center (the panel's bell).
- `ttf-iosevkaterm-nerd` — Nerd Font used by the bar/terminal for icon glyphs.
- `papirus-icon-theme` — dark app icons (tray, GTK/Qt apps, app grid).
- `qt5ct` / `qt6ct` — Qt 5/6 theming (Fusion + Catppuccin palette).
- `gnome-themes-extra` — provides the `Adwaita-dark` GTK theme.
- `xdg-desktop-portal` + `-gtk` — surface dark mode + reduced motion to
  Firefox/Chromium (so they report `prefers-color-scheme: dark` and
  `prefers-reduced-motion: reduce`).
- `xorg-xwayland` — runs legacy X11 apps inside Sway (full `xorg-server` not needed).
- `seatd` — only a fallback if the headless session complains about seat access.

Verify versions:

```bash
sway --version
wayvnc --version     # want >= 0.8 for server-side resize of headless outputs
```

## 2. Enable linger (one-time, sudo)

The user systemd manager must be able to run without an interactive login:

```bash
sudo loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger    # expect Linger=yes
```

This leaves a small idle user-manager footprint — idle RAM is "near zero beyond
PostgreSQL / the user manager", not literally zero.

## 3. Install the repo configs

From the repo root:

```bash
./host/install-host.sh
```

This copies the tracked configs into your home directory, substitutes the detected
Docker bridge gateway into the Sway `exec wayvnc` line, and runs
`systemctl --user daemon-reload`:

```text
host/sway/config              → ~/.config/sway/config
host/wayvnc/config            → ~/.config/wayvnc/config
host/waybar/config.jsonc      → ~/.config/waybar/config.jsonc
host/waybar/style.css         → ~/.config/waybar/style.css
host/foot/foot.ini            → ~/.config/foot/foot.ini
host/fuzzel/fuzzel.ini        → ~/.config/fuzzel/fuzzel.ini
host/wallpapers/mocha.png     → ~/.config/wallpapers/mocha.png
host/systemd/sway-headless.service → ~/.config/systemd/user/sway-headless.service
```

The installer substitutes two placeholders into the Sway config: the detected
Docker bridge gateway (`@DOCKER_BRIDGE_GATEWAY@`) and the absolute wallpaper
path (`@WALLPAPER@`).

Verify it landed:

```bash
systemctl --user cat sway-headless
ls -l ~/.config/sway/config ~/.config/wayvnc/config
grep '^exec wayvnc' ~/.config/sway/config   # confirm the bind address/port
```

---

## Start / stop / status

```bash
systemctl --user start  sway-headless
systemctl --user stop   sway-headless
systemctl --user status sway-headless
journalctl --user -u sway-headless -b --no-pager
```

`make up` / `make down` (and `make desk-up` / `make desk-down`) wrap these.

Check wayvnc is listening on the Docker bridge gateway:

```bash
ss -ltnp | grep 5901
```

If `swaymsg` can reach the running session, confirm the headless output:

```bash
swaymsg -t get_outputs    # expect HEADLESS-1
```

---

## Appearance / theming (Catppuccin Mocha)

The desktop uses a flat **Catppuccin Mocha** theme with a KDE Plasma feel: a
layered-mountains wallpaper and a **compact, edge-to-edge bottom panel**
(**Waybar**, 28 px). The panel has a mauve **start button** that opens the
`nwg-drawer` **app grid** and a workspace **pager** on the left; the center is
intentionally empty (no task list — this is a tiling WM, so window switching is
done with the keyboard and the pager, leaving maximum height for content); and
the right holds the system **tray**, a **notification bell** (toggles the
`swaync` control center), and a **clock**. Inner/outer gaps and a mauve accent
on the focused window border finish the Sway side.

App theming matches the desktop: **GTK 3/4** use `Adwaita-dark` with Catppuccin
Mocha accent overrides (`host/gtk/`), and **Qt 5/6** route through
`qt5ct`/`qt6ct` with the Fusion style and a Catppuccin Mocha palette
(`host/qt/`), selected via `QT_QPA_PLATFORMTHEME=qt6ct` in
`host/environment.d/desktop.conf`. Glyphs come from `IosevkaTerm Nerd Font` and
icons from `Papirus-Dark`.

**Everything is flat and instant — no animations.** This is enforced in layers
(see *Why no … animations* below): GTK's `gtk-enable-animations=0` plus the
gsettings `enable-animations false` (applied by `host/sway/apply-gsettings.sh`)
turn off GTK-app motion *and* make Firefox/Chromium report
`prefers-reduced-motion: reduce`; Qt uses the (near-static) Fusion style; and
Waybar/swaync/nwg-drawer stylesheets all set `transition: none`. The same
gsettings + `xdg-desktop-portal-gtk` push `color-scheme: prefer-dark`, so
browsers and portal-aware apps go dark automatically.

All of it lives in `host/` and is installed by `install-host.sh`. To tweak the
look, edit the repo files and re-run the installer, then reload Sway:

```bash
./host/install-host.sh
swaymsg reload          # or: systemctl --user restart sway-headless
```

### Why no SwayFX / blur / shadows / animations

This is intentional, for two reasons specific to this setup:

1. **Software rendering.** `sway-headless.service` forces `WLR_RENDERER=pixman`
   (CPU, no GPU). SwayFX's effects (`fx_renderer`) require GLES2/OpenGL and will
   not run on the pixman backend.
2. **VNC stream.** The session is re-encoded and sent to the browser through
   guacd/wayvnc. Animated pixels (blur, shadows, motion, live widgets like
   `cava`, per-second repaints) cost CPU and bandwidth on every frame. A flat,
   mostly-static look compresses well and a static wallpaper is free after the
   first frame.

For that reason the Waybar `clock` updates per minute, the panel carries only
lightweight modules (start button, pager, tray, notification bell, clock), and
nothing animates — toolkit animations are disabled globally (see above).

### Regenerating the wallpaper

The wallpaper is a committed PNG; `host/wallpapers/generate.py` reproduces it
(stdlib only — no ImageMagick/PIL needed) and accepts an output path, size, and
style (`mountains` default, or `gradient` for the lighter original):

```bash
python3 host/wallpapers/generate.py host/wallpapers/mocha.png 1920 1080 mountains
```

To skip the wallpaper entirely, set the fallback solid color in
`host/sway/config`:

```text
output HEADLESS-1 bg #1e1e2e solid_color
```

---

## Guacamole connection settings

| Field    | Value                  |
| -------- | ---------------------- |
| Name     | `Arch Sway`            |
| Protocol | `VNC`                  |
| Hostname | `host.docker.internal` |
| Port     | `5901`                 |
| Password | **blank / cleared**    |

The VNC password field **must be empty** — wayvnc runs with auth disabled (see below).

---

## Browser-responsive resolution (dynamic resize)

The desktop resizes to match the browser viewport (on connect and on window
resize). This needs a **patched neatvnc** because of an incompatibility between
stock wayvnc/neatvnc and Guacamole's VNC auto-resize (added in Guacamole 1.6.0):

- neatvnc advertises its `ExtendedDesktopSize` screen with **id 0**.
- guacd's libvncclient **discards any screen whose id is 0** (treats it as
  invalid), so it never initialises `client->screen` and logs
  `Screen data has not been initialized` / `Failed to send desktop size
  message`, refusing every resize.
- The fix advertises a **non-zero screen id (1)**, which also matches guacd's
  `GUAC_VNC_SCREEN_ID = 1`, so the full resize round-trip works.

The one-line change plus a build helper live in `host/patches/`:

```bash
host/patches/build-neatvnc.sh          # clone v0.9.5, patch, build, install (sudo)
systemctl --user restart sway-headless # load the patched library
```

Verify it took effect:

```bash
ls -l /usr/lib/libneatvnc.so.0.0.0     # patched build is noticeably larger
swaymsg -t get_outputs | grep -A2 HEADLESS-1   # size tracks the browser after a resize
```

### Maintenance

This **overwrites the distro `libneatvnc`**, so a `pacman -Syu` that upgrades
`neatvnc` will revert it (losing dynamic resize, not breaking anything). To keep
it:

- Re-run `host/patches/build-neatvnc.sh` after a neatvnc upgrade, **or**
- Pin the package: add `IgnorePkg = neatvnc` to `/etc/pacman.conf` (note: it
  then won't receive updates).
- Ideally, report the id-0 issue upstream (neatvnc and/or guacamole-server) so
  the patch becomes unnecessary.

> ABI note: build the neatvnc version whose soname matches your installed wayvnc
> (`libneatvnc.so.0`). If a future neatvnc bumps the soname, rebuild wayvnc too.

---

## Security: bind address & firewall

wayvnc runs **without VNC auth** (it has no legacy DES VNC password; its TLS/RSA-AES
modes are not a clean match for Guacamole's VNC password field). Security therefore
relies on two things:

1. wayvnc binds to the **Docker bridge gateway** (e.g. `172.17.0.1:5901`), not
   `0.0.0.0`. guacd reaches it through `host.docker.internal` (mapped to
   `host-gateway` in `compose.yaml`).
2. **Guacamole** login + permissions + optional TOTP is the public boundary.

Rules:

- Do **not** publish `5901` through Docker.
- Do **not** open host firewall port `5901` publicly.
- Only `22`, `80`, `443` should be publicly reachable.

If you must temporarily bind `0.0.0.0:5901`, add/verify a firewall rule blocking
external access to `5901` **before** first starting wayvnc.

Checks:

```bash
ss -ltnp | grep 5901
sudo nft list ruleset | grep -E '5901|vnc' || true
# from another machine — this should FAIL:
nc -vz <server-public-ip-or-domain> 5901
```

Verify the bind address matches what `host.docker.internal` resolves to:

```bash
ip -4 addr show docker0
docker compose exec guacd getent hosts host.docker.internal
docker compose exec guacd nc -vz host.docker.internal 5901
```

---

## Troubleshooting

### `systemctl --user` cannot connect to bus

```bash
loginctl show-user "$USER" -p Linger
sudo loginctl enable-linger "$USER"
```

Log out/in or start a proper user session if needed.

### Sway fails to start (renderer / DRM / GPU errors)

Confirm the service env includes the headless/software settings:

```text
WLR_BACKENDS=headless
WLR_RENDERER=pixman
WLR_HEADLESS_OUTPUTS=1
```

```bash
journalctl --user -u sway-headless -b --no-pager
```

### Sway fails due to input / seat errors

Confirm `WLR_LIBINPUT_NO_DEVICES=1` is set. If it still needs seat access:

```bash
sudo systemctl enable --now seatd
sudo usermod -aG seat "$USER"
```

Then log out/in or restart the user manager.

### No `HEADLESS-1` output

Confirm `WLR_HEADLESS_OUTPUTS=1` and that the Sway config references `HEADLESS-1`:

```bash
swaymsg -t get_outputs
```

(`swaymsg` from a non-interactive shell may need `SWAYSOCK` discovery.)

### wayvnc is not listening

```bash
journalctl --user -u sway-headless -b --no-pager | grep -i wayvnc
ss -ltnp | grep 5901
```

Likely causes: wrong bind address, port still held by an old TigerVNC
`vncserver@:1`, wayvnc config parse error, or Sway never started.

```bash
systemctl status 'vncserver@:1' || true
```

### guacd cannot reach wayvnc

```bash
docker compose exec guacd getent hosts host.docker.internal
ss -ltnp | grep 5901
```

If the resolved IP and the wayvnc bind address differ, re-run
`./host/install-host.sh` (it re-detects docker0) or fix the `exec wayvnc` line.

### Browser shows a blank / gray desktop

- Sway output exists (`swaymsg -t get_outputs`).
- wayvnc logs show a client connected.
- Guacamole connection password is blank and protocol is VNC.
- `xorg-xwayland` is installed if launching X11 apps.

---

## Rollback to XFCE + TigerVNC

```bash
systemctl --user stop sway-headless || true
sudo pacman -S --needed xfce4 xfce4-goodies tigervnc
sudo systemctl start 'vncserver@:1'
```

Then restore the Guacamole connection password to the old TigerVNC password.
