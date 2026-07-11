#!/usr/bin/env bash
# Iran side — Rathole server + HAProxy (safe, no duplicate restart)
set -euo pipefail

IRAN_PORT="${IRAN_PORT:-2088}"
RATHOLE_TOKEN="${RATHOLE_TOKEN:-avavlessiran174062832f02}"

info() { echo "→ $*"; }
ok()   { echo "✓ $*"; }

fix_rathole_systemd() {
  info "Stopping broken rathole restart loop (keeps existing process if running)..."
  systemctl stop rathole 2>/dev/null || true
  systemctl disable rathole 2>/dev/null || true
  systemctl reset-failed rathole 2>/dev/null || true

  cat > /etc/systemd/system/rathole-guard.service <<EOF
[Unit]
Description=Rathole server guard (start only if port 3083 is free)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'if ss -ltnp | grep -q ":3083.*rathole"; then echo rathole-already-running; exit 0; fi; exec /usr/local/bin/rathole --server /etc/rathole/server.toml'

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable rathole-guard.service
  ok "rathole-guard enabled (no duplicate bind on :3083)"
}

ensure_vless_service() {
  info "Ensuring Rathole VLESS service on 0.0.0.0:${IRAN_PORT}..."

  if ! grep -q 'germany_vless_iran' /etc/rathole/server.toml 2>/dev/null; then
    cat >> /etc/rathole/server.toml <<EOF

[server.services.germany_vless_iran]
token = "${RATHOLE_TOKEN}"
bind_addr = "0.0.0.0:${IRAN_PORT}"
EOF
    ok "Added germany_vless_iran to server.toml (reload manually if rathole already running)"
  fi

  if grep -q '49.13.6.108:46100' /etc/haproxy/haproxy.cfg 2>/dev/null; then
    sed -i "s|server de_main 49.13.6.108:46100|server de_main 127.0.0.1:${IRAN_PORT}|" /etc/haproxy/haproxy.cfg
    systemctl reload haproxy 2>/dev/null || systemctl restart haproxy
    ok "HAProxy :444 → 127.0.0.1:${IRAN_PORT}"
  fi
}

main() {
  echo "AVA CDN — Iran tunnel side (safe mode)"
  fix_rathole_systemd
  ensure_vless_service
  echo ""
  ok "Iran tunnel entry: 80.249.112.56:${IRAN_PORT} (HAProxy :444)"
  echo "  Do NOT run: systemctl restart rathole  (causes user disconnects)"
  echo "  Existing rathole PID is preserved if already listening on :3083"
}

main "$@"
