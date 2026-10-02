# homelab-stack

**Infrastruktur lengkap dengan satu perintah.** Reverse proxy + TLS otomatis, aplikasi,
PostgreSQL, dan monitoring (Prometheus + Grafana + node-exporter) — semuanya jalan lokal,
tanpa domain publik, tanpa biaya.

Yang membedakan repo ini: **semuanya sudah diverifikasi benar-benar jalan**, bukan sekadar
"file compose-nya ada". Ada `make verify` yang memeriksa 20 hal — dari container hidup,
TLS handshake, header keamanan, metrik Prometheus, sampai skema database — dan CI menjalankan
stack-nya sungguhan lalu memverifikasi.

[![CI](https://github.com/nullbyte12007/homelab-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/nullbyte12007/homelab-stack/actions/workflows/ci.yml)
![Docker](https://img.shields.io/badge/docker-compose-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Yang dibangun

| Service | Peran |
|---|---|
| **Caddy** | Reverse proxy + **TLS otomatis** (CA lokal internal — tanpa domain publik) |
| **app** | Aplikasi demo (Python stdlib, non-root, image kecil) dengan `/healthz`, `/metrics`, `/info` |
| **PostgreSQL 16** | Database + skema awal lewat `docker-entrypoint-initdb.d` |
| **Prometheus** | Scrape metrik app, node-exporter, dan dirinya sendiri |
| **Grafana** | Dashboard + datasource Prometheus, **ter-provision otomatis** |
| **node-exporter** | Metrik host (CPU, memori, disk) |

Semua port default hanya terikat ke **127.0.0.1** — ubah `BIND_ADDR` di `.env` kalau memang
mau diakses dari mesin lain.

## Keluaran `make verify` (nyata, 20/20)

```
================================================================
  VERIFIKASI HOMELAB-STACK
================================================================
     PEMERIKSAAN              HASIL
----------------------------------------------------------------
✅  container:proxy          berjalan
✅  container:app            berjalan
✅  container:db             berjalan
✅  container:prometheus     berjalan
✅  container:grafana        berjalan
✅  container:node-exporter  berjalan
✅  proxy TLS /healthz       HTTP 200
✅  TLS handshake            berhasil
✅  header HSTS              ada
✅  header Server            disembunyikan
✅  app lewat proxy          halaman tampil
✅  proxy HTTP /lb-health    HTTP 200
✅  metrik /metrics          format Prometheus
✅  app→db                   TCP terjangkau
✅  prometheus /-/ready      HTTP 200
✅  prometheus targets       3/3 up
✅  grafana /api/health      database ok
✅  dashboard ter-provision  2 ditemukan
✅  postgres pg_isready      menerima koneksi
✅  skema ter-init           2 tabel
----------------------------------------------------------------
  LOLOS: 20   GAGAL: 0
================================================================
```

## Mulai pakai

Butuh Docker + Compose v2.

```bash
git clone https://github.com/nullbyte12007/homelab-stack
cd homelab-stack

make up        # buat .env, pull image, build app, jalankan semua
make verify    # buktikan semuanya hidup (20 pemeriksaan)
```

Lalu buka:

- **app** — https://localhost:8443 (sertifikat internal → `curl -k`, atau impor
  `homelab-proxy:/data/caddy/pki/authorities/local/root.crt`)
- **Grafana** — http://127.0.0.1:3000 (dashboard "Homelab — Ringkasan" sudah ter-provision)
- **Prometheus** — http://127.0.0.1:9090

Perintah lain:

```bash
make ps        # status container
make logs      # ikuti log
make backup    # dump database ke ./backups (retensi 7, atur BACKUP_KEEP)
make restore FILE=backups/homelab-....sql.gz
make down      # hentikan (data tersimpan di volume)
make clean     # hentikan + HAPUS volume (data hilang)
```

## Dua hal yang sempat bikin gagal (dan pelajarannya)

Repo ini tidak langsung jadi — dua perilaku Docker/Caddy ini sempat bikin verifikasi merah.
Gua tulis di sini karena dokumentasi resminya kurang eksplisit:

**1. Docker tidak menerbitkan port untuk container yang hanya di jaringan `internal: true`.**
Prometheus dan Grafana tadinya cuma di jaringan `internal` → port 9090/3000 tidak muncul di
host (`connection refused`) walaupun container-nya "Up" dan `docker compose config` tetap
menampilkan port-nya. Solusinya: mereka ditempel juga ke jaringan `edge` (non-internal).
Sekarang ada komentar di `compose.yaml` supaya tidak terulang.

**2. `tls internal` Caddy menerbitkan sertifikat untuk HOSTNAME, bukan IP.**
Dengan blok `:443`, Caddy tidak tahu nama apa yang harus disertifikasi → setiap handshake
gagal dengan `TLS alert internal error`. Solusinya: sebutkan hostname eksplisit
(`localhost, lab.localhost`) dan akses lewat `https://localhost:8443`, bukan `https://127.0.0.1:8443`.

## Struktur

```
homelab-stack/
├── compose.yaml                 # definisi seluruh stack
├── Makefile                     # up/down/verify/backup/restore/clean
├── .env.example                 # template kredensial & port
├── app/                         # aplikasi demo (stdlib, non-root)
├── caddy/Caddyfile              # proxy + TLS internal + header keamanan
├── db/init/01-schema.sql        # skema awal
├── monitoring/prometheus/       # konfigurasi scrape
├── monitoring/grafana/          # provisioning datasource + dashboard
└── scripts/
    ├── verify.sh                # 20 pemeriksaan end-to-end
    ├── backup.sh                # pg_dump + retensi
    └── restore.sh               # pulihkan dump
```

## Keamanan & kebersihan (yang sudah dilakukan)

- Semua port hanya di `127.0.0.1` secara default
- Password **wajib** diisi — compose menolak jalan tanpa `POSTGRES_PASSWORD`/`GRAFANA_PASSWORD`
- `.env` masuk `.gitignore`; ada `.env.example` sebagai template
- Aplikasi jalan sebagai **user non-root** di dalam container
- Header keamanan dipasang di proxy: HSTS, `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, dan `Server` disembunyikan
- Jaringan `internal` memisahkan database & app dari akses keluar
- Grafana: pendaftaran pengguna dimatikan, telemetri dimatikan

## Batasan yang jujur

- **Untuk lab, bukan produksi apa adanya.** Untuk produksi masih perlu: pin digest image,
  secrets manager (bukan `.env`), backup offsite, TLS dengan domain nyata, dan pemantauan
  uptime dari luar.
- **Image memakai tag minor, bukan digest.** Tag seperti `postgres:16-alpine` bisa berubah;
  untuk produksi pin ke digest (`@sha256:...`).
- Aplikasi demo hanya memeriksa **TCP** ke database, bukan query — itu cukup untuk
  menunjukkan metrik, tapi tidak memvalidasi kredensial/konten.
- Dashboard Grafana sengaja ringkas (4 panel), bukan dashboard produksi lengkap.
- `verify.sh` mengasumsikan service dijalankan oleh compose **project ini** (mencocokkan nama
  service `proxy`, `app`, `db`, …). Kalau diubah, sesuaikan juga.
- Ansible playbook untuk deploy ke VPS **belum ada** — itu langkah berikutnya yang jelas.

## Lisensi

MIT — lihat [LICENSE](LICENSE). Copyright (c) 2026 M Yusuf Chairul Saleh.
