# Web Remote Desktop — convenience commands.
# Run `make` or `make help` to list targets.

SHELL   := /bin/bash
COMPOSE := docker compose

.DEFAULT_GOAL := help

## help: Show this help.
.PHONY: help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //' | awk -F': ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

## setup: Bootstrap .env from the example (then edit it and run make init-db).
.PHONY: setup
setup:
	@if [ -f .env ]; then \
		echo ".env already exists — leaving it untouched."; \
	else \
		cp .env.example .env; \
		echo "Created .env from .env.example."; \
		echo "Next: edit .env (POSTGRES_PASSWORD, GUAC_DOMAIN, ACME_EMAIL), then run 'make init-db'."; \
	fi

## up: Start host xrdp services + Docker stack.
.PHONY: up
up:
	sudo systemctl start xrdp xrdp-sesman
	$(COMPOSE) up -d
	@echo "Up: https://$$(grep -E '^GUAC_DOMAIN=' .env | cut -d= -f2-)"

## down: Stop Docker stack, host xrdp services, and running XFCE sessions.
.PHONY: down
down:
	$(COMPOSE) down
	sudo systemctl stop xrdp xrdp-sesman
	-sudo pkill -x xfce4-session

## restart: Restart the Docker stack only (host xrdp untouched).
.PHONY: restart
restart:
	$(COMPOSE) restart

## init-db: Generate + load the Guacamole schema into system PostgreSQL (run once).
.PHONY: init-db
init-db:
	./scripts/init-db.sh

## logs: Follow logs for all services.
.PHONY: logs
logs:
	$(COMPOSE) logs -f

## logs-guac: Follow Guacamole logs only.
.PHONY: logs-guac
logs-guac:
	$(COMPOSE) logs -f guacamole

## ps: Show stack status.
.PHONY: ps
ps:
	$(COMPOSE) ps

## config: Validate and render the merged compose config.
.PHONY: config
config:
	$(COMPOSE) config

## pull: Pull/update all service images.
.PHONY: pull
pull:
	$(COMPOSE) pull

## host-status: Show xrdp/xrdp-sesman status and RDP listener.
.PHONY: host-status
host-status:
	-systemctl status xrdp xrdp-sesman --no-pager
	-ss -ltnp | grep ':3389'
