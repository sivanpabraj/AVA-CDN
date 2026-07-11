# Troubleshooting Guide

## 10 Most Common Issues

| # | Symptom | Likely Cause | Fix |
|---|---------|--------------|-----|
| 1 | Site returns 522 from Cloudflare | Origin down or firewall blocks Cloudflare | Check `docker ps`, open ports 80/443 in UFW, verify origin is running |
| 2 | SSL handshake error (525/526) | Wrong SSL mode or bad origin cert | Set Cloudflare to **Full (strict)**, reinstall origin certificate |
| 3 | 502 Bad Gateway | Nginx upstream unreachable | Check `ORIGIN_UPSTREAM` in `/opt/ava-cdn/.env`, verify backend app is listening |
| 4 | CDN not caching | Cache rules missing or `Cache-Control: no-store` | Add Cloudflare cache rules; set proper cache headers on static files |
| 5 | Rathole won't connect | Wrong token, blocked port, or reversed server/client roles | Iran must be **server**, Kharej **client**; verify token and port 2096 |
| 6 | 3x-ui panel inaccessible | Random high port blocked by UFW | Run status check; `ufw allow PORT/tcp` for panel port |
| 7 | Docker containers restart loop | Port conflict or bad config | `docker logs CONTAINER`; check `ss -tlnp` for port conflicts |
| 8 | iptables rules lost after reboot | Persistence service failed | `systemctl status ava-iptables-restore`; re-run Iran iptables setup |
| 9 | High latency on API calls | API traffic going through CDN cache | Bypass cache for `/api/*`; use grey-cloud subdomain for admin |
| 10 | `setup.sh` fails on second run | Non-idempotent state (rare) | Check `/var/log/ava-cdn-setup.log`; run uninstall then reinstall |

## Quick diagnostic commands

```bash
# On Germany (Kharej) server
sudo bash setup.sh   # choose option 3 (Status)

docker ps -a
docker compose -f /opt/ava-cdn/docker-compose.yml logs --tail=50
ufw status verbose
curl -I http://127.0.0.1
ss -tlnp

# On Iran relay server
systemctl status rathole-server
iptables -t nat -L cdn-tunnel-pre -n -v
journalctl -u rathole-server -n 50
```

## Log locations

| Component | Log path |
|-----------|----------|
| Setup script | `/var/log/ava-cdn-setup.log` |
| Rathole server | `/var/log/rathole-server.log` |
| Nginx (Docker) | `docker logs ava-nginx` |
| 3x-ui | `docker logs ava-3x-ui` |
