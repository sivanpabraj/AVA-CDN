#!/usr/bin/env bash
# AVA CDN — Production installer
# CDN Origin (Germany) separate from optional Iran relay tunnel
set -euo pipefail

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Constants
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
readonly SCRIPT_VERSION="1.0.0"
readonly INSTALL_DIR="/opt/ava-cdn"
readonly ENV_FILE="${INSTALL_DIR}/.env"
readonly LOG_FILE="/var/log/ava-cdn-setup.log"
readonly COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
readonly NGINX_CONF_DIR="${INSTALL_DIR}/nginx"
readonly CERTS_DIR="${INSTALL_DIR}/certs"
readonly RATHOLE_VERSION="0.5.0"
readonly RATHOLE_INSTALL="/usr/local/bin/rathole"
readonly XUI_IMAGE="ghcr.io/mhsanaei/3x-ui:latest"
readonly XUI_CONTAINER="ava-3x-ui"
readonly NGINX_CONTAINER="ava-nginx"
readonly NODE_EXPORTER_CONTAINER="ava-node-exporter"

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Colors & output
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "[${ts}] [${level}] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

info()    { echo -e "${BLUE}ℹ${NC}  $*"; log "INFO" "$*"; }
success() { echo -e "${GREEN}✓${NC}  $*"; log "OK" "$*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; log "WARN" "$*"; }
error()   { echo -e "${RED}✗${NC}  $*"; log "ERROR" "$*"; }
step()    { echo -e "${CYAN}→${NC}  $*"; log "STEP" "$*"; }

on_error() {
  local line="$1"
  error "Script failed at line ${line}. Check ${LOG_FILE}"
  exit 1
}
trap 'on_error ${LINENO}' ERR

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "Run as root: sudo bash setup.sh"
    exit 1
  fi
}

show_banner() {
  echo -e "${BOLD}${CYAN}"
  cat <<'BANNER'
    _    ____    _    ____ ____  _   _ 
   / \  |  _ \  / \  / ___|  _ \| \ | |
  / _ \ | | | |/ _ \| |   | | | |  \| |
 / ___ \| |_| / ___ \ |___| |_| | |\  |
/_/   \_\____/_/   \_\____|____/|_| \_|

  AVA CDN Installer v1.0 — CDN Origin + Optional Relay
BANNER
  echo -e "${NC}"
}

rand_alnum() {
  local len="${1:-16}"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${len}"
}

rand_port() {
  local min="${1:-40000}"
  local max="${2:-50000}"
  echo $(( min + RANDOM % (max - min + 1) ))
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) error "Unsupported architecture: ${arch}"; exit 1 ;;
  esac
}

detect_public_ip() {
  local ip=""
  local apis=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
  )
  for api in "${apis[@]}"; do
    ip="$(curl -fsSL --max-time 5 "${api}" 2>/dev/null || true)"
    if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "${ip}"
      return 0
    fi
  done
  echo ""
}

detect_ssh_port() {
  local port="22"
  if [[ -f /etc/ssh/sshd_config ]]; then
    local cfg_port
    cfg_port="$(grep -E '^Port[[:space:]]+' /etc/ssh/sshd_config | awk '{print $2}' | tail -1 || true)"
    [[ -n "${cfg_port}" ]] && port="${cfg_port}"
  fi
  echo "${port}"
}

ensure_dirs() {
  mkdir -p "${INSTALL_DIR}" "${NGINX_CONF_DIR}" "${CERTS_DIR}" "$(dirname "${LOG_FILE}")"
  touch "${LOG_FILE}"
  chmod 600 "${LOG_FILE}" 2>/dev/null || true
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a; source "${ENV_FILE}"; set +a
  fi
}

save_env_var() {
  local key="$1"
  local value="$2"
  ensure_dirs
  if [[ -f "${ENV_FILE}" ]] && grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    echo "${key}=${value}" >> "${ENV_FILE}"
  fi
  chmod 600 "${ENV_FILE}"
}

