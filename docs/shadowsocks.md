# Shadowsocks — مسیرهای فعال

## خلاصه تست (۲۰۲۶-۰۷-۱۱)

| مسیر | پورت | وضعیت | تأخیر |
|------|------|--------|-------|
| HAProxy مشترک | `1080` / `1081` | ✅ OK | ~450ms |
| Bridge بات | `2053` / `2055` | ✅ OK | ~470ms |
| بات Germany-Rathole | `46103` | ✅ OK (بعد از fix) | ~430ms |
| بات Germany-Backhaul | `46101` | ✅ OK | SOCKS→gost |
| آلمان مستقیم | `8388` | ✅ OK | ~35ms |

---

## مسیر اصلی کاربران (مشترک)

```text
کلاینت SS → ایران 80.249.112.56:1080
         → HAProxy → Rathole 127.0.0.1:19454
         → آلمان 127.0.0.1:8388 (SS)
         → اینترنت
```

| پارامتر | مقدار |
|---------|-------|
| Server | `80.249.112.56` |
| Port | `1080` یا `1081` یا `2053` یا `2055` |
| Method | `chacha20-ietf-poly1305` |
| Password | `m0w11TUXF4Sh` |

---

## مسیر بات (پورت 46103 — per-user password)

```text
کلاینت SS → ایران :46103 (رمز اختصاصی هر کاربر)
         → x-ui inbound-46103
         → outbound out-rathole-de (SS به 19454)
         → Rathole → آلمان :8388
```

هر کاربر رمز خودش را از بات می‌گیرد — **نه** `m0w11TUXF4Sh`.

---

## مسیر بات Backhaul (پورت 46101)

```text
کلاینت SS → ایران :46101
         → outbound out-backhaul-de (SOCKS به 19444)
         → gost → آلمان 49.13.6.108:29444
```

این مسیر **SOCKS** است و درست تنظیم شده (برخلاف Rathole).

---

## آلمان — SS Origin

| پارامتر | مقدار |
|---------|-------|
| Port | `8388` (فقط از Rathole — localhost) |
| Method | `chacha20-ietf-poly1305` |
| Password | `m0w11TUXF4Sh` |

---

## مشکل رفع‌شده: پورت 46103

**علت:** outbound `out-rathole-de` به‌اشتباه `socks` به پورت `19454` بود.  
پورت 19454 تانل خام Rathole است (SS مستقیم)، نه پروکسی SOCKS.

**Fix:** تغییر به `shadowsocks` با method/password آلمان + `x-ui restart-xray`

---

## ⚠️ قطع نشدن کاربران

| مجاز | ممنوع |
|------|-------|
| `x-ui restart-xray` (~۱ ثانیه) | `systemctl restart rathole` |
| `systemctl reload haproxy` | `x-ui restart` (کل پنل) |

---

## تست سریع

```bash
# از هر سرور با xray:
# shared path
ss://chacha20-ietf-poly1305:m0w11TUXF4Sh@80.249.112.56:1080

# bot path (رمز کاربر خودت)
ss://chacha20-ietf-poly1305:USER_PASSWORD@80.249.112.56:46103
```
