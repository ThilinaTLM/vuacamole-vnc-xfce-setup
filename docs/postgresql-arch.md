# PostgreSQL on Arch Linux — General Setup Guide

A practical, general-purpose guide to running PostgreSQL as a system service on this Arch Linux
server. It is **not** specific to the remote-desktop project — use it as the base DB for any dev or
self-hosted workload. The remote-desktop stack just adds a `guacamole_db` database on top.

> Arch defaults used throughout:
> - System user: `postgres`
> - Data directory (`PGDATA`): `/var/lib/postgres/data`
> - Service: `postgresql.service`
> - Default port: `5432`

---

## 1. Install

```bash
sudo pacman -S --needed postgresql
```

This installs the server and client (`psql`, `pg_dump`, `initdb`, ...) and creates the `postgres`
system user.

## 2. Initialize the database cluster

The data directory starts empty; initialize it **as the `postgres` user**. Enabling data checksums
is recommended for catching silent disk corruption:

```bash
sudo -iu postgres initdb \
  --locale=en_US.UTF-8 \
  --encoding=UTF8 \
  --data-checksums \
  -D /var/lib/postgres/data
```

> If `en_US.UTF-8` is missing, uncomment it in `/etc/locale.gen` and run `sudo locale-gen` first.

## 3. Start and enable the service

```bash
sudo systemctl enable --now postgresql
systemctl status postgresql --no-pager
```

Confirm you can connect:

```bash
sudo -iu postgres psql -c '\conninfo'
```

## 4. Create roles and databases

PostgreSQL ships with a superuser role `postgres`. Create application-specific roles instead of
using it directly.

```bash
sudo -iu postgres psql
```

```sql
-- A login role with a password
CREATE ROLE myapp WITH LOGIN PASSWORD 'a_long_random_password';

-- A database owned by that role
CREATE DATABASE myapp_db OWNER myapp;

-- (Optional) a personal superuser-ish admin role for day-to-day work
CREATE ROLE tlm WITH LOGIN CREATEDB CREATEROLE PASSWORD 'another_password';

\q
```

Quick non-interactive equivalents:

```bash
sudo -iu postgres createuser --interactive --pwprompt myapp
sudo -iu postgres createdb --owner=myapp myapp_db
```

### Convenience: match your Linux username

PostgreSQL's default `peer` auth (see below) lets a Linux user log in as the same-named DB role
with no password locally. Creating a role matching your shell user is handy:

```bash
sudo -iu postgres createuser --superuser "$USER"   # then: psql -d postgres  (no sudo)
```

## 5. Authentication (`pg_hba.conf`)

Auth rules live in `/var/lib/postgres/data/pg_hba.conf`, evaluated **top to bottom, first match
wins**. Defaults on Arch:

```text
# TYPE  DATABASE  USER  ADDRESS         METHOD
local   all       all                   peer            # unix socket: OS user == DB role
host    all       all   127.0.0.1/32    scram-sha-256   # localhost IPv4 (password)
host    all       all   ::1/128         scram-sha-256   # localhost IPv6
```

- **`peer`** — trusts the OS user for local socket connections (great for `sudo -iu postgres psql`).
- **`scram-sha-256`** — modern password auth (preferred over the legacy `md5`).
- **`trust`** — no auth; never use it beyond throwaway local testing.

After editing, reload (no restart needed for `pg_hba.conf`):

```bash
sudo systemctl reload postgresql
```

> Set passwords with strong hashing by ensuring `password_encryption = scram-sha-256` in
> `postgresql.conf` (the modern default) before running `\password`.

## 6. Network access (optional)

By default PostgreSQL listens only on `localhost`. To accept connections from other hosts, Docker
containers, or your LAN, edit `/var/lib/postgres/data/postgresql.conf`:

```text
listen_addresses = 'localhost,172.17.0.1'   # add the docker0 gateway, or '*' for all interfaces
port = 5432
```

