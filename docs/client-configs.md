# Client Configuration Samples

## 1. Xray / v2rayN — VLESS-gRPC (CDN mode via Cloudflare)

Replace placeholders before use.

```json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "socks",
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": { "udp": true }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "YOUR_DOMAIN.com",
            "port": 443,
            "users": [
              {
                "id": "YOUR-UUID-HERE",
                "encryption": "none",
                "flow": ""
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "serverName": "YOUR_DOMAIN.com",
          "alpn": ["h2"],
          "fingerprint": "chrome"
        },
        "grpcSettings": {
          "serviceName": "grpc-service",
          "multiMode": false
        },
        "sockopt": {
          "dialerProxy": "fragment"
        }
      }
    },
    {
      "tag": "fragment",
      "protocol": "freedom",
      "settings": {
        "fragment": {
          "packets": "tlshello",
          "length": "100-200",
          "interval": "10-20"
        }
      }
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "outboundTag": "proxy", "network": "tcp,udp" }
    ]
  }
}
```

### v2rayN Fragment settings (GUI)

- **Fragment:** enable
- **Packets:** `tlshello`
- **Length:** `100-200`
- **Interval:** `10-20`

---

## 2. Sing-box client config

```json
{
  "log": { "level": "warn" },
  "inbounds": [
    {
      "type": "mixed",
      "listen": "127.0.0.1",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "YOUR_DOMAIN.com",
      "server_port": 443,
      "uuid": "YOUR-UUID-HERE",
      "tls": {
        "enabled": true,
        "server_name": "YOUR_DOMAIN.com",
        "alpn": ["h2"],
        "utls": { "enabled": true, "fingerprint": "chrome" }
      },
      "transport": {
        "type": "grpc",
        "service_name": "grpc-service"
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [{ "outbound": "proxy" }]
  }
}
```

---

## Notes

- **CDN mode:** traffic goes `Client → Cloudflare → Germany Origin`. Tunnel is not involved.
- Generate UUID and gRPC service name from your 3x-ui panel if using proxy panel mode.
- For CDN-only static hosting, these client configs are not required.
