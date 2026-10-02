# homelab-stack — perintah harian
#
#   make up        bangun & jalankan seluruh stack
#   make verify    periksa semua service benar-benar hidup
#   make ps        status container
#   make logs      ikuti log
#   make backup    dump database ke ./backups (dengan retensi)
#   make down      hentikan (data tetap tersimpan di volume)
#   make clean     hentikan + hapus volume (DATA HILANG)

SHELL := /bin/bash
COMPOSE := docker compose
ENV_FILE := .env

.PHONY: help up down clean ps logs verify backup restore pull config

help:
	@grep -E '^#   ' $(MAKEFILE_LIST) | sed 's/^#   //'

.env:
	@cp .env.example .env
	@echo "→ .env dibuat dari .env.example. UBAH PASSWORD-nya sebelum 'make up'."

up: .env
	$(COMPOSE) --env-file $(ENV_FILE) up -d --build
	@echo
	@echo "Tunggu beberapa detik, lalu jalankan: make verify"

down:
	$(COMPOSE) --env-file $(ENV_FILE) down

clean:
	@echo "⚠  Ini menghapus seluruh volume (database & dashboard hilang)."
	@read -p "Ketik 'ya' untuk lanjut: " ok; [ "$$ok" = "ya" ] || exit 1
	$(COMPOSE) --env-file $(ENV_FILE) down -v

ps:
	$(COMPOSE) --env-file $(ENV_FILE) ps

logs:
	$(COMPOSE) --env-file $(ENV_FILE) logs -f --tail=50

config:
	$(COMPOSE) --env-file $(ENV_FILE) config

pull:
	$(COMPOSE) --env-file $(ENV_FILE) pull

verify:
	./scripts/verify.sh

backup:
	./scripts/backup.sh

restore:
	@test -n "$(FILE)" || { echo "pakai: make restore FILE=backups/xxx.sql.gz"; exit 1; }
	./scripts/restore.sh "$(FILE)"
