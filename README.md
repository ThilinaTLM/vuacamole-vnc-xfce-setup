# Web Remote Desktop

A self-hosted, browser-accessible remote desktop for the Arch Linux dev server, reachable at
`https://desk.tlmtech.dev`.

- **Desktop**: Sway + wayvnc on the host (headless, started on demand).
- **Gateway**: Apache Guacamole (HTML5 client, auth, optional TOTP/2FA) + guacd, in Docker.
- **Proxy**: Caddy in Docker — automatic HTTPS for `desk.tlmtech.dev`.
- **Database**: your existing system-level PostgreSQL (shared with dev work).

Everything is **on-demand**: nothing starts at boot, so idle RAM cost is near zero beyond
PostgreSQL and the user systemd manager.

> Host desktop details (packages, linger, config install, troubleshooting) live in
> [`docs/sway-wayvnc.md`](./docs/sway-wayvnc.md).

> A general PostgreSQL setup guide for this server is in [`docs/postgresql-arch.md`](./docs/postgresql-arch.md).

## Architecture

```text
https://desk.tlmtech.dev  ──►  Caddy (Docker, 80/443)
                                  └─► Guacamole (Docker) ─► guacd (Docker)
                                                              └─► VNC ─► wayvnc + Sway headless (host :5901)
                                  Guacamole ─► PostgreSQL (host, system service)
```

Only ports **80/443** (and **22** for SSH) are exposed publicly. VNC/guacd/Guacamole/Postgres stay
on loopback or the Docker bridge.

---

## One-time setup

### 0. Prerequisites

Docker Engine + the Compose v2 plugin:

```bash
sudo pacman -S --needed docker docker-compose
sudo systemctl enable --now docker
docker compose version   # verify the plugin is present
```

### 1. Host desktop (Sway + wayvnc)

Install packages and enable linger (so the user systemd manager runs without an
interactive login):

```bash
sudo pacman -S --needed sway wayvnc foot fuzzel xorg-xwayland seatd
sudo loginctl enable-linger "$USER"
```

Install the repo-tracked host configs (Sway config, wayvnc config, user unit). The
installer detects the Docker bridge gateway and binds wayvnc to it (e.g. `172.17.0.1:5901`),
then runs `systemctl --user daemon-reload`:

```bash
./host/install-host.sh
```

There is **no** `vncpasswd` and **no** `/etc/tigervnc/vncserver.users` — wayvnc runs with
auth disabled and is reachable only from the Docker bridge; Guacamole login is the public
boundary. See [`docs/sway-wayvnc.md`](./docs/sway-wayvnc.md) for the full rationale.

> The `sway-headless` user unit is **not** enabled (no autostart). `make up` starts it on demand.

### 2. PostgreSQL database + role

If PostgreSQL isn't set up yet, follow [`docs/postgresql-arch.md`](./docs/postgresql-arch.md) first.
Then create the Guacamole database/role and allow the Docker bridge to connect:

```bash
sudo -u postgres psql <<'SQL'
CREATE USER guacamole_user WITH PASSWORD 'use_a_long_random_value';
CREATE DATABASE guacamole_db OWNER guacamole_user;
SQL
```

Allow the Docker bridge subnet (one-time host edit):

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
make setup      # creates .env from .env.example
# edit .env: POSTGRES_PASSWORD (match the role above), GUAC_DOMAIN, ACME_EMAIL
```

### 4. Load the Guacamole schema (once)

```bash
make init-db        # generates sql/initdb.sql and loads it into guacamole_db
```

---

## Daily use

```bash
make up        # start desktop + stack  → https://desk.tlmtech.dev
make down      # stop everything (frees RAM; PostgreSQL stays up)
make ps        # status
make logs      # follow all logs
make restart   # restart the Docker stack only
make           # list all targets
```

### First login

1. Open `https://desk.tlmtech.dev`.
2. Log in with `guacadmin` / `guacadmin` and **change the password immediately**.
3. Create a connection:

   | Field    | Value                  |
   | -------- | ---------------------- |
   | Name     | `Arch Sway`            |
   | Protocol | `VNC`                  |
   | Hostname | `host.docker.internal` |
   | Port     | `5901`                 |
   | Password | **blank / cleared**    |

### Enable TOTP/2FA (recommended before serious use)

Mount `guacamole-auth-totp-1.6.0.jar` into the Guacamole extensions directory and restart the
`guacamole` service; each user enrolls on next login. See
[Guacamole TOTP docs](https://guacamole.apache.org/doc/gug/totp-auth.html).

---

## Files

```text
.
├── README.md            # this file
├── compose.yaml         # guacd + guacamole + caddy
├── Makefile             # make up / down / init-db / logs ...
├── .env.example         # copy to .env
├── caddy/Caddyfile      # automatic HTTPS → guacamole
├── sql/initdb.sql       # generated schema (gitignored)
├── scripts/             # up.sh, down.sh, init-db.sh (used by Makefile)
├── host/                # host desktop configs (installed by install-host.sh)
│   ├── sway/config
│   ├── wayvnc/config
│   ├── systemd/sway-headless.service
│   ├── install-host.sh
│   └── patches/         # patched neatvnc for browser-responsive resize
└── docs/
    ├── sway-wayvnc.md       # host desktop (Sway + wayvnc) setup & troubleshooting
    └── postgresql-arch.md   # general PostgreSQL setup for this server
```

## Troubleshooting

- **Gray/blank desktop / Sway won't start / wayvnc not listening** — see the dedicated
  troubleshooting section in [`docs/sway-wayvnc.md`](./docs/sway-wayvnc.md). Quick checks:
  `systemctl --user status sway-headless`, `journalctl --user -u sway-headless -b --no-pager`,
  and `ss -ltnp | grep 5901`.
- **Guacamole can't reach the DB** — confirm `pg_hba.conf` allows `172.16.0.0/12` and
  `listen_addresses` includes the docker0 gateway (`ip addr show docker0`), then
  `sudo systemctl reload postgresql`.
- **Cert not issued** — DNS for `desk.tlmtech.dev` must resolve to this server and ports 80/443 must
  be reachable; check `make logs` for Caddy ACME errors.
- **`docker compose` not found** — install the plugin: `sudo pacman -S docker-compose`.
