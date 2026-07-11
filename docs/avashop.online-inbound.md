# avashop.online — Inbound طراحی‌شده

## اینباند: VLESS-gRPC-TLS (مسیر CDN)

| پارامتر | مقدار |
|---------|-------|
| **Protocol** | VLESS |
| **Network** | gRPC |
| **Address** | `de.avashop.online` |
| **Port** | `443` |
| **Service Name** | `grpc-avashop` |
| **Security** | TLS |
| **SNI** | `de.avashop.online` |
| **CDN** | Cloudflare (Proxied) |
| **Path** | `/grpc-avashop` |

### جریان ترافیک

```text
کلاینت → Cloudflare (Proxied) → de.avashop.online:443
       → Nginx (/grpc-avashop) → Xray:2096 (VLESS-gRPC)
       → اینترنت
```

**تانل (`tunnel.avashop.online`) در این مسیر نیست.**

---

## تنظیمات Cloudflare (الزامی)

1. **Network → gRPC** → فعال
2. **`de.avashop.online`** → Proxied (نارنجی)
3. **`tunnel.avashop.online`** → DNS only (خاکستری)
4. **SSL/TLS** → Full (strict)

---

## کانفیگ کلاینت (v2rayN / Sing-box)

فایل روی سرور بعد از نصب:

```bash
cat /opt/ava-cdn/avashop.online/client-vless-grpc.json
cat /opt/ava-cdn/avashop.online/inbound.json
```

### Fragment (v2rayN) — برای DPI

| Setting | Value |
|---------|-------|
| Packets | `tlshello` |
| Length | `100-200` |
| Interval | `10-20` |

### Sing-box outbound نمونه

```json
{
  "type": "vless",
  "tag": "avashop-cdn",
  "server": "de.avashop.online",
  "server_port": 443,
  "uuid": "YOUR-UUID-FROM-inbound.json",
  "tls": {
    "enabled": true,
    "server_name": "de.avashop.online",
    "alpn": ["h2"],
    "utls": { "enabled": true, "fingerprint": "chrome" }
  },
  "transport": {
    "type": "grpc",
    "service_name": "grpc-avashop"
  }
}
```

---

## نصب روی سرور

```bash
sudo bash setup-avashop.sh --with-inbound
```

---

## عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| اتصال برقرار نمی‌شود | gRPC در Cloudflare فعال باشد |
| TLS error | SSL mode = Full strict + Origin cert |
| UUID invalid | `cat /opt/ava-cdn/avashop.online/inbound.json` |
| Xray down | `docker logs ava-avashop-xray` |