write_env_header() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cat > "${ENV_FILE}" <<EOF
# AVA CDN — generated $(date -Iseconds)
# chmod 600 — do not share
EOF
    chmod 600 "${ENV_FILE}"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    success "Docker already installed: $(docker --version)"
    return 0
  fi
  step "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  success "Docker installed"
}

configure_ufw() {
  local ssh_port="$1"
  shift
  local extra_ports=("$@")

  if ! command -v ufw >/dev/null 2>&1; then
    step "Installing UFW..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ufw
  fi

  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${ssh_port}/tcp" comment 'SSH'

  for p in "${extra_ports[@]}"; do
    [[ -n "${p}" ]] && ufw allow "${p}/tcp" comment "AVA-CDN"
  done

  ufw --force enable
  success "UFW configured (SSH: ${ssh_port}, extra: ${extra_ports[*]:-none})"
}

write_nginx_config() {
  local domain="${1:-_}"
  cat > "${NGINX_CONF_DIR}/default.conf" <<EOF
# AVA CDN Origin — Nginx reverse proxy + cache
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=ava_cache:50m max_size=2g inactive=7d use_temp_path=off;

upstream origin_backend {
    server ${ORIGIN_UPSTREAM:-127.0.0.1:8080};
    keepalive 32;
}

server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://origin_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache ava_cache;
        proxy_cache_valid 200 302 1h;
        proxy_cache_valid 404 1m;
        add_header X-Cache-Status \$upstream_cache_status;
    }
    location /api/ {
        proxy_pass http://origin_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_cache off;
    }
}

server {
    listen 443 ssl http2;
    server_name ${domain};

    ssl_certificate     /etc/nginx/certs/origin.pem;
    ssl_certificate_key /etc/nginx/certs/origin-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://origin_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache ava_cache;
        proxy_cache_valid 200 302 1h;
        proxy_cache_valid 404 1m;
        add_header X-Cache-Status \$upstream_cache_status;
    }
    location /api/ {
        proxy_pass http://origin_backend;
        proxy_cache off;
    }
}
EOF
}

write_self_signed_certs() {
  if [[ -f "${CERTS_DIR}/origin.pem" && -f "${CERTS_DIR}/origin-key.pem" ]]; then
    return 0
  fi
  step "Generating temporary self-signed origin certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${CERTS_DIR}/origin-key.pem" \
    -out "${CERTS_DIR}/origin.pem" \
    -subj "/CN=ava-cdn-origin" 2>/dev/null
  chmod 600 "${CERTS_DIR}/origin-key.pem"
  warn "Using self-signed cert. Replace with Cloudflare Origin Certificate (see docs/cloudflare-setup.md)"
}

write_docker_compose_cdn() {
  cat > "${COMPOSE_FILE}" <<'COMPOSE'
services:
  nginx:
    image: nginx:1.27-alpine
    container_name: ava-nginx
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "${NGINX_HTTP_PORT:-80}:80"
      - "${NGINX_HTTPS_PORT:-443}:443"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./certs:/etc/nginx/certs:ro
      - nginx_cache:/var/cache/nginx
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 1G

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: ava-node-exporter
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "${NODE_EXPORTER_PORT:-9100}:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 256M

volumes:
  nginx_cache:
COMPOSE
}

write_docker_compose_with_xui() {
  local panel_port="$1"
  cat > "${COMPOSE_FILE}" <<COMPOSE
services:
  nginx:
    image: nginx:1.27-alpine
    container_name: ava-nginx
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "\${NGINX_HTTP_PORT:-80}:80"
      - "\${NGINX_HTTPS_PORT:-443}:443"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./certs:/etc/nginx/certs:ro
      - nginx_cache:/var/cache/nginx
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 1G

  x-ui:
    image: ${XUI_IMAGE}
    container_name: ${XUI_CONTAINER}
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "${panel_port}:2053"
      - "2096:2096"
    volumes:
      - xui_data:/etc/x-ui
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 1G

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: ava-node-exporter
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "\${NODE_EXPORTER_PORT:-9100}:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 256M

volumes:
  nginx_cache:
  xui_data:
COMPOSE
}

