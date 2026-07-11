# avashop.online — CDN جدا از Tunnel

راه‌اندازی CDN برای فروشگاه **جدا** از تانل `tunnel.avashop.online`.

## معماری

```text
فروشگاه (کاربران):
  avashop.online / www / de  →  Cloudflare (Proxied)  →  49.13.6.108  →  Nginx CDN

تانل (جدا):
  tunnel.avashop.online  →  DNS only (خاکستری)  →  49.13.6.108  →  Xray/Rathole
```

## تنظیم DNS در Cloudflare (مهم)

| Record | Type | Content | Proxy | نقش |
|--------|------|---------|-------|-----|
| `avashop.online` | A | `49.13.6.108` | **Proxied** (نارنجی) | فروشگاه اصلی |
| `www` | A | `49.13.6.108` | **Proxied** | فروشگاه |
| `de` | A | `49.13.6.108` | **Proxied** | CDN آلمان |
| `tunnel` | A | `49.13.6.108` | **DNS only** (خاکستری) | تانل — جدا از CDN |
| `*` | A | `49.13.6.108` | DNS only | اختیاری |
| `a2` | AAAA | `2a01:4f8:c013:ee8e::2` | DNS only | IPv6 |

### تغییرات لازم نسبت به وضعیت فعلی

1. **`tunnel.avashop.online`** → از Proxied به **DNS only** تغییر دهید (جدا شدن از CDN)
2. **`avashop.online`** و **`www`** → به **Proxied** تغییر دهید (فعال‌سازی CDN)
3. **`de.avashop.online`** → Proxied بماند (CDN آلمان)

## SSL/TLS در Cloudflare

1. **SSL/TLS → Overview** → حالت **Full (strict)**
2. **SSL/TLS → Origin Server** → ساخت Origin Certificate برای:
   - `avashop.online`
   - `*.avashop.online`
3. فایل‌ها را روی سرور قرار دهید:

```bash
/opt/ava-cdn/avashop.online/certs/origin.pem
/opt/ava-cdn/avashop.online/certs/origin-key.pem
chmod 600 /opt/ava-cdn/avashop.online/certs/*
```

## Cache Rules (Cloudflare)

| Rule | Match | Action |
|------|-------|--------|
| Static | URI contains `.css`, `.js`, `.png`, `.jpg`, `.woff2` | Cache Everything, TTL 1 month |
| API | URI starts with `/api/` | Bypass cache |
| Tunnel | Host equals `tunnel.avashop.online` | Bypass cache (اگر اشتباهاً Proxied شد) |

## Network

- **gRPC** را فقط اگر برای `tunnel` یا پنل لازم دارید فعال کنید
- برای فروشگاه CDN معمولاً gRPC لازم نیست

## نصب روی سرور آلمان

```bash
ssh root@49.13.6.108
git clone https://github.com/sivanpabraj/AVA-CDN.git
cd AVA-CDN
sudo bash setup-avashop.sh
```

## تأیید

```bash
# CDN path
curl -I https://de.avashop.online
# باید header های cloudflare و X-AVA-Layer: cdn-origin ببینید

# Tunnel path (DNS only)
curl -I https://tunnel.avashop.online
# باید X-AVA-Layer: tunnel-direct ببینید (بدون cf-cache-status)
```

## عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| tunnel از CDN رد می‌شود | Proxy را خاموش کنید (DNS only) |
| 522 روی de/www | `docker ps` روی سرور، پورت 80/443 باز باشد |
| SSL 525 | Origin Certificate نصب کنید، Full strict |
| فروشگاه کند است | Cache rules برای استاتیک فعال کنید |
