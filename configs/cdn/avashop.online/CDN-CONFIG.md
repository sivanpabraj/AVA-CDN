# avashop.online — CDN Config Package

> فقط CDN پشت Cloudflare — بدون سرور ایران  
> Origin: آلمان `49.13.6.108`

---

## ۱) لینک اتصال (Import کنید)

```
vless://fbf5af83-4473-4d46-a682-f82b98badea8@de.avashop.online:443?encryption=none&security=tls&sni=de.avashop.online&fp=chrome&alpn=h2&type=grpc&serviceName=grpc-avashop#avashop-cdn
```

---

## ۲) پارامترهای اینباند

| پارامتر | مقدار |
|---------|-------|
| Protocol | VLESS |
| Address | `de.avashop.online` |
| Port | `443` |
| UUID | `fbf5af83-4473-4d46-a682-f82b98badea8` |
| Network | gRPC |
| Service Name | `grpc-avashop` |
| TLS | فعال |
| SNI | `de.avashop.online` |
| ALPN | `h2` |
| Fingerprint | `chrome` |
| Flow | خالی |

---

## ۳) تنظیمات Cloudflare (شما انجام می‌دهید)

### DNS

| Record | Type | Content | Proxy |
|--------|------|---------|-------|
| `de` | A | `49.13.6.108` | **Proxied** (نارنجی) |
| `avashop.online` | A | `49.13.6.108` | **Proxied** |
| `www` | A | `49.13.6.108` | **Proxied** |
| `cn` | A | `49.13.6.108` | **Proxied** (اختیاری) |

### SSL/TLS

- حالت: **Full (strict)**
- Origin Certificate برای `*.avashop.online` بسازید
- فایل‌ها را در `certs/origin.pem` و `certs/origin-key.pem` روی سرور بگذارید

### Network

- **gRPC** → **فعال** (الزامی)

### Cache (اختیاری)

- برای مسیر `/grpc-avashop` → **Bypass cache**

---

## ۴) نصب Origin روی سرور آلمان

```bash
# روی 49.13.6.108
mkdir -p /opt/ava-cdn-cdn/avashop.online/certs
cd /opt/ava-cdn-cdn/avashop.online

# کپی فایل‌های این پوشه:
#   docker-compose.yml
#   nginx-origin.conf
#   xray-config.json
#   certs/origin.pem + certs/origin-key.pem

docker compose up -d
curl http://127.0.0.1/health
```

---

## ۵) v2rayN

1. لینک بالا را Import کنید
2. تنظیمات دستی اگر لازم شد:

| فیلد | مقدار |
|------|-------|
| Address | `de.avashop.online` |
| Port | `443` |
| UUID | `fbf5af83-4473-4d46-a682-f82b98badea8` |
| Transport | gRPC |
| Service Name | `grpc-avashop` |
| TLS | ON |
| SNI | `de.avashop.online` |
| ALPN | h2 |
| Fingerprint | chrome |

### Fragment (فقط اگر از ایران وصل نمی‌شود)

| Setting | Value |
|---------|-------|
| Packets | `tlshello` |
| Length | `100-200` |
| Interval | `10-20` |

> Fragment سرعت را کم می‌کند — فقط در صورت نیاز فعال کنید.

---

## ۶) Sing-box

فایل آماده: `client-singbox.json`

```bash
sing-box run -c client-singbox.json
```

---

## ۷) مسیر ترافیک

```text
کلاینت → Cloudflare (Proxied) → de.avashop.online:443
       → Nginx /grpc-avashop → Xray:2096 → اینترنت
```

---

## ۸) تست

```bash
# باید grpc-status بدهد (برای curl طبیعی است)
curl -I https://de.avashop.online/grpc-avashop
```

در v2rayN: **تست سرعت / Test connection**

---

## ۹) عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| وصل نمی‌شود | gRPC در Cloudflare فعال باشد |
| خطای TLS | SSL = Full strict + Origin cert |
| کند است | Fragment را خاموش کنید |
| 502/526 | Origin cert و docker روی آلمان چک شود |
| UUID error | UUID بالا را دقیق کپی کنید |

---

## فایل‌های این پکیج

```
configs/cdn/avashop.online/
├── inbound.json           # مشخصات اینباند
├── xray-config.json       # کانفیگ Xray روی origin
├── nginx-origin.conf      # Nginx پشت Cloudflare
├── docker-compose.yml     # اجرای origin
├── client-v2rayn.json     # کلاینت v2rayN
├── client-singbox.json    # کلاینت Sing-box
└── CDN-CONFIG.md          # همین فایل
```