compose_up() {
  step "Starting Docker services..."
  cd "${INSTALL_DIR}"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull -q 2>/dev/null || docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d
  success "Docker services started"
}

configure_xui_credentials() {
  local user="$1"
  local pass="$2"
  local retries=30
  step "Waiting for 3x-ui container..."
  while (( retries > 0 )); do
    if docker ps --format '{{.Names}}' | grep -q "^${XUI_CONTAINER}$"; then
      if docker exec "${XUI_CONTAINER}" /app/x-ui setting -username "${user}" -password "${pass}" 2>/dev/null; then
        success "3x-ui credentials applied"
        return 0
      fi
    fi
    sleep 2
    ((retries--))
  done
  warn "Could not auto-apply 3x-ui credentials; set manually in panel"
}

install_rathole_binary() {
  local arch="$1"
  if [[ -x "${RATHOLE_INSTALL}" ]]; then
    success "Rathole already installed"
    return 0
  fi
  step "Installing Rathole ${RATHOLE_VERSION} (${arch})..."
  local url="https://github.com/rathole-org/rathole/releases/download/v${RATHOLE_VERSION}/rathole-${arch}-unknown-linux-gnu.zip"
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "${url}" -o "${tmp}/rathole.zip"
  apt-get install -y -qq unzip >/dev/null 2>&1 || true
  unzip -qo "${tmp}/rathole.zip" -d "${tmp}"
  install -m 755 "${tmp}/rathole" "${RATHOLE_INSTALL}"
  rm -rf "${tmp}"
  success "Rathole installed to ${RATHOLE_INSTALL}"
}

write_rathole_server_config() {
  local tunnel_port="$1"
  local service_port="$2"
  local token="$3"
  cat > "${INSTALL_DIR}/rathole-server.toml" <<EOF
[server]
bind_addr = "0.0.0.0:${tunnel_port}"
default_token = "${token}"
heartbeat_interval = 30

[server.services.proxy]
bind_addr = "0.0.0.0:${service_port}"
EOF
}

write_rathole_client_config() {
  local iran_ip="$1"
  local tunnel_port="$2"
  local token="$3"
  local local_port="$4"
  cat > "${INSTALL_DIR}/rathole-client.toml" <<EOF
[client]
remote_addr = "${iran_ip}:${tunnel_port}"
default_token = "${token}"
heartbeat_interval = 30
retry_interval = 5

[client.services.proxy]
local_addr = "127.0.0.1:${local_port}"
EOF
}

install_rathole_server_service() {
  cat > /etc/systemd/system/rathole-server.service <<EOF
[Unit]
Description=Rathole Server (AVA CDN Relay)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${RATHOLE_INSTALL} --server ${INSTALL_DIR}/rathole-server.toml
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${INSTALL_DIR} /var/log
StandardOutput=append:/var/log/rathole-server.log
StandardError=append:/var/log/rathole-server.log

[Install]
WantedBy=multi-user.target
EOF
  touch /var/log/rathole-server.log
  systemctl daemon-reload
  systemctl enable --now rathole-server.service
  success "Rathole server service enabled"
}

install_rathole_client_service() {
  cat > /etc/systemd/system/rathole-client.service <<EOF
[Unit]
Description=Rathole Client (AVA CDN Kharej)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${RATHOLE_INSTALL} --client ${INSTALL_DIR}/rathole-client.toml
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${INSTALL_DIR} /var/log
StandardOutput=append:/var/log/rathole-client.log
StandardError=append:/var/log/rathole-client.log

[Install]
WantedBy=multi-user.target
EOF
  touch /var/log/rathole-client.log
  systemctl daemon-reload
  systemctl enable --now rathole-client.service
  success "Rathole client service enabled"
}

