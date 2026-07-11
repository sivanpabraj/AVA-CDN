# Cloudflare CDN Setup (Separate from Tunnel)

Use this guide after deploying the **CDN Origin** on your Germany (Kharej) server.

## Architecture

```text
Users → Cloudflare Edge (CDN) → Germany Origin (49.13.x.x) → Your App
```

The Iran↔Germany tunnel is **not** in this path. Use the tunnel only for admin access.

## Step 1: Add your domain to Cloudflare

1. Sign in at [https://dash.cloudflare.com](https://dash.cloudflare.com)
2. Add your domain
3. Update nameservers at your registrar to Cloudflare's NS records

## Step 2: DNS records

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `@` | `YOUR_GERMANY_IP` | Proxied (orange cloud) |
| A | `www` | `YOUR_GERMANY_IP` | Proxied |
| A | `cdn` | `YOUR_GERMANY_IP` | Proxied (optional) |

## Step 3: SSL/TLS

1. Go to **SSL/TLS → Overview**
2. Set encryption mode to **Full (strict)**
3. Go to **SSL/TLS → Origin Server**
4. Create an **Origin Certificate** (15 years)
5. Install on Germany server:

```bash
# On Germany server
mkdir -p /opt/ava-cdn/certs
# Paste origin cert to /opt/ava-cdn/certs/origin.pem
# Paste private key to /opt/ava-cdn/certs/origin-key.pem
chmod 600 /opt/ava-cdn/certs/*
docker compose -f /opt/ava-cdn/docker-compose.yml restart nginx
```

## Step 4: Enable gRPC (for VLESS-gRPC clients)

1. **Network** → enable **gRPC**
2. If using 3x-ui with gRPC inbound, ensure the path matches your Xray config

## Step 5: Caching rules

1. **Caching → Configuration** → set caching level to **Standard**
2. **Cache Rules** → create rules:

| Rule | Match | Action |
|------|-------|--------|
| Static assets | URI Path contains `.css`, `.js`, `.png`, `.jpg`, `.woff2` | Cache Everything, Edge TTL 1 month |
| API bypass | URI Path starts with `/api/` | Bypass cache |

## Step 6: Security

1. **Security → Settings** → set security level to **Medium**
2. Enable **Bot Fight Mode** if needed
3. **WAF** → enable managed rules (Pro plan) or basic rules

## Step 7: Verify

```bash
curl -I https://yourdomain.com
```

Expected headers include `cf-cache-status` and `server: cloudflare`.

## Origin-only admin (optional)

Create a DNS-only record for direct server access (no CDN):

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `origin` | `YOUR_GERMANY_IP` | DNS only (grey cloud) |

Use `origin.yourdomain.com` only for administration, not public traffic.
