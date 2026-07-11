# اینباند مخصوص داخل ایران (تانل Rathole)

## مسیر (سریع — بدون Cloudflare)

```text
شما (ایران) → سرور ایران (80.249.112.56) → Rathole (~80ms) → آلمان → اینترنت
```

**از `de.avashop.online` استفاده نکنید** — آن مسیر CDN برای خارج از ایران است.

---

## لینک VLESS فعال

```
vless://19a9bb1b-05e9-45c1-a0eb-1c5bc4d19d10@80.249.112.56:2088?type=tcp&security=none#avashop-iran
```

| پارامتر | مقدار |
|---------|-------|
| Protocol | VLESS |
| Network | TCP |
| Address | `80.249.112.56` |
| Port | `2088` (یا `444` از HAProxy) |
| UUID | `19a9bb1b-05e9-45c1-a0eb-1c5bc4d19d10` |
| Security | none |
| Fragment | **خاموش** |

---

## کاربران SS موجود (تغییر نکرده)

| پارامتر | مقدار |
|---------|-------|
| Address | `80.249.112.56` |
| Port | `1080` |
| Method | chacha20-ietf-poly1305 |

---

## v2rayN

1. Import لینک VLESS
2. **Fragment را خاموش کنید**
3. TLS/Security = none
4. تست واقعی: باز کردن `https://www.google.com`

---

## مقایسه سرعت

| مسیر | تأخیر |
|------|-------|
| `de.avashop.online` (CDN gRPC) | ~۵۰۰ms+ |
| `80.249.112.56:2088` (ایران رله) | ~۴۲۰ms |
| `80.249.112.56:1080` (SS کاربران) | ~۴۰۰ms |

---

## نصب / تعمیر

```bash
# آلمان
sudo bash setup-iran-inbound.sh

# ایران (بدون قطع کاربران)
sudo bash setup-iran-iran-side.sh
```

جزئیات معماری: [tunnel-architecture.md](tunnel-architecture.md)

---

## ⚠️ مهم — قطع نشدن کاربران

روی سرور ایران **هرگز** این را نزنید:
```bash
systemctl restart rathole   # باعث قطع لحظه‌ای همه کاربران می‌شود
```

از `rathole-guard.service` استفاده کنید (در `setup-iran-iran-side.sh`).