setup_iran_iptables() {
  local ports_csv="$1"
  local ssh_port
  ssh_port="$(detect_ssh_port)"

  step "Configuring iptables relay..."
  sysctl -w net.ipv4.ip_forward=1
  grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null || \
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

  iptables -t nat -N cdn-tunnel-pre 2>/dev/null || iptables -t nat -F cdn-tunnel-pre
  iptables -t nat -N cdn-tunnel-post 2>/dev/null || iptables -t nat -F cdn-tunnel-post

  iptables -t nat -F cdn-tunnel-pre
  iptables -t nat -F cdn-tunnel-post

  IFS=',' read -ra PORTS <<< "${ports_csv}"
  for port in "${PORTS[@]}"; do
    port="$(echo "${port}" | tr -d ' ')"
    [[ -z "${port}" ]] && continue
    read -rp "Destination IP for port ${port}: " dest_ip
    iptables -t nat -A cdn-tunnel-pre -p tcp --dport "${port}" -j DNAT --to-destination "${dest_ip}:${port}"
    iptables -t nat -A cdn-tunnel-pre -p udp --dport "${port}" -j DNAT --to-destination "${dest_ip}:${port}"
    iptables -t nat -A cdn-tunnel-post -j MASQUERADE
    success "DNAT port ${port} → ${dest_ip}:${port}"
  done

  iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > "${INSTALL_DIR}/iptables.rules"

  cat > /etc/systemd/system/ava-iptables-restore.service <<'EOF'
[Unit]
Description=Restore AVA CDN iptables rules
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if [ -f /etc/iptables/rules.v4 ]; then iptables-restore < /etc/iptables/rules.v4; elif [ -f /opt/ava-cdn/iptables.rules ]; then iptables-restore < /opt/ava-cdn/iptables.rules; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable ava-iptables-restore.service

  local ufw_ports=("${PORTS[@]}")
  configure_ufw "${ssh_port}" "${ufw_ports[@]}"
  save_env_var "AVA_ROLE" "iran"
  save_env_var "AVA_MODE" "iptables-relay"
  save_env_var "RELAY_PORTS" "${ports_csv}"
  success "Iran iptables relay configured"
}