Then add matching `pg_hba.conf` rules — **scope them tightly**:

```text
# Docker bridge containers
host  myapp_db  myapp  172.16.0.0/12   scram-sha-256

# A specific LAN host
host  myapp_db  myapp  192.168.1.50/32 scram-sha-256
```

Changing `listen_addresses` requires a **restart**, not just reload:

```bash
sudo systemctl restart postgresql
```

> Find the docker bridge gateway with `ip addr show docker0` (commonly `172.17.0.1`). From inside a
> container, the host is reachable via `host.docker.internal` when you add
> `extra_hosts: ["host.docker.internal:host-gateway"]`.

**Never** expose 5432 to the public internet. Keep it on loopback / private subnets and front any
remote access with SSH tunnels, a VPN, or a reverse proxy with TLS.

## 7. Connecting

```bash
# Local, as the postgres superuser
sudo -iu postgres psql

# With a connection URI
psql "postgresql://myapp:password@localhost:5432/myapp_db"

# Using environment variables
PGPASSWORD=password psql -h localhost -U myapp -d myapp_db
```

Handy `psql` commands:

| Command            | Description                |
| ------------------ | -------------------------- |
| `\l`               | list databases             |
| `\c dbname`        | connect to a database      |
| `\dt`              | list tables                |
| `\du`              | list roles                 |
| `\dn`              | list schemas               |
| `\conninfo`        | current connection info    |
| `\password role`   | set a role's password      |
| `\q`               | quit                       |

## 8. Backups & restore

```bash
# Single database (compressed custom format — preferred)
sudo -iu postgres pg_dump -Fc myapp_db > myapp_db.dump
pg_restore -d myapp_db myapp_db.dump

# Plain SQL dump
sudo -iu postgres pg_dump myapp_db > myapp_db.sql
psql myapp_db < myapp_db.sql

# Everything (roles + all databases)
sudo -iu postgres pg_dumpall > full_cluster.sql
```

Automate with a systemd timer or cron; store dumps off-box.

## 9. Basic performance tuning

Defaults are conservative. For a dev server, edit `postgresql.conf` and tune to available RAM
(rough starting points for a machine with, say, 8–16 GB):

```text
shared_buffers = 2GB              # ~25% of RAM
effective_cache_size = 6GB        # ~50–75% of RAM
work_mem = 32MB                   # per sort/hash op; raise carefully
maintenance_work_mem = 512MB
max_connections = 100
wal_compression = on
```

Use [PGTune](https://pgtune.leopard.in.ua/) for tailored values. Restart after changing memory
settings:

```bash
sudo systemctl restart postgresql
```

## 10. Maintenance

```bash
# Autovacuum is on by default; a manual full analyze occasionally helps:
sudo -iu postgres vacuumdb --all --analyze

# Check version / upgrade considerations
psql --version
```

> **Major version upgrades** (e.g. 16 → 17) require `pg_upgrade` or dump/restore and a new data
> directory — read the Arch wiki "PostgreSQL#Upgrading" section before upgrading the package across
> a major version, or the service will refuse to start against an old cluster.

## 11. Security checklist

- [ ] No `trust` rules in `pg_hba.conf` outside throwaway testing.
- [ ] `password_encryption = scram-sha-256`.
- [ ] `listen_addresses` limited to what's needed; 5432 never public.
- [ ] App roles are non-superuser and own only their own databases.
- [ ] Regular, off-box backups (`pg_dump`/`pg_dumpall`).
- [ ] Firewall blocks 5432 from the public internet.

## References

- Arch Wiki — PostgreSQL: https://wiki.archlinux.org/title/PostgreSQL
- Official docs — Authentication (`pg_hba.conf`): https://www.postgresql.org/docs/current/auth-pg-hba-conf.html
- Official docs — Server config: https://www.postgresql.org/docs/current/runtime-config.html
- Backup & restore: https://www.postgresql.org/docs/current/backup.html
