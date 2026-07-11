# AVA CDN

Production-ready CDN origin infrastructure for Germany (Kharej) server, **fully separate** from optional Iran relay tunnel.

## Architecture (Recommended)

```text
Users → Cloudflare CDN → Germany Origin (Nginx + Cache) → Your App
                              ↑
                    Tunnel NOT in this path

Iran ↔ Germany tunnel = admin/relay only (optional, separate)
```

## Quick deploy on Germany server

SSH into your Germany VPS, then run:

```bash
# As root on Germany server (49.13.6.108)
curl -fsSL https://raw.githubusercontent.com/sivanpabraj/AVA-CDN/main/setup.sh -o setup.sh
# OR clone the repo:
git clone https://github.com/sivanpabraj/AVA-CDN.git
cd AVA-CDN

# Interactive menu (recommended)
sudo bash setup.sh

# Non-interactive CDN origin only
sudo bash setup.sh --kharej-cdn
```

### Menu options

| Option | Description |
|--------|-------------|
| **1a — CDN Origin** | **Best method.** Nginx reverse proxy + cache, Node Exporter, UFW |
| 1b — Proxy Panel | 3x-ui + Nginx (for VLESS/gRPC behind Cloudflare) |
| 1c — Rathole Client | Tunnel client to Iran (optional, separate) |
| 2a — Iran iptables | Simple port forwarding on Iran relay |
| 2b — Iran Rathole | Encrypted reverse tunnel (Iran = server) |
| 3 — Status | Containers, Rathole, iptables, resources |
| 4 — Update | Pull images, update Rathole, restart |
| 5 — Uninstall | Clean removal |

## After Germany setup

1. Point your domain DNS to Cloudflare → Germany IP
2. Install Cloudflare Origin Certificate on server
3. See [docs/cloudflare-setup.md](docs/cloudflare-setup.md)

## Project structure

```
AVA-CDN/
├── setup.sh                  # Main installer (single file)
├── setup-avashop.sh          # One-shot deploy for avashop.online
├── sites/avashop.online/     # Domain-specific nginx + compose
├── .env.example              # Environment template
├── docs/
│   ├── cloudflare-setup.md   # CDN DNS/SSL/cache guide
│   ├── client-configs.md     # Xray/Sing-box samples
│   └── troubleshooting.md    # Common issues
└── README.md
```

## Security notes

- All secrets generated at install time → `/opt/ava-cdn/.env` (chmod 600)
- UFW default deny incoming
- Docker: `no-new-privileges`, resource limits, log rotation
- **Never commit** `.env` or server passwords to git
- **Rotate** server password if it was shared in chat

## avashop.online (CDN separate from tunnel)

Pre-built site profile for **avashop.online** on Germany server `49.13.6.108`:

| Hostname | Cloudflare | Role |
|----------|------------|------|
| `avashop.online`, `www`, `de` | **Proxied** (orange) | Shop CDN |
| `tunnel.avashop.online` | **DNS only** (grey) | Tunnel — separate |

```bash
sudo bash setup-avashop.sh
```

Full guide: [docs/avashop.online-setup.md](docs/avashop.online-setup.md)

## Germany server reference

| Item | Value |
|------|-------|
| IP | `49.13.6.108` |
| Domain | `avashop.online` |
| Role | CDN Origin (Kharej) |
| Install path | `/opt/ava-cdn/avashop.online/` |
| Logs | `/var/log/ava-cdn-avashop-setup.log` |

## Documentation

- [avashop.online setup (CDN vs tunnel)](docs/avashop.online-setup.md)
- [Cloudflare CDN setup](docs/cloudflare-setup.md)
- [Client configs (VLESS-gRPC / Sing-box)](docs/client-configs.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

License to be determined.
