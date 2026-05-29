# Host desktop: XFCE + xrdp + X11

The host-side remote desktop is an **XFCE** session running on **Xorg** via
**xrdp/xorgxrdp**. Guacamole connects to it with RDP:

```text
guacd ─► RDP ─► xrdp/xorgxrdp ─► Xorg ─► XFCE (xfwm4)
```

`xrdp` and `xrdp-sesman` run as system services at boot. The XFCE desktop itself starts only when a
user logs in over RDP.

XFCE is used here because it is the most battle-tested desktop over xrdp: reliable session startup
and reconnection, and xfwm4 runs fine with **compositing disabled**, which is exactly what you want
over RDP (no shadows/transparency wasting bandwidth or adding latency).

## Package set

```bash
sudo pacman -S --needed \
  xrdp xorgxrdp \
  xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-settings xfconf \
  xfce4-whiskermenu-plugin \
  thunar xfce4-terminal xfce4-appfinder xfce4-notifyd garcon \
  flameshot \
  breeze-icons noto-fonts
```

Why these packages:

- `xrdp`, `xorgxrdp` — RDP daemon and Xorg backend. No physical GPU/video driver is required.
- `xfce4-session`, `xfwm4`, `xfce4-panel`, `xfdesktop`, `xfce4-settings`, `xfconf`, `garcon` —
  minimal practical XFCE desktop (session manager, window manager, panel, desktop/background, the
  settings/config backend, and the menu library).
- `thunar` — file manager.
- `flameshot` — screenshot tool with region selection and annotation (X11).
- `xfce4-terminal` — terminal.
- `xfce4-whiskermenu-plugin` — modern searchable applications menu for the panel (search box,
  categories, favorites, recently used).
- `xfce4-appfinder` — application launcher / run dialog (`Alt+F2`/`Alt+F3`).
- `xfce4-notifyd` — desktop notifications.
- `breeze-icons`, `noto-fonts` — sane icons/fonts.

Avoid the full `xfce4` / `xfce4-goodies` groups unless you specifically want extras like the screen
saver, power manager, screenshot tools, or panel goodies that are pointless inside a no-audio,
no-hardware RDP session.

## Run the installer

From the repo root:

```bash
./host/install-host.sh
```

Run it interactively. It will prompt for sudo and then:

- install the package set above,
- install `host/xfce/xinitrc` to `~/.xinitrc`,
- reset `~/.config/xfce4` and install the repo-tracked xfconf XML into
  `~/.config/xfce4/xfconf/xfce-perchannel-xml/`:
  - `xsettings.xml` — Adwaita-dark GTK theme, `breeze-dark` icons, Noto fonts, no event sounds,
  - `xfwm4.xml` — Default xfwm4 theme, **compositing off**, 4 workspaces,
  - `xfce4-panel.xml` — single locked bottom panel (menu, window list, spacer, tray, clock,
    show-desktop) with no audio/volume plugin,
  - `xfce4-desktop.xml` — solid dark `#111827` background, desktop icons for Home/Trash only,
  - `xfce4-session.xml` — no session saving, no logout prompt, no screen lock on shutdown,
  - `keyboard-shortcuts.xml` — XFCE/xfwm4 shortcuts; audio/brightness keys omitted,
- install dark GTK preference configs,
- bind xrdp to the Docker bridge gateway on port `3389`,
- set the Arch xorgxrdp Xorg path in `/etc/xrdp/sesman.ini`,
- enable/start `xrdp` and `xrdp-sesman`,
- offer to remove old LXQt/Openbox/Sway/Wayland/TigerVNC packages.

`~/.xinitrc` launches XFCE for xrdp with:

```sh
exec startxfce4
```

`startxfce4` sets up its own D-Bus session, so it is **not** wrapped in `dbus-run-session`. The
appearance configs intentionally drop the volume/removable-media applets and audio/brightness
hotkeys because this setup does not provide a PulseAudio/PipeWire desktop audio server or local
removable media inside the RDP session.

Verify after the installer finishes:

```bash
systemctl status xrdp xrdp-sesman --no-pager
ss -ltnp | grep ':3389'
```

Expected listener: `<docker0-gateway>:3389`, not `0.0.0.0:3389`.

## Customizing

