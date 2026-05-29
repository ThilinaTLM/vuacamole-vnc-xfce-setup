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
sudo pacman -S --needed sway wayvnc foot fuzzel xorg-xwayland seatd
```

- `sway` — the Wayland compositor (uses the wlroots headless backend here).
- `wayvnc` — VNC server for wlroots compositors.
- `foot` — terminal; `fuzzel` — application launcher.
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
host/systemd/sway-headless.service → ~/.config/systemd/user/sway-headless.service
```

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
