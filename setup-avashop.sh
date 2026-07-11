#!/usr/bin/env bash
# AVA CDN — avashop.online one-shot deploy (CDN separate from tunnel)
set -euo pipefail

readonly INSTALL_DIR="/opt/ava-cdn/avashop.online"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SITE_SRC="${SCRIPT_DIR}/sites/avashop.online"
readonly LOG_FILE="/var/log/ava-cdn-avashop-setup.log"
readonly WITH_INBOUND="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}→${NC}  $*"; echo "[$(date -Iseconds)] $*" >> "${LOG_FILE}"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*"; exit 1; }

rand_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}

[[ "${EUID:-$(id -u)}" -eq 0 ]] || error "Run as root: sudo bash setup-avashop.sh"

echo -e "${BOLD}${CYAN}"
echo "  AVA CDN — avashop.online (CDN separate from tunnel)"
echo -e "${NC}"

mkdir -p "${INSTALL_DIR}/certs" "${INSTALL_DIR}/xray" "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

# ─── Docker ───
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# ─── Xray inbound (VLESS-gRPC via CDN) ───
INBOUND_UUID=""
if [[ "${WITH_INBOUND}" == "--with-inbound" ]]; then
  if [[ -f "${INSTALL_DIR}/inbound.json" ]]; then
    INBOUND_UUID="$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/inbound.json'))['uuid'])" 2>/dev/null || true)"
    info "Reusing existing inbound UUID"
  fi
  [[ -z "${INBOUND_UUID}" ]] && INBOUND_UUID="$(rand_uuid)"

  info "Creating VLESS-gRPC inbound (CDN path via de.avashop.online)..."
  sed "s/{{UUID}}/${INBOUND_UUID}/g" "${SITE_SRC}/xray/config.json.template" > "${INSTALL_DIR}/xray/config.json"
  chmod 600 "${INSTALL_DIR}/xray/config.json"

  cat > "${INSTALL_DIR}/inbound.json" <<EOF
{
  "name": "avashop-cdn-grpc",
  "protocol": "vless",
  "uuid": "${INBOUND_UUID}",
  "address": "de.avashop.online",
  "port": 443,
  "network": "grpc",
  "serviceName": "grpc-avashop",
  "security": "tls",
  "sni": "de.avashop.online",
  "path": "/grpc-avashop",
  "cdn": "cloudflare",
  "tunnel_host": "tunnel.avashop.online",
  "note": "CDN inbound — separate from tunnel subdomain"
}
EOF
  chmod 600 "${INSTALL_DIR}/inbound.json"
  success "Inbound designed: VLESS-gRPC on de.avashop.online:443"
fi

# ─── Copy site configs ───
info "Deploying avashop.online configs to ${INSTALL_DIR}..."
cp "${SITE_SRC}/nginx.conf" "${INSTALL_DIR}/nginx.conf"
cp "${SITE_SRC}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
cp "${SITE_SRC}/site.env.example" "${INSTALL_DIR}/.env"
chmod 600 "${INSTALL_DIR}/.env"

# ─── Origin certificate ───
if [[ ! -f "${INSTALL_DIR}/certs/origin.pem" ]]; then
  info "Generating temporary self-signed certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${INSTALL_DIR}/certs/origin-key.pem" \
    -out "${INSTALL_DIR}/certs/origin.pem" \
    -subj "/CN=avashop.online" 2>/dev/null
  chmod 600 "${INSTALL_DIR}/certs/origin-key.pem"
  warn "Replace with Cloudflare Origin Certificate (see docs/avashop.online-setup.md)"
fi

# ─── UFW ───
if command -v ufw >/dev/null 2>&1; then
  ssh_port="$(grep -E '^Port[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1 || echo 22)"
  ufw allow "${ssh_port}/tcp" 2>/dev/null || true
  ufw allow 80/tcp 2>/dev/null || true
  ufw allow 443/tcp 2>/dev/null || true
  ufw allow 9100/tcp 2>/dev/null || true
  ufw --force enable 2>/dev/null || true
fi

# ─── Start services ───
info "Starting services..."
cd "${INSTALL_DIR}"
docker compose --env-file .env pull -q 2>/dev/null || true
if [[ "${WITH_INBOUND}" == "--with-inbound" ]]; then
  docker compose --env-file .env up -d
else
  docker compose --env-file .env up -d nginx node-exporter
fi

# ─── Health check ───
sleep 3
if curl -fsS http://127.0.0.1/health >/dev/null 2>&1; then
  success "Health check passed"
else
  warn "Health check pending — verify: curl http://127.0.0.1/health"
fi

if [[ "${WITH_INBOUND}" == "--with-inbound" ]] && docker ps --format '{{.Names}}' | grep -q ava-avashop-xray; then
  success "Xray inbound container running"
fi

# ─── Client config export ───
if [[ -f "${INSTALL_DIR}/inbound.json" ]]; then
  python3 - <<'PY' "${INSTALL_DIR}/inbound.json" > "${INSTALL_DIR}/client-vless-grpc.json"
import json, sys
d = json.load(open(sys.argv[1]))
print(json.dumps({
  "remarks": "avashop CDN — VLESS-gRPC",
  "protocol": "vless",
  "address": d["address"],
  "port": d["port"],
  "id": d["uuid"],
  "security": "tls",
  "sni": d["sni"],
  "network": "grpc",
  "serviceName": d["serviceName"],
  "path": d["path"],
  "alpn": ["h2"],
  "fingerprint": "chrome"
}, indent=2))
PY
  chmod 600 "${INSTALL_DIR}/client-vless-grpc.json"
fi

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║           avashop.online — CDN DEPLOYED (SEPARATE)          ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC} CDN (Proxied):  avashop.online, www, de.avashop.online     ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Tunnel (DNS):   tunnel.avashop.online → DNS only!          ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Server IP:       49.13.6.108                                 ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Config:          ${INSTALL_DIR}                              ${BOLD}${GREEN}║${NC}"
if [[ -f "${INSTALL_DIR}/inbound.json" ]]; then
echo -e "${BOLD}${GREEN}║${NC} Inbound:         VLESS-gRPC de.avashop.online:443            ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Service:         grpc-avashop                               ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Client config:  ${INSTALL_DIR}/client-vless-grpc.json       ${BOLD}${GREEN}║${NC}"
fi
echo -e "${BOLD}${GREEN}║${NC} Next:            Cloudflare DNS + gRPC enabled               ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
if [[ -f "${INSTALL_DIR}/inbound.json" ]]; then
  echo -e "${BOLD}Inbound UUID:${NC}"
  python3 -c "import json; d=json.load(open('${INSTALL_DIR}/inbound.json')); print(d['uuid'])"
  echo ""
  echo -e "${BOLD}VLESS Link:${NC}"
  python3 - <<PY
import json, urllib.parse
d = json.load(open("${INSTALL_DIR}/inbound.json"))
q = urllib.parse.urlencode({
    "type": "grpc", "security": "tls", "sni": d["sni"],
    "serviceName": d["serviceName"], "alpn": "h2", "fp": "chrome"
})
print(f"vless://{d['uuid']}@{d['address']}:{d['port']}?{q}#avashop-cdn-grpc")
PY
fi
success "Done. Read docs/avashop.online-setup.md for Cloudflare DNS changes."
