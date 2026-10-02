# Arsitektur homelab-stack

## Peta layanan

```
                        host (laptop / VPS)
  ┌───────────────────────────────────────────────────────────────┐
  │                                                               │
  │   :8080 ─┐                                    :9090 ─┐        │
  │   :8443 ─┤  (hanya 127.0.0.1)                         │        │
  │          │                                            │        │
  │  ┌───────▼────────┐   network: edge          ┌────────▼──────┐ │
  │  │  caddy (proxy) │◄─────────────────────────┤  prometheus   │ │
  │  │  TLS internal  │                          └────────┬──────┘ │
  │  └───────┬────────┘                                   │ scrape  │
  │          │ reverse_proxy app:8000                     │        │
  │          │                    ┌───────────────────────┴─────┐  │
  │          │                    │                             │  │
  │  ┌───────▼────────┐   network: internal              ┌──────▼─┐│
  │  │      app       │◄─────────────────────────────────┤grafana ││
  │  │  (non-root)    │                                  └────────┘│
  │  └───────┬────────┘                                            │
  │          │ TCP 5432                            ┌──────────────┐│
  │  ┌───────▼────────┐                            │ node-exporter││
  │  │   postgres 16  │                            │  (metrik host)││
  │  │  volume: db_data│                           └──────────────┘│
  │  └────────────────┘                                            │
  └───────────────────────────────────────────────────────────────┘
```

## Jaringan

Dua bridge network, dengan alasan yang jelas:

- **`edge`** — satu-satunya jaringan yang punya jalur ke host (tempat publikasi port bekerja).
  Anggotanya: `proxy`, `prometheus`, `grafana`.
- **`internal`** (`internal: true`) — tanpa akses keluar. Anggotanya: `app`, `db`,
  `prometheus`, `node-exporter`.

Kenapa tidak semua di `internal`? **Docker tidak mem-publish port untuk container yang hanya
berada di jaringan internal** — inilah yang sempat membuat 9090/3000 tidak bisa diakses.
Karena itu container yang port-nya perlu diakses dari host ditempel juga ke `edge`.

Artinya `db` dan `app` tidak bisa menghubungi internet — permukaan serangnya lebih kecil.
`app` hanya bisa diakses dari `proxy` (tidak ada port yang dipublish).

## Alur satu permintaan

1. Browser → `https://localhost:8443`
2. **Caddy** melakukan TLS handshake dengan sertifikat dari CA internal-nya
   (dibuat saat pertama kali jalan, disimpan di volume `caddy_data`)
3. Header keamanan ditambahkan, `Server` dihapus
4. `reverse_proxy` meneruskan ke `app:8000` (nama service diselesaikan Docker DNS)
5. `app` menaikkan `homelab_requests_total` dan membalas HTML
6. Setiap 15 detik **Prometheus** menarik `app:8000/metrics`, `node-exporter:9100/metrics`,
   dan dirinya sendiri
7. **Grafana** membaca Prometheus lewat datasource yang di-provision, menampilkan 4 panel

## Titik pemeriksaan (`scripts/verify.sh`)

Verifikasi sengaja memeriksa **jalur nyata**, bukan hanya status container:

| Lapisan | Yang diperiksa |
|---|---|
| Container | 6 service berstatus running |
| TLS | handshake berhasil, sertifikat valid (via `curl -k`) |
| Header | HSTS ada, `Server` tidak bocor |
| Rute | app benar-benar terjangkau lewat proxy, isi halaman sesuai |
| Metrik | `/metrics` format Prometheus, `homelab_db_tcp_open = 1` |
| Monitoring | Prometheus ready, ≥3 target `up`, Grafana sehat, dashboard ada |
| Database | `pg_isready`, skema ter-init (≥2 tabel) |

Kalau salah satu gagal, skrip keluar dengan kode ≠ 0 — cocok dipakai di CI atau cron.

## Kredensial & konfigurasi

- `.env` dibuat dari `.env.example` oleh `make up`; **password wajib diubah** — compose
  memakai `${POSTGRES_PASSWORD:?...}` sehingga gagal jalan kalau kosong.
- `.env` tidak pernah di-commit (ada di `.gitignore`).
- `.env.example` hanya berisi placeholder.

## Rencana berikutnya

- Ansible playbook: pasang Docker + deploy stack ini ke VPS baru dalam satu perintah
- Backup offsite (rclone/S3) + uji restore terjadwal
- Alertmanager + aturan alert (disk penuh, service mati, sertifikat hampir kedaluwarsa)
- Pin image ke digest untuk reproduksibilitas