The shipped xfconf XML is just a sane starting point. Once a session is running you can adjust
everything through the normal XFCE GUI (Settings Manager, panel right-click, etc.); changes are
written back to `~/.config/xfce4/xfconf/xfce-perchannel-xml/`. Re-running `./host/install-host.sh`
**resets** `~/.config/xfce4` to the repo defaults, so copy any tweaks you want to keep back into
`host/xfce/`.

## Security model

- Public access is HTTPS to Caddy/Guacamole only.
- RDP is host-internal: `xrdp.ini` binds to the Docker bridge gateway so `guacd` can connect via
  `host.docker.internal:3389`.
- Guacamole login/permissions, optional TOTP, and the Linux account used for RDP form the access
  controls.
- Do not open port `3389` publicly unless you explicitly want direct RDP access.

## Guacamole connection

Create an RDP connection:

| Field | Value |
| --- | --- |
| Name | `Arch XFCE` |
| Protocol | `RDP` |
| Hostname | `host.docker.internal` |
| Port | `3389` |
| Security mode | `Any` or `TLS` |
| Ignore server certificate | enabled |

Use Linux account credentials for the RDP login, or configure Guacamole to prompt/store them.

## Cleanup old desktop packages/configs

`./host/install-host.sh` offers to do this. If you skipped that prompt, run:

```bash
candidates=(
  lxqt-session lxqt-panel lxqt-config lxqt-globalkeys lxqt-menu-data
  lxqt-notificationd lxqt-policykit lxqt-qtplugin lxqt-runner lxqt-themes
  pcmanfm-qt qterminal openbox obconf-qt
  sway swaybg waybar wayvnc foot fuzzel xorg-xwayland seatd
  ttf-iosevkaterm-nerd papirus-icon-theme swaync nwg-drawer
  qt5ct qt6ct xdg-desktop-portal xdg-desktop-portal-gtk
  autotiling swayr wl-clipboard cliphist grim slurp swappy wlogout neatvnc
  tigervnc
)
remove_pkgs=()
for p in "${candidates[@]}"; do
  pacman -Q "$p" >/dev/null 2>&1 && remove_pkgs+=("$p")
done

if ((${#remove_pkgs[@]})); then
  printf 'Removing old desktop packages:\n'
  printf '  %s\n' "${remove_pkgs[@]}"
  sudo pacman -Rns -- "${remove_pkgs[@]}"
else
  echo 'No old desktop packages found.'
fi

sudo systemctl disable --now 'vncserver@:1.service' 2>/dev/null || true
sudo rm -f /etc/tigervnc/vncserver.users
```

`./host/install-host.sh` also removes old user-level config directories/files from previous remote
desktop setups (LXQt, Openbox, PCManFM, Sway/Wayland, Qt theme files, TigerVNC).

## Troubleshooting

### xrdp is not listening

```bash
systemctl status xrdp xrdp-sesman --no-pager
journalctl -u xrdp -u xrdp-sesman -b --no-pager
ss -ltnp | grep ':3389'
```

If no listener appears, confirm packages are installed and `sudo systemctl enable --now xrdp
xrdp-sesman` completed successfully.

### Blank or blue desktop after login

Check:

```bash
ls -l ~/.xinitrc
command -v startxfce4 xfce4-session xfwm4
sudo grep -A20 '^\[Xorg\]' /etc/xrdp/sesman.ini
journalctl -u xrdp -u xrdp-sesman -b --no-pager
```

The `[Xorg]` block should use `param=/usr/lib/Xorg` on Arch.

### Desktop background is not the dark color

xorgxrdp may name the virtual output `rdp0` instead of the default `monitor0`. The shipped
`xfce4-desktop.xml` sets both `monitor0` and `monitorrdp0`, but if your build uses another name,
just right-click the desktop → *Desktop Settings* and set the background to a solid color once; it
will be saved under the correct monitor key.

### Guacamole cannot connect

Check:

```bash
docker compose exec guacd getent hosts host.docker.internal
ss -ltnp | grep ':3389'
docker compose logs guacd guacamole
```

The xrdp bind address must match the Docker bridge gateway returned for
`host.docker.internal`.

### RDP is exposed publicly

If `ss -ltnp | grep ':3389'` shows `0.0.0.0:3389`, re-apply the xrdp bind command:

```bash
gateway="$(ip -4 addr show docker0 | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')"
sudo sed -i -E "0,/^port=.*/s|^port=.*|port=tcp://${gateway}:3389|" /etc/xrdp/xrdp.ini
sudo systemctl restart xrdp
```