print_summary_box() {
  local title="$1"
  shift
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  printf "${BOLD}${GREEN}║ %-60s ║${NC}\n" "${title}"
  echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
  while [[ $# -gt 0 ]]; do
    printf "${BOLD}${GREEN}║${NC} %-60s ${BOLD}${GREEN}║${NC}\n" "$1"
    shift
  done
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MODE 1: Kharej (Germany) — CDN Origin (RECOMMENDED)
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_kharej_cdn_origin() {
  require_root
  ensure_dirs
  write_env_header
  load_env

  local ssh_port public_ip domain
  ssh_port="$(detect_ssh_port)"
  public_ip="$(detect_public_ip)"
  [[ -z "${public_ip}" ]] && public_ip="49.13.6.108"

  read -rp "Your domain (e.g. cdn.example.com) [optional]: " domain
  read -rp "Origin upstream [127.0.0.1:8080]: " upstream_in
  local upstream="${upstream_in:-127.0.0.1:8080}"

  step "Setting up Kharej CDN Origin (separate from tunnel)..."
  install_docker

  save_env_var "AVA_ROLE" "kharej"
  save_env_var "AVA_MODE" "cdn-origin"
  save_env_var "AVA_PUBLIC_IP" "${public_ip}"
  save_env_var "AVA_DOMAIN" "${domain:-}"
  save_env_var "NGINX_HTTP_PORT" "80"
  save_env_var "NGINX_HTTPS_PORT" "443"
  save_env_var "ORIGIN_UPSTREAM" "${upstream}"
  save_env_var "NODE_EXPORTER_PORT" "9100"

  ORIGIN_UPSTREAM="${upstream}"
  write_nginx_config "${domain:-_}"
  write_self_signed_certs
  write_docker_compose_cdn
  configure_ufw "${ssh_port}" "80" "443" "9100"
  compose_up

  print_summary_box "KHAREJ CDN ORIGIN — READY" \
    "Public IP:    ${public_ip}" \
    "HTTP:         http://${public_ip}" \
    "HTTPS:        https://${public_ip} (origin cert)" \
    "Upstream:     ${upstream}" \
    "Config:       ${ENV_FILE}" \
    "Next:         Point Cloudflare DNS → ${public_ip}" \
    "Docs:         docs/cloudflare-setup.md" \
    "Tunnel:       NOT used in CDN path (separate)"

  success "Kharej CDN Origin deployment complete"
}

setup_kharej_with_panel() {
  require_root
  ensure_dirs
  write_env_header

  local ssh_port public_ip panel_port admin_user admin_pass
  ssh_port="$(detect_ssh_port)"
  public_ip="$(detect_public_ip)"
  panel_port="$(rand_port)"
  admin_user="admin_$(rand_alnum 6)"
  admin_pass="$(rand_alnum 16)"

  install_docker

  save_env_var "AVA_ROLE" "kharej"
  save_env_var "AVA_MODE" "proxy-panel"
  save_env_var "AVA_PUBLIC_IP" "${public_ip}"
  save_env_var "XUI_PANEL_PORT" "${panel_port}"
  save_env_var "XUI_ADMIN_USER" "${admin_user}"
  save_env_var "XUI_ADMIN_PASS" "${admin_pass}"
  save_env_var "NGINX_HTTP_PORT" "80"
  save_env_var "NGINX_HTTPS_PORT" "443"
  save_env_var "ORIGIN_UPSTREAM" "127.0.0.1:2096"
  save_env_var "NODE_EXPORTER_PORT" "9100"

  ORIGIN_UPSTREAM="127.0.0.1:2096"
  write_nginx_config "_"
  write_self_signed_certs
  write_docker_compose_with_xui "${panel_port}"
  configure_ufw "${ssh_port}" "80" "443" "${panel_port}" "2096" "9100"
  compose_up
  configure_xui_credentials "${admin_user}" "${admin_pass}"

  print_summary_box "KHAREJ PROXY PANEL — READY" \
    "Panel URL:    http://${public_ip}:${panel_port}" \
    "Username:     ${admin_user}" \
    "Password:     ${admin_pass}" \
    "Config:       ${ENV_FILE}" \
    "Note:         Use Cloudflare for CDN mode (see docs/)"

  success "Kharej proxy panel deployment complete"
}

setup_kharej_rathole_client() {
  require_root
  ensure_dirs
  write_env_header
  load_env

  local arch iran_ip tunnel_port token local_port ssh_port
  arch="$(detect_arch)"
  ssh_port="$(detect_ssh_port)"
  tunnel_port="${RATHOLE_TUNNEL_PORT:-2096}"
  local_port="2096"

  read -rp "Iran server IP: " iran_ip
  read -rp "Rathole token [auto-generate]: " token_in
  token="${token_in:-$(rand_alnum 32)}"

  install_rathole_binary "${arch}"
  write_rathole_client_config "${iran_ip}" "${tunnel_port}" "${token}" "${local_port}"
  install_rathole_client_service

  save_env_var "AVA_ROLE" "kharej"
  save_env_var "AVA_MODE" "rathole-client"
  save_env_var "RATHOLE_TOKEN" "${token}"
  save_env_var "RATHOLE_IRAN_IP" "${iran_ip}"
  save_env_var "RATHOLE_TUNNEL_PORT" "${tunnel_port}"

  configure_ufw "${ssh_port}"

  print_summary_box "KHAREJ RATHOLE CLIENT — READY" \
    "Connects to:  ${iran_ip}:${tunnel_port}" \
    "Token:        ${token}" \
    "Local fwd:    127.0.0.1:${local_port}" \
    "Config:       ${INSTALL_DIR}/rathole-client.toml" \
    "Use same token on Iran Rathole server"

  success "Kharej Rathole client configured"
}

setup_kharej_menu() {
  echo ""
  echo -e "${BOLD}Kharej (Germany) Setup${NC}"
  echo "  a) CDN Origin — RECOMMENDED (separate from tunnel)"
  echo "  b) Proxy Panel (3x-ui + Nginx)"
  echo "  c) Rathole Client only (tunnel to Iran)"
  echo "  0) Back"
  echo ""
  read -rp "Choice [a]: " choice
  choice="${choice:-a}"
  case "${choice}" in
    a|A) setup_kharej_cdn_origin ;;
    b|B) setup_kharej_with_panel ;;
    c|C) setup_kharej_rathole_client ;;
    0) return 0 ;;
    *) error "Invalid choice" ;;
  esac
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MODE 2: Iran Relay
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_iran_rathole_server() {
  require_root
  ensure_dirs
  write_env_header

  local arch tunnel_port service_port token ssh_port
  arch="$(detect_arch)"
  ssh_port="$(detect_ssh_port)"
  tunnel_port="${RATHOLE_TUNNEL_PORT:-2096}"
  service_port="${RATHOLE_SERVICE_PORT:-443}"

  read -rp "Rathole token (must match Kharej client) [auto]: " token_in
  token="${token_in:-$(rand_alnum 32)}"

  install_rathole_binary "${arch}"
  write_rathole_server_config "${tunnel_port}" "${service_port}" "${token}"
  install_rathole_server_service

  save_env_var "AVA_ROLE" "iran"
  save_env_var "AVA_MODE" "rathole-server"
  save_env_var "RATHOLE_TOKEN" "${token}"
  save_env_var "RATHOLE_TUNNEL_PORT" "${tunnel_port}"
  save_env_var "RATHOLE_SERVICE_PORT" "${service_port}"

  configure_ufw "${ssh_port}" "${tunnel_port}" "${service_port}"

  print_summary_box "IRAN RATHOLE SERVER — READY" \
    "Control port: ${tunnel_port} (Kharej connects here)" \
    "Service port: ${service_port} (users connect here)" \
    "Token:        ${token}" \
    "Log:          /var/log/rathole-server.log"

  success "Iran Rathole server configured"
}

