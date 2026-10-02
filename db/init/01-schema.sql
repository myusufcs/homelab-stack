-- Inisialisasi skema homelab-stack.
-- Dijalankan otomatis oleh image postgres saat volume data masih kosong.

CREATE TABLE IF NOT EXISTS hosts (
    id          SERIAL PRIMARY KEY,
    hostname    TEXT NOT NULL UNIQUE,
    ip          INET,
    kind        TEXT DEFAULT 'unknown',
    last_seen   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS events (
    id          BIGSERIAL PRIMARY KEY,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    severity    TEXT NOT NULL DEFAULT 'info',
    source      TEXT NOT NULL,
    message     TEXT NOT NULL
);

INSERT INTO hosts (hostname, ip, kind) VALUES
    ('gw-utama',    '192.168.10.1', 'router'),
    ('pi-dashboard','192.168.10.2', 'server'),
    ('prn-lantai2', '192.168.10.5', 'printer')
ON CONFLICT (hostname) DO NOTHING;

INSERT INTO events (severity, source, message) VALUES
    ('info', 'seed', 'Skema awal dibuat oleh docker-entrypoint-initdb.d');

CREATE INDEX IF NOT EXISTS events_created_at_idx ON events (created_at DESC);
