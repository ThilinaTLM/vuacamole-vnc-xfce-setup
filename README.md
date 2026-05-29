# Web Remote Desktop

A self-hosted, browser-accessible remote desktop for the Arch Linux dev server, reachable at
`https://desk.tlmtech.dev`.

- **Desktop**: XFCE (xfwm4) on X11, served by host `xrdp`/`xorgxrdp`.
- **Gateway**: Apache Guacamole (HTML5 client, auth, optional TOTP/2FA) + guacd, in Docker.
- **Proxy**: Caddy in Docker — automatic HTTPS for `desk.tlmtech.dev`.
- **Database**: your existing system-level PostgreSQL (shared with dev work).

The public boundary is still HTTPS/Caddy/Guacamole. Host RDP binds only to the Docker bridge
address, so it is reachable by `guacd` but not exposed publicly.

Host desktop details live in [`docs/xfce-xrdp.md`](./docs/xfce-xrdp.md). PostgreSQL setup lives in
[`docs/postgresql-arch.md`](./docs/postgresql-arch.md).

## Architecture

```text
https://desk.tlmtech.dev  ──►  Caddy (Docker, 80/443)
                                  └─► Guacamole (Docker) ─► guacd (Docker)
                                                              └─► RDP ─► xrdp/xorgxrdp ─► Xorg ─► XFCE
                                  Guacamole ─► PostgreSQL (host, system service)
```

Only ports **80/443** (and **22** for SSH) should be exposed publicly. RDP/guacd/Guacamole/Postgres
stay on the Docker bridge, loopback, or private host interfaces.

---

## One-time setup

### 0. Prerequisites

Docker Engine + the Compose v2 plugin:

```bash
sudo pacman -S --needed docker docker-compose
sudo systemctl enable --now docker
docker compose version
```

### 1. Host desktop (XFCE + xrdp + X11)

Run the host installer interactively. It installs repo-tracked XFCE user configs, prompts for sudo, installs the lightweight XFCE/xrdp package set, binds xrdp to the Docker bridge, enables `xrdp`/`xrdp-sesman`, and offers to remove old LXQt/Sway/TigerVNC packages.

```bash
./host/install-host.sh
```

Verify xrdp is bound to the Docker bridge only:

```bash
systemctl status xrdp xrdp-sesman --no-pager
ss -ltnp | grep ':3389'     # expect <docker0-gateway>:3389, not 0.0.0.0:3389
```

### 2. PostgreSQL database + role

If PostgreSQL is not set up yet, follow [`docs/postgresql-arch.md`](./docs/postgresql-arch.md) first.
Then create the Guacamole database/role and allow the Docker bridge to connect:

```bash
sudo -u postgres psql <<'SQL'
CREATE USER guacamole_user WITH PASSWORD 'use_a_long_random_value';
CREATE DATABASE guacamole_db OWNER guacamole_user;
SQL
```

Allow the Docker bridge subnet:

```text
# /var/lib/postgres/data/postgresql.conf
listen_addresses = 'localhost,172.17.0.1'

# /var/lib/postgres/data/pg_hba.conf
host  guacamole_db  guacamole_user  172.16.0.0/12  scram-sha-256
```

```bash
sudo systemctl reload postgresql
```

### 3. Project configuration

```bash
make setup
# edit .env: POSTGRES_PASSWORD (match the role above), GUAC_DOMAIN, ACME_EMAIL
```

### 4. Load the Guacamole schema (once)

```bash
make init-db
```

### 5. Clean old host desktop packages/configs

The installer offers to remove obsolete packages. If you skipped that prompt, run:

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
  sudo pacman -Rns -- "${remove_pkgs[@]}"
fi
sudo systemctl disable --now 'vncserver@:1.service' 2>/dev/null || true
sudo rm -f /etc/tigervnc/vncserver.users
```

---

## Daily use

```bash
make up           # start Docker stack → https://desk.tlmtech.dev
make down         # stop Docker stack; PostgreSQL and xrdp stay up
make host-status  # xrdp/xrdp-sesman status + RDP listener
make ps           # Docker stack status
make logs         # follow all Docker logs
make restart      # restart Docker stack only
make              # list all targets
```

### First login

1. Open `https://desk.tlmtech.dev`.
2. Log in with `guacadmin` / `guacadmin` and **change the password immediately**.
3. Create a connection:

   | Field | Value |
   | --- | --- |
   | Name | `Arch XFCE` |
   | Protocol | `RDP` |
   | Hostname | `host.docker.internal` |
   | Port | `3389` |
   | Security mode | `Any` or `TLS` |
   | Ignore server certificate | enabled |

Use your Linux account credentials for the RDP login, or configure Guacamole to prompt/store them.

### Enable TOTP/2FA

Mount `guacamole-auth-totp-1.6.0.jar` into the Guacamole extensions directory and restart the
`guacamole` service; each user enrolls on next login. See
[Guacamole TOTP docs](https://guacamole.apache.org/doc/gug/totp-auth.html).

---

## Files

```text
.
├── README.md
├── compose.yaml         # guacd + guacamole + caddy
├── Makefile             # make up / down / init-db / logs ...
├── .env.example         # copy to .env
├── caddy/Caddyfile      # automatic HTTPS → guacamole
├── sql/initdb.sql       # generated schema (gitignored)
├── scripts/             # up.sh, down.sh, init-db.sh
├── host/
│   ├── install-host.sh  # installs/configures XFCE + xrdp host setup
│   ├── xfce/            # XFCE xinitrc + xfconf (theme, panel, session, hotkeys)
│   ├── gtk-3.0/         # GTK dark preference
│   └── gtk-4.0/         # GTK dark preference
└── docs/
    ├── xfce-xrdp.md
    └── postgresql-arch.md
```

## Troubleshooting

- **xrdp not listening** — run `make host-status` and check `journalctl -u xrdp -u xrdp-sesman -b --no-pager`.
- **Blank/blue session after login** — confirm `~/.xinitrc` exists, `startxfce4` is installed, and `/etc/xrdp/sesman.ini` has `[Xorg] param=/usr/lib/Xorg`.
- **Guacamole cannot reach RDP** — confirm `compose.yaml` has `host.docker.internal:host-gateway` and `ss -ltnp | grep ':3389'` shows the Docker bridge address.
- **RDP exposed publicly** — fix `/etc/xrdp/xrdp.ini`; it should bind to `tcp://<docker0-gateway>:3389`, not `0.0.0.0:3389`.