setup_iran_menu() {
  echo ""
  echo -e "${BOLD}Iran Relay Setup${NC}"
  echo "  a) iptables (simple port forwarding)"
  echo "  b) Rathole (encrypted reverse tunnel)"
  echo "  0) Back"
  echo ""
  read -rp "Choice [b]: " choice
  choice="${choice:-b}"
  case "${choice}" in
    a|A)
      read -rp "Ports to forward (comma-separated, e.g. 443,8443): " ports
      setup_iran_iptables "${ports:-443}"
      ;;
    b|B) setup_iran_rathole_server ;;
    0) return 0 ;;
    *) error "Invalid choice" ;;
  esac
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Status / Update / Uninstall
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
check_status() {
  echo ""
  echo -e "${BOLD}═══ System Status ═══${NC}"
  echo ""
  echo -e "${BOLD}Resources:${NC}"
  echo "  CPU:  $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')% used"
  echo "  RAM:  $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
  echo "  Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
  echo ""
  echo -e "${BOLD}Docker:${NC}"
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || warn "Docker not available"
  echo ""
  echo -e "${BOLD}Rathole:${NC}"
  systemctl is-active rathole-server.service 2>/dev/null && success "rathole-server: active" || info "rathole-server: not running"
  systemctl is-active rathole-client.service 2>/dev/null && success "rathole-client: active" || info "rathole-client: not running"
  echo ""
  echo -e "${BOLD}iptables (cdn-tunnel-pre):${NC}"
  iptables -t nat -L cdn-tunnel-pre -n -v 2>/dev/null || info "No iptables relay rules"
  echo ""
  echo -e "${BOLD}Listening ports:${NC}"
  ss -tlnp | head -20
  echo ""
  if [[ -f "${ENV_FILE}" ]]; then
    echo -e "${BOLD}Config:${NC} ${ENV_FILE}"
  fi
}

