# اینباند مخصوص داخل ایران

## مسیر (سریع — بدون Cloudflare)

```text
شما (ایران) → سرور ایران (80.249.112.56) → Rathole (~80ms) → آلمان → اینترنت
```

**از `de.avashop.online` استفاده نکنید** — آن مسیر CDN برای خارج از ایران است.

---

## اتصال VLESS-TCP

| پارامتر | مقدار |
|---------|-------|
| Protocol | VLESS |
| Network | TCP |
| Address | `80.249.112.56` |
| Port | `2088` (یا `444` از HAProxy) |
| Security | none |
| Fragment | **خاموش** |

### لینک

بعد از نصب:

```bash
cat /opt/ava-cdn/iran-inbound/inbound.json
```

---

## v2rayN

1. Import لینک VLESS
2. **Fragment را خاموش کنید**
3. TLS/Security = none
4. تست اتصال

---

## مقایسه سرعت

| مسیر | تأخیر از ایران |
|------|----------------|
| `de.avashop.online` (CDN gRPC) | ~9 ثانیه |
| `80.249.112.56:2088` (ایران رله) | ~80ms |

---

## نصب روی سرور

```bash
# روی آلمان
sudo bash setup-iran-inbound.sh

# سپس روی ایران (از آلمان)
sshpass -p 'PASS' ssh root@80.249.112.56 'bash -s' < setup-iran-iran-side.sh
```
