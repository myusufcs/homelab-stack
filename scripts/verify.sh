#!/usr/bin/env bash
#
# verify.sh — buktikan seluruh stack benar-benar hidup, bukan sekadar "container up".
# Memeriksa: status container, health service, TLS lewat proxy, metrik, database.
#
# Pakai: ./scripts/verify.sh
set -uo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

BIND="${BIND_ADDR:-127.0.0.1}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
PROM_PORT="${PROM_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
HTTP_PORT="${HTTP_PORT:-8080}"
DB_USER="${POSTGRES_USER:-homelab}"
DB_NAME="${POSTGRES_DB:-homelab}"

# Sertifikat internal Caddy diterbitkan untuk HOSTNAME, bukan IP — jadi akses
# HTTPS lewat `localhost` (sudah menunjuk 127.0.0.1), bukan 127.0.0.1.
TLS_HOST="${TLS_HOST:-localhost}"

pass=0; fail=0
declare -a rows

ok()   { rows+=("✅|$1|$2"); pass=$((pass+1)); }
bad()  { rows+=("❌|$1|$2"); fail=$((fail+1)); }
skip() { rows+=("➖|$1|$2"); }

# --- 1. container -----
if ! command -v docker >/dev/null; then
  echo "docker tidak ditemukan" >&2; exit 2
fi
running=$(docker compose ps --status running --format '{{.Service}}' 2>/dev/null | sort | tr '\n' ' ')
for svc in proxy app db prometheus grafana node-exporter; do
  if echo "$running" | grep -qw "$svc"; then ok "container:$svc" "berjalan"
  else bad "container:$svc" "TIDAK berjalan"; fi
done

# --- 2. proxy + TLS -----
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://$TLS_HOST:$HTTPS_PORT/healthz" 2>/dev/null || true)
[ "$code" = "200" ] && ok "proxy TLS /healthz" "HTTP $code" || bad "proxy TLS /healthz" "HTTP ${code:-000}"

tls=$(curl -skv --max-time 8 "https://$TLS_HOST:$HTTPS_PORT/healthz" 2>&1 | grep -c 'SSL connection using' || true)
[ "$tls" -ge 1 ] && ok "TLS handshake" "berhasil" || bad "TLS handshake" "gagal"

hdr=$(curl -sk -D - -o /dev/null --max-time 8 "https://$TLS_HOST:$HTTPS_PORT/" | tr -d '\r')
echo "$hdr" | grep -qi 'strict-transport-security' && ok "header HSTS" "ada" || bad "header HSTS" "tidak ada"
echo "$hdr" | grep -qi '^server:' && bad "header Server" "masih bocor" || ok "header Server" "disembunyikan"

body=$(curl -sk --max-time 8 "https://$TLS_HOST:$HTTPS_PORT/")
echo "$body" | grep -q 'homelab-stack' && ok "app lewat proxy" "halaman tampil" || bad "app lewat proxy" "isi tidak sesuai"

http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:$HTTP_PORT/lb-health" 2>/dev/null || true)
[ "$http_code" = "200" ] && ok "proxy HTTP /lb-health" "HTTP $http_code" || bad "proxy HTTP /lb-health" "HTTP ${http_code:-000}"

# --- 3. metrik aplikasi -----
m=$(curl -sk --max-time 8 "https://$TLS_HOST:$HTTPS_PORT/metrics" || true)
echo "$m" | grep -q 'homelab_uptime_seconds' && ok "metrik /metrics" "format Prometheus" || bad "metrik /metrics" "tidak sesuai"
echo "$m" | grep -qE 'homelab_db_tcp_open 1' && ok "app→db" "TCP terjangkau" || bad "app→db" "tidak terjangkau"

# --- 4. prometheus -----
# Catatan: Prometheus butuh satu siklus scrape pertama (interval 15s) sebelum
# target muncul "up". Jadi bagian ini menunggu (maks ~75 detik) — supaya
# `make verify` langsung setelah `make up` tidak memberi hasil merah palsu.
p=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$BIND:$PROM_PORT/-/ready" || echo 000)
[ "$p" = "200" ] && ok "prometheus /-/ready" "HTTP $p" || bad "prometheus /-/ready" "HTTP $p"

up_targets=0; all_targets=0; waited=0
while [ "$waited" -lt 75 ]; do
  read -r up_targets all_targets < <(
    curl -s --max-time 8 "http://$BIND:$PROM_PORT/api/v1/targets?state=active" 2>/dev/null \
      | python3 -c "import sys,json;d=json.load(sys.stdin);t=d['data']['activeTargets'];print(sum(1 for x in t if x['health']=='up'),len(t))" 2>/dev/null \
      || echo "0 0")
  [ "${up_targets:-0}" -ge 3 ] && break
  sleep 5; waited=$((waited + 5))
done
if [ "${up_targets:-0}" -ge 3 ]; then
  ok "prometheus targets" "$up_targets/$all_targets up"
else
  bad "prometheus targets" "$up_targets/$all_targets up (ditunggu ${waited}s)"
fi

# --- 5. grafana -----
# provisioning dashboard bisa butuh beberapa detik setelah container naik
dash=0; waited=0
while [ "$waited" -lt 60 ]; do
  dash=$(curl -s -u "${GRAFANA_USER:-admin}:${GRAFANA_PASSWORD:-admin}" --max-time 8 \
    "http://$BIND:$GRAFANA_PORT/api/search?query=Homelab" 2>/dev/null \
    | python3 -c "import sys,json;print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  [ "${dash:-0}" -ge 1 ] && break
  sleep 5; waited=$((waited + 5))
done
g=$(curl -s --max-time 8 "http://$BIND:$GRAFANA_PORT/api/health" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('database','?'))" 2>/dev/null || echo "?")
[ "$g" = "ok" ] && ok "grafana /api/health" "database ok" || bad "grafana /api/health" "database=$g"
[ "${dash:-0}" -ge 1 ] && ok "dashboard ter-provision" "$dash ditemukan" || bad "dashboard ter-provision" "tidak ditemukan"

# --- 6. database -----
if docker compose exec -T db pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
  ok "postgres pg_isready" "menerima koneksi"
else
  bad "postgres pg_isready" "tidak menerima koneksi"
fi
tabel=$(docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -tAc \
  "select count(*) from information_schema.tables where table_schema='public'" 2>/dev/null | tr -d '[:space:]')
[ "${tabel:-0}" -ge 2 ] && ok "skema ter-init" "$tabel tabel" || bad "skema ter-init" "tabel=${tabel:-0}"

# --- ringkasan -----
echo
echo "================================================================"
echo "  VERIFIKASI HOMELAB-STACK"
echo "================================================================"
printf '%-4s %-24s %s\n' "" "PEMERIKSAAN" "HASIL"
printf -- '----------------------------------------------------------------\n'
for r in "${rows[@]}"; do
  IFS='|' read -r s name detail <<< "$r"
  printf '%-4s %-24s %s\n' "$s" "$name" "$detail"
done
echo "----------------------------------------------------------------"
echo "  LOLOS: $pass   GAGAL: $fail"
echo "================================================================"

# --- petunjuk akses -----
if [ "$fail" -eq 0 ]; then
  echo
  echo "Akses:"
  echo "  app        https://$TLS_HOST:$HTTPS_PORT        (sertifikat internal → curl -k)"
  echo "  grafana    http://$BIND:$GRAFANA_PORT       (${GRAFANA_USER:-admin} / password di .env)"
  echo "  prometheus http://$BIND:$PROM_PORT"
  exit 0
fi
exit 1
