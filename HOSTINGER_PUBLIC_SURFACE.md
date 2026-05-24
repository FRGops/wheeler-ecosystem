# Hostinger Public Surface Audit
**Server:** wheeler-aiops-01 | **Date:** 2026-05-24 | **Public IP:** 5.78.140.118

---

## 1. What Is Actually Reachable From the Internet

### Directly Exposed (UFW ALLOW Anywhere + service on 0.0.0.0)

| Port | Service | Auth? | Risk |
|------|---------|-------|------|
| **22** | SSH (LIMIT rate-limited) | Yes (key-based) | HIGH |
| **80** | nginx (dead listener, no content served) | N/A | LOW |
| **8090** | 1Panel Server Admin Panel | Login page | **CRITICAL** |
| **3002** | Grafana | Login page | **HIGH** |
| **8088** | Apache Superset | Login page | **HIGH** |
| **3001** | Uptime-Kuma | No auth by default | **HIGH** |
| **19999** | Netdata | No auth by default | **HIGH** |
| **5000** | Changedetection.io | Login page | MEDIUM |
| **3130** | Healthchecks.io | Login page | MEDIUM |
| **8098** | Prediction Radar Web | Unknown | MEDIUM |
| **8123** | ClickHouse HTTP (DATABASE) | None visible | **CRITICAL** |
| **8007** | surplusai-scraper-agent-svc | Internal API | **HIGH** |
| **5001** | NOTHING (stale rule, no listener) | N/A | LOW |
| **9091** | hostinger-health-exporter | None | LOW |

### Exposed via Docker (0.0.0.0 binding, UFW-dependent)

| Port | Container | Notes |
|------|-----------|-------|
| 7860 | langflow | AI workflow UI |
| 3010 | docuseal | Document signing |
| 3100 | loki | Log aggregation |
| 9080 | promtail | Log collector |
| 9090 | prometheus | Metrics (UFW DENY overrides for pub) |
| 9100 | node_exporter | System metrics |

### Tailscale-Only / Not Internet-Reachable
- **443 (HTTPS)**: nginx binds only to Tailscale IP `100.121.230.28`
- **All PM2 agent services**: localhost-only (8003, 8006-8013, 8020, 8082, 8091, 8095, 8103)
- **PostgreSQL**: both instances (5433, 5434) bind to 127.0.0.1
- **Redis**: no published ports
- **Temporal Server**: binds to 127.0.1.1

---

## 2. Architecture Diagram (Exposure Flow)

```
INTERNET
   │
   ▼
[5.78.140.118]  ←── No Cloudflare WAF, no CDN, direct IP exposure
   │
   ├── UFW (active, default deny incoming)
   │     ├── 22 (SSH) ───────────── ALLOW Anywhere (LIMIT)
   │     ├── 80 (nginx dead) ────── ALLOW Anywhere
   │     ├── 8090 (1Panel) ──────── ALLOW Anywhere  ← CRITICAL
   │     ├── 3002 (Grafana) ─────── ALLOW Anywhere  ← HIGH
   │     ├── 8088 (Superset) ────── ALLOW Anywhere  ← HIGH
   │     ├── 8123 (ClickHouse) ──── ALLOW tailscale0 only  ← Bound 0.0.0.0!
   │     └── ... (see UFW audit for full list)
   │
   ├── nginx (binds Tailscale IP :443 ONLY)
   │     └── Proxies → 127.0.0.1:xxxx (localhost services)
   │
   ├── Docker containers (14 on 0.0.0.0)
   │     ├── Reachable directly IF UFW permits
   │     └── Also reachable via nginx on Tailscale
   │
   └── PM2 services (all localhost-only, safe)
```

---

## 3. Protection Gaps

| Gap | Severity | Detail |
|-----|----------|--------|
| **No Cloudflare/WAF** | HIGH | Direct IP exposure, no DDoS protection, no bot filtering |
| **No public HTTPS** | MEDIUM | Port 443 only on Tailscale IP; public web would be plain HTTP |
| **14 Docker 0.0.0.0 bindings** | HIGH | Containers bypass nginx; UFW is the only protection |
| **3 host-network containers** | HIGH | temporal-ui, temporal-server, usesend bypass Docker isolation |
| **Port 80 dead listener** | LOW | nginx opens 0.0.0.0:80 via systemd socket but serves nothing |
| **Self-signed SSL** | INFO | Appropriate for Tailscale mesh, but no public CA trust |

---

## 4. Traffic Flow Reality

**Normal access pattern:**
MacBook → Tailscale mesh → `https://grafana.aiops` (resolves via Tailscale DNS to 100.121.230.28:443) → nginx → 127.0.0.1:3002

**What ALSO works (if UFW allows):**
Anyone → `http://5.78.140.118:3002` → Docker container directly on 0.0.0.0:3002

**The nginx gateway is correctly configured but the Docker port bindings create a parallel access path that bypasses it entirely.**

---

## 5. Quick Wins (No-Risk Changes)

1. **Delete UFW rules 30-41** (the Anywhere ALLOW rules overriding tailscale0 restrictions) — 8 admin panels go dark instantly from the internet
2. **Re-bind Docker containers to 127.0.0.1** (e.g., `127.0.0.1:3002:3000` instead of `0.0.0.0:3002:3000`) — nginx still reaches them, internet can't
3. **Remove port 80 from nginx** or add a redirect — eliminate the dead listener
