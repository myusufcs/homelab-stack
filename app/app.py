"""Aplikasi demo untuk homelab-stack.

Sengaja memakai standard library saja (tanpa framework) supaya image-nya kecil
dan tidak ada dependensi pihak ketiga yang perlu di-“trust”.

Endpoint:
  GET /         halaman status
  GET /healthz  health check (200)
  GET /metrics  metrik format Prometheus
  GET /info     JSON berisi konfigurasi & status konektivitas DB
"""

from __future__ import annotations

import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

START = time.time()
REQUESTS = {"total": 0}
DB_HOST = os.environ.get("DB_HOST", "db")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "homelab")
APP_ENV = os.environ.get("APP_ENV", "lab")


def db_tcp_open(timeout: float = 1.5) -> bool:
    """Cek keterjangkauan TCP ke database (bukan query) — cukup untuk metrik."""
    try:
        with socket.create_connection((DB_HOST, DB_PORT), timeout=timeout):
            return True
    except OSError:
        return False


def metrics_text() -> str:
    up = time.time() - START
    db_open = 1 if db_tcp_open() else 0
    return "\n".join([
        "# HELP homelab_uptime_seconds Umur proses aplikasi.",
        "# TYPE homelab_uptime_seconds gauge",
        f"homelab_uptime_seconds {up:.1f}",
        "# HELP homelab_requests_total Jumlah permintaan HTTP yang dilayani.",
        "# TYPE homelab_requests_total counter",
        f"homelab_requests_total {REQUESTS['total']}",
        "# HELP homelab_db_tcp_open Status keterjangkauan TCP ke PostgreSQL (1=terbuka).",
        "# TYPE homelab_db_tcp_open gauge",
        f"homelab_db_tcp_open {db_open}",
        "",
    ])


def index_html() -> str:
    db_open = db_tcp_open()
    status = "terhubung" if db_open else "TIDAK terjangkau"
    warna = "#86efac" if db_open else "#f87171"
    return f"""<!doctype html><html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>homelab-stack</title>
<style>
 body{{font:15px/1.6 system-ui,sans-serif;margin:0;background:#0f1115;color:#e6e6e6}}
 main{{max-width:720px;margin:0 auto;padding:48px 24px}}
 h1{{font-size:22px;margin:0 0 6px}} .sub{{color:#8b93a1;font-size:13px;margin-bottom:28px}}
 .card{{background:#161a21;border:1px solid #242a33;border-radius:10px;padding:18px;margin-bottom:14px}}
 .k{{color:#8b93a1;font-size:12px;text-transform:uppercase;letter-spacing:.5px}}
 .v{{font-size:17px;font-weight:600}} code{{background:#1c2430;padding:2px 6px;border-radius:4px}}
 a{{color:#7dd3fc}} ul{{padding-left:18px}} li{{margin:4px 0}}
</style></head><body><main>
<h1>homelab-stack</h1>
<div class="sub">reverse proxy + TLS internal · app · PostgreSQL · Prometheus · Grafana</div>

<div class="card"><div class="k">Lingkungan</div><div class="v">{APP_ENV}</div></div>
<div class="card"><div class="k">Database ({DB_NAME} @ {DB_HOST}:{DB_PORT})</div>
  <div class="v" style="color:{warna}">{status}</div></div>
<div class="card"><div class="k">Uptime proses</div><div class="v">{time.time() - START:.0f} detik</div></div>

<div class="card"><div class="k">Endpoint</div><ul>
  <li><code>/healthz</code> — health check</li>
  <li><code>/metrics</code> — metrik Prometheus</li>
  <li><code>/info</code> — konfigurasi &amp; status JSON</li>
</ul></div>
</main></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "homelab-app"
    sys_version = ""

    def log_message(self, fmt, *args):
        print(f"[app] {self.address_string()} {fmt % args}", flush=True)

    def _send(self, body: str, code: int = 200, ctype: str = "text/html; charset=utf-8"):
        raw = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):                                     # noqa: N802
        REQUESTS["total"] += 1
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path == "/healthz":
            return self._send("ok\n", ctype="text/plain")
        if path == "/metrics":
            return self._send(metrics_text(), ctype="text/plain; version=0.0.4")
        if path == "/info":
            return self._send(json.dumps({
                "env": APP_ENV,
                "uptime_seconds": round(time.time() - START, 1),
                "requests_total": REQUESTS["total"],
                "db": {"host": DB_HOST, "port": DB_PORT, "name": DB_NAME,
                       "tcp_open": db_tcp_open()},
            }, indent=2), ctype="application/json")
        if path == "/":
            return self._send(index_html())
        return self._send("tidak ditemukan\n", 404, "text/plain")


def main() -> None:
    port = int(os.environ.get("APP_PORT", "8000"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[app] mendengarkan di :{port} (env={APP_ENV}, db={DB_HOST}:{DB_PORT})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
