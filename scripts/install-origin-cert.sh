#!/usr/bin/env bash
# Install Cloudflare Origin Certificate on avashop.online server
set -euo pipefail

CERT_DIR="/opt/ava-cdn/avashop.online/certs"

echo "Cloudflare Origin Certificate Installer"
echo "========================================"
echo ""
echo "Paste your Origin Certificate (PEM), then press Ctrl+D:"
cat > "${CERT_DIR}/origin.pem"

echo ""
echo "Paste your Private Key (PEM), then press Ctrl+D:"
cat > "${CERT_DIR}/origin-key.pem"

chmod 600 "${CERT_DIR}/origin-key.pem"
chmod 644 "${CERT_DIR}/origin.pem"

cd /opt/ava-cdn/avashop.online
docker compose restart nginx

echo ""
echo "Certificate installed. Testing..."
openssl x509 -in "${CERT_DIR}/origin.pem" -noout -subject -issuer -dates
curl -sI -k --resolve de.avashop.online:443:127.0.0.1 https://de.avashop.online | head -5
echo ""
echo "Done. Cloudflare 526 error should be fixed within 1-2 minutes."
