#!/usr/bin/env bash
#
# restore.sh — pulihkan dump ke database. Pakai: ./scripts/restore.sh backups/xxx.sql.gz
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

FILE="${1:-}"
[ -n "$FILE" ] || { echo "pakai: $0 <berkas.sql.gz>"; exit 2; }
[ -f "$FILE" ] || { echo "berkas tidak ada: $FILE"; exit 2; }

DB_USER="${POSTGRES_USER:-homelab}"
DB_NAME="${POSTGRES_DB:-homelab}"

echo "→ memulihkan $FILE ke $DB_NAME"
gunzip -c "$FILE" | docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 >/dev/null
echo "  selesai."

tabel=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -tAc \
  "select count(*) from information_schema.tables where table_schema='public'" | tr -d '[:space:]')
echo "  tabel di database sekarang: $tabel"
