# avashop.online — CDN Config Package

> فقط CDN پشت Cloudflare — بدون سرور ایران  
> Origin: آلمان `49.13.6.108`

---

## ۱) لینک اتصال (Import کنید)

```
vless://fbf5af83-4473-4d46-a682-f82b98badea8@de.avashop.online:443?encryption=none&security=tls&sni=de.avashop.online&fp=chrome&alpn=h2&type=grpc&serviceName=grpc-avashop&mode=gun#avashop-cdn
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
2. **تنظیمات DNS (مهم — برای پینگ/سرعت پشت اینباند):**

| فیلد | مقدار |
|------|-------|
| Remote DNS | `https://1.1.1.1/dns-query` |
| Domestic DNS | `localhost` |
| Domain strategy | `IPIfNonMatch` |

3. **تست واقعی:**
   - «تست سرعت واقعی» یا باز کردن `https://www.google.com`
   - **پینگ ICMP از پشت VLESS معمولاً کار نمی‌کند** — این طبیعی است

4. تنظیمات دستی:

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

## ۸) تست (تأیید شده ۲۰۲۶-۰۷-۱۱)

### نتیجه تست واقعی از بیرون (از طریق Cloudflare)

| تست | نتیجه |
|-----|-------|
| TLS به `de.avashop.online:443` | ~۳۵–۵۸ ms |
| VLESS-gRPC → `google.com/generate_204` | **۲۰۴ OK** — ~۲۵۰–۵۰۰ ms |
| ترافیک در لاگ Xray سرور | از IPهای Cloudflare قبول می‌شود |

```bash
# تست TLS (پینگ سرور / دامنه)
curl -sk -o /dev/null -w "tls:%{time_appconnect}s\n" https://de.avashop.online/

# grpc با curl معمولاً 405 می‌دهد — طبیعی است و به معنی خرابی نیست
curl -I https://de.avashop.online/grpc-avashop
```

### v2rayN — تست تأخیر

1. لینک بالا را Import کنید (`mode=gun` مهم است)
2. **Ctrl+R** → **تست واقعی / Real test** (نه پینگ ICMP)
3. یا `https://www.google.com` را با پروکسی باز کنید

> **پینگ ICMP از پشت VLESS کار نمی‌کند** — حتی اگر سرور پینگ داشته باشد.  
> در v2rayN گاهی «تست تأخیر» gRPC عدد `-1` می‌دهد ولی اتصال واقعی OK است.

---

## ۹) عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| پینگ سرور خوبه ولی **پشت اینباند پینگ نمیده** | **طبیعی است** — VLESS ICMP را رد نمی‌کند. تست با باز کردن سایت یا Real delay |
| سایت باز نمی‌شود | Remote DNS = `1.1.1.1` در v2rayN |
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
