#!/usr/bin/env bash
# Iran-optimized inbound: User → Iran → Rathole → Germany Xray
# Safe: uses x-ui restart-xray only (not full panel restart)
set -euo pipefail

IRAN_IP="80.249.112.56"
GERMANY_IP="49.13.6.108"
INSTALL_DIR="/opt/ava-cdn/iran-inbound"
IRAN_PORT="${IRAN_PORT:-2088}"
GERMANY_PORT="${GERMANY_PORT:-18443}"
RATHOLE_TOKEN="${RATHOLE_TOKEN:-avavlessiran174062832f02}"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${CYAN}→${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }

rand_uuid() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())'
}

deploy_germany() {
  local uuid="$1"
  info "Germany: VLESS-TCP on 127.0.0.1:${GERMANY_PORT} (x-ui)"

  python3 - <<PY
import sqlite3, json, time
uid = "${uuid}"
email = "iran@avashop.online"
port = ${GERMANY_PORT}
now = int(time.time() * 1000)
settings = json.dumps({"clients": [], "decryption": "none", "fallbacks": []})
stream = json.dumps({"network": "tcp", "security": "none", "tcpSettings": {"header": {"type": "none"}, "acceptProxyProtocol": False}})
sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls"]})

con = sqlite3.connect("/etc/x-ui/x-ui.db")
cur = con.cursor()

cur.execute("DELETE FROM inbounds WHERE tag='inbound-iran-vless'")
cur.execute(
    "INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,listen,port,protocol,settings,stream_settings,tag,sniffing) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    (1, 0, 0, 0, "Iran-VLESS-TCP", 1, 0, "127.0.0.1", port, "vless", settings, stream, "inbound-iran-vless", sniff),
)
inbound_id = cur.lastrowid

cur.execute("SELECT id FROM clients WHERE email=?", (email,))
row = cur.fetchone()
if row:
    client_id = row[0]
    cur.execute("UPDATE clients SET uuid=?, enable=1, updated_at=? WHERE id=?", (uid, now, client_id))
else:
    cur.execute(
        "INSERT INTO clients (email, uuid, enable, flow, security, total_gb, expiry_time, reset, created_at, updated_at) VALUES (?, ?, 1, '', '', 0, 0, 0, ?, ?)",
        (email, uid, now, now),
    )
    client_id = cur.lastrowid

cur.execute("DELETE FROM client_inbounds WHERE inbound_id=?", (inbound_id,))
cur.execute("INSERT INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, '', ?)", (client_id, inbound_id, now))
cur.execute("DELETE FROM client_traffics WHERE inbound_id=? AND email=?", (inbound_id, email))
cur.execute("INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset, last_online) VALUES (?, 1, ?, 0, 0, 0, 0, 0, 0)", (inbound_id, email))
con.commit()
con.close()
PY

  if ! grep -q 'germany_vless_iran' /etc/rathole/client.toml 2>/dev/null; then
    cat >> /etc/rathole/client.toml <<EOF

[client.services.germany_vless_iran]
token = "${RATHOLE_TOKEN}"
local_addr = "127.0.0.1:${GERMANY_PORT}"
EOF
  fi

  info "Restarting xray only (SS users: ~1s blip, not full panel restart)..."
  x-ui restart-xray
  ok "Germany inbound ready (127.0.0.1:${GERMANY_PORT})"
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
  "alt_port_haproxy": 444,
  "note": "Iran relay → Rathole → Germany. NO Cloudflare. For users inside Iran.",
  "ss_users_port": 1080
}
EOF
  chmod 600 "${INSTALL_DIR}/inbound.json"
}

main() {
  local uuid
  uuid="$(rand_uuid)"
  echo -e "${BOLD}AVA CDN — Iran Inbound Setup (Germany side)${NC}"
  deploy_germany "${uuid}"
  save_config "${uuid}"
  echo ""
  echo -e "${BOLD}${GREEN}Iran VLESS Link:${NC}"
  echo "vless://${uuid}@${IRAN_IP}:${IRAN_PORT}?type=tcp&security=none#avashop-iran"
  echo ""
  echo "Then on Iran: bash setup-iran-iran-side.sh"
  echo "SS existing users: ${IRAN_IP}:1080 (unchanged)"
}

main "$@"
