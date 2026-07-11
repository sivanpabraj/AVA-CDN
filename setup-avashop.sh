#!/usr/bin/env bash
# AVA CDN — avashop.online one-shot deploy (CDN separate from tunnel)
set -euo pipefail

readonly INSTALL_DIR="/opt/ava-cdn/avashop.online"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SITE_SRC="${SCRIPT_DIR}/sites/avashop.online"
readonly LOG_FILE="/var/log/ava-cdn-avashop-setup.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}→${NC}  $*"; echo "[$(date -Iseconds)] $*" >> "${LOG_FILE}"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*"; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || error "Run as root: sudo bash setup-avashop.sh"

echo -e "${BOLD}${CYAN}"
echo "  AVA CDN — avashop.online (CDN separate from tunnel)"
echo -e "${NC}"

mkdir -p "${INSTALL_DIR}/certs" "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

# ─── Docker ───
if ! command -v docker >/dev/null 2>&1; then
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
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
info "Starting Nginx CDN origin..."
cd "${INSTALL_DIR}"
docker compose --env-file .env pull -q 2>/dev/null || true
docker compose --env-file .env up -d

# ─── Health check ───
sleep 2
if curl -fsS http://127.0.0.1/health >/dev/null 2>&1; then
  success "Health check passed"
else
  warn "Health check pending — verify: curl http://127.0.0.1/health"
fi

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║           avashop.online — CDN DEPLOYED (SEPARATE)          ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC} CDN (Proxied):  avashop.online, www, de.avashop.online     ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Tunnel (DNS):   tunnel.avashop.online → DNS only!          ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Server IP:       49.13.6.108                                 ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Config:          ${INSTALL_DIR}                              ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║${NC} Next:            Fix Cloudflare DNS (see docs/)            ${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "Done. Read docs/avashop.online-setup.md for Cloudflare DNS changes."