update_services() {
  require_root
  step "Updating services..."
  if [[ -f "${COMPOSE_FILE}" ]]; then
    cd "${INSTALL_DIR}"
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d
    success "Docker services updated"
  fi
  if [[ -x "${RATHOLE_INSTALL}" ]]; then
    local arch
    arch="$(detect_arch)"
    install_rathole_binary "${arch}"
    systemctl restart rathole-server.service 2>/dev/null || true
    systemctl restart rathole-client.service 2>/dev/null || true
    success "Rathole binary updated"
  fi
  success "Update complete"
}

uninstall_all() {
  require_root
  read -rp "This will remove ALL AVA CDN components. Continue? [y/N]: " confirm
  [[ "${confirm}" =~ ^[Yy]$ ]] || { info "Cancelled"; return 0; }

  step "Removing services..."
  systemctl stop rathole-server.service rathole-client.service ava-iptables-restore.service 2>/dev/null || true
  systemctl disable rathole-server.service rathole-client.service ava-iptables-restore.service 2>/dev/null || true
  rm -f /etc/systemd/system/rathole-server.service /etc/systemd/system/rathole-client.service
  rm -f /etc/systemd/system/ava-iptables-restore.service
  systemctl daemon-reload

  if [[ -f "${COMPOSE_FILE}" ]]; then
    cd "${INSTALL_DIR}"
    docker compose -f "${COMPOSE_FILE}" down -v 2>/dev/null || true
  fi
  docker rm -f "${NGINX_CONTAINER}" "${XUI_CONTAINER}" "${NODE_EXPORTER_CONTAINER}" 2>/dev/null || true

  iptables -t nat -F cdn-tunnel-pre 2>/dev/null || true
  iptables -t nat -F cdn-tunnel-post 2>/dev/null || true
  iptables -t nat -X cdn-tunnel-pre 2>/dev/null || true
  iptables -t nat -X cdn-tunnel-post 2>/dev/null || true

  rm -f "${RATHOLE_INSTALL}"
  rm -rf "${INSTALL_DIR}"

  success "Uninstall complete"
}

main_menu() {
  while true; do
    show_banner
    echo -e "${BOLD}Main Menu${NC}"
    echo "  1) 🌍 Setup Kharej (Germany) Server"
    echo "  2) 🏠 Setup Iran Relay Server"
    echo "  3) 📊 Check Status"
    echo "  4) 🔄 Update Services"
    echo "  5) 🗑  Uninstall"
    echo "  0) Exit"
    echo ""
    read -rp "Choice: " choice
    case "${choice}" in
      1) setup_kharej_menu ;;
      2) setup_iran_menu ;;
      3) check_status ;;
      4) update_services ;;
      5) uninstall_all ;;
      0) info "Goodbye"; exit 0 ;;
      *) error "Invalid choice" ;;
    esac
    echo ""
    read -rp "Press Enter to continue..."
  done
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entry — support non-interactive quick deploy for Germany CDN origin
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [[ "${1:-}" == "--kharej-cdn" ]]; then
  require_root
  ensure_dirs
  write_env_header
  install_docker
  public_ip="$(detect_public_ip)"
  ssh_port="$(detect_ssh_port)"
  save_env_var "AVA_ROLE" "kharej"
  save_env_var "AVA_MODE" "cdn-origin"
  save_env_var "AVA_PUBLIC_IP" "${public_ip:-49.13.6.108}"
  save_env_var "NGINX_HTTP_PORT" "80"
  save_env_var "NGINX_HTTPS_PORT" "443"
  save_env_var "ORIGIN_UPSTREAM" "127.0.0.1:8080"
  save_env_var "NODE_EXPORTER_PORT" "9100"
  ORIGIN_UPSTREAM="127.0.0.1:8080"
  write_nginx_config "_"
  write_self_signed_certs
  write_docker_compose_cdn
  configure_ufw "${ssh_port}" "80" "443" "9100"
  compose_up
  print_summary_box "KHAREJ CDN ORIGIN — QUICK DEPLOY DONE" \
    "IP: ${public_ip:-49.13.6.108}" \
    "See docs/cloudflare-setup.md for CDN"
  exit 0
fi

main_menu
