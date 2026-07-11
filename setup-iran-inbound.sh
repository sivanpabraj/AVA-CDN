#!/usr/bin/env bash
# Iran-optimized inbound: User → Iran (80.249.112.56) → Rathole → Germany Xray
set -euo pipefail

IRAN_IP="80.249.112.56"
IRAN_PASS="${IRAN_PASS:-}"
GERMANY_IP="49.13.6.108"
GERMANY_PASS="${GERMANY_PASS:-}"
INSTALL_DIR="/opt/ava-cdn/iran-inbound"
IRAN_PORT="${IRAN_PORT:-2088}"
GERMANY_PORT="${GERMANY_PORT:-18443}"
RATHOLE_TOKEN="${RATHOLE_TOKEN:-avavlessiran$(openssl rand -hex 8)}"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${CYAN}→${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }

rand_uuid() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())'
}

deploy_germany() {
  local uuid="$1"
  info "Germany: adding VLESS-TCP inbound on 127.0.0.1:${GERMANY_PORT}"

  python3 - <<PY
import sqlite3, json
uid = "${uuid}"
port = ${GERMANY_PORT}
settings = json.dumps({"clients": [{"id": uid, "email": "iran@avashop.online", "flow": ""}], "decryption": "none", "fallbacks": []})
stream = json.dumps({"network": "tcp", "security": "none", "tcpSettings": {"header": {"type": "none"}, "acceptProxyProtocol": False}})
sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls"]})
conn = sqlite3.connect("/etc/x-ui/x-ui.db")
conn.execute("DELETE FROM inbounds WHERE tag='inbound-iran-vless'")
conn.execute(
    "INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,listen,port,protocol,settings,stream_settings,tag,sniffing) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    (1, 0, 0, 0, "Iran-VLESS-TCP", 1, 0, "127.0.0.1", port, "vless", settings, stream, "inbound-iran-vless", sniff),
)
conn.commit()
PY

  # Update rathole client
  if ! grep -q 'germany_vless_iran' /etc/rathole/client.toml 2>/dev/null; then
    cat >> /etc/rathole/client.toml <<EOF

[client.services.germany_vless_iran]
token = "${RATHOLE_TOKEN}"
local_addr = "127.0.0.1:${GERMANY_PORT}"
EOF
  else
    sed -i "s|token = \".*\"|token = \"${RATHOLE_TOKEN}\"|" /etc/rathole/client.toml
  fi

  x-ui restart-xray
  systemctl restart rathole 2>/dev/null || pkill -HUP rathole 2>/dev/null || true
  ok "Germany inbound ready (127.0.0.1:${GERMANY_PORT})"
}

deploy_iran() {
  info "Iran: exposing VLESS via Rathole on 0.0.0.0:${IRAN_PORT}"

  if ! grep -q 'germany_vless_iran' /etc/rathole/server.toml 2>/dev/null; then
    cat >> /etc/rathole/server.toml <<EOF

[server.services.germany_vless_iran]
token = "${RATHOLE_TOKEN}"
bind_addr = "0.0.0.0:${IRAN_PORT}"
EOF
  fi

  # Fix dead HAProxy backends → use Rathole local SS tunnel
  if grep -q '49.13.6.108:40915' /etc/haproxy/haproxy.cfg; then
    sed -i 's|server de_ss1 49.13.6.108:40915|server de_ss1 127.0.0.1:19454|' /etc/haproxy/haproxy.cfg
    sed -i 's|server de_ss2 49.13.6.108:26909|server de_ss2 127.0.0.1:19454|' /etc/haproxy/haproxy.cfg
    sed -i 's|server de_main 49.13.6.108:46100|server de_main 127.0.0.1:'"${IRAN_PORT}"'|' /etc/haproxy/haproxy.cfg
    systemctl reload haproxy 2>/dev/null || systemctl restart haproxy
  fi

  systemctl restart rathole
  ok "Iran entry ready (${IRAN_IP}:${IRAN_PORT})"
}

save_config() {
  local uuid="$1"
  mkdir -p "${INSTALL_DIR}"
  cat > "${INSTALL_DIR}/inbound.json" <<EOF
{
  "name": "avashop-iran-vless",
  "protocol": "vless",
  "uuid": "${uuid}",
  "address": "${IRAN_IP}",
  "port": ${IRAN_PORT},
  "network": "tcp",
  "security": "none",
  "path": "",
  "note": "Iran relay → Rathole → Germany. NO Cloudflare. For users inside Iran.",
  "alt_port_haproxy": 444,
  "latency_expected_ms": 80
}
EOF
  chmod 600 "${INSTALL_DIR}/inbound.json"
}

main() {
  local uuid
  uuid="$(rand_uuid)"
  echo -e "${BOLD}AVA CDN — Iran Inbound Setup${NC}"
  deploy_germany
  save_config "${uuid}"
  echo ""
  echo -e "${BOLD}${GREEN}Iran VLESS Link:${NC}"
  echo "vless://${uuid}@${IRAN_IP}:${IRAN_PORT}?type=tcp&security=none#avashop-iran"
  echo ""
  echo "Also via HAProxy port 444 on Iran"
}

main "$@"
