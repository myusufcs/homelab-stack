#!/usr/bin/env bash
#
# backup.sh — dump database ke ./backups lalu terapkan retensi.
# Pakai: ./scripts/backup.sh
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

DB_USER="${POSTGRES_USER:-homelab}"
DB_NAME="${POSTGRES_DB:-homelab}"
KEEP="${BACKUP_KEEP:-7}"
DEST="${BACKUP_DIR:-backups}"

mkdir -p "$DEST"
stamp="$(date +%Y%m%d-%H%M%S)"
out="$DEST/$DB_NAME-$stamp.sql.gz"

echo "→ dump $DB_NAME → $out"
docker compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists \
  | gzip -9 > "$out"

size=$(du -h "$out" | cut -f1)
echo "  selesai ($size)"

# retensi
mapfile -t old < <(ls -1t "$DEST"/*.sql.gz 2>/dev/null | tail -n "+$((KEEP+1))")
for f in "${old[@]:-}"; do
  [ -n "$f" ] && rm -f "$f" && echo "  hapus lama: $(basename "$f")"
done

count=$(ls -1 "$DEST"/*.sql.gz 2>/dev/null | wc -l)
echo "  total $count backup tersimpan (retensi $KEEP)"
