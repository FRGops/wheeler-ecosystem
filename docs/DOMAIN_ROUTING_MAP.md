# Wheeler Ecosystem — Public Domain Routing Map
## Phase 2: Complete Domain → Upstream → Health Mapping

> **Date:** 2026-05-23
> **Status:** Planning/scaffolding — no DNS changes applied
> **Source:** ARCHITECTURE.md, Traefik config analysis, Tailscale network inspection

---

## DNS ASSUMPTION LAYER

```
                      ┌──────────────────────────┐
                      │      CLOUDFLARE DNS       │
                      │  (DDoS Protection + WAF)  │
                      │  Proxy: 🟠 (Orange Cloud) │
                      └────────────┬─────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
         ┌─────────┴──────────┐       ┌──────────┴──────────┐
         │  HOSTINGER EDGE    │       │  HETZNER AIOPS      │
         │  187.77.148.88     │       │  5.78.140.118       │
         │  Traefik :80/:443  │       │  Traefik :80/:443   │
         │  (Public TLS Term) │       │  (Internal Router)   │
         └────────────────────┘       └─────────────────────┘
                    │                             │
         ┌──────────┴──────────┐       ┌──────────┴──────────┐
         │  TAILSCALE MESH     │       │  TAILSCALE MESH     │
         │  100.98.x.x         │◄──────►│  100.121.x.x        │
         └─────────────────────┘       └─────────────────────┘
```

---

## PUBLIC DOMAIN ROUTING TABLE

### 1. fundsrecoverygroup.com

| Field | Value |
|-------|-------|
| **Primary Domain** | `fundsrecoverygroup.com` |
| **WWW** | `www.fundsrecoverygroup.com` (redirect → apex) |
| **DNS Provider** | Cloudflare (assumed) |
| **Edge Router** | Hostinger Traefik (:80/:443) |
| **SSL** | Cloudflare Origin CA + Let's Encrypt (Traefik) |
| **Frontend Target** | Hostinger local FRGops app :3000 |
| **API Target** | Hostinger local FRGCRM API (or proxied to AIOPS) |
| **Upstream** | `http://localhost:3000` (Hostinger) |
| **Health Check** | `curl -I https://fundsrecoverygroup.com` |
| **Cutover Risk** | **HIGH** — Primary revenue domain. Any cutover requires verified DNS propagation + SSL + frontend + API + CRM all functional. |

---

### 2. wheeler.frgop.io

| Field | Value |
|-------|-------|
| **Primary Domain** | `wheeler.frgop.io` |
| **DNS Provider** | Cloudflare (assumed) |
| **Edge Router** | Hostinger Traefik (:80/:443) |
| **SSL** | Let's Encrypt (Traefik) |
| **Frontend Target** | Hostinger (Wheeler Brain OS dashboard) |
| **API Target** | Proxied to AIOPS via Tailscale |
| **Upstream** | `http://localhost:3000` or Tailscale `100.121.x.x` |
| **Health Check** | `curl -I https://wheeler.frgop.io` |
| **Cutover Risk** | **HIGH** — Wheeler Brain OS dashboard for operations |

---

### 3. predictionradar.app

| Field | Value |
|-------|-------|
| **Primary Domain** | `predictionradar.app` |
| **DNS Provider** | Cloudflare (assumed) |
| **Edge Router** | Hostinger Traefik (:80/:443) |
| **SSL** | Let's Encrypt (Traefik) |
| **Frontend Target** | Hetzner Docker: prediction-radar-app-web :8098 via Tailscale `100.121.230.28:8098` |
| **API Target** | Hetzner Docker: Prediction Radar API :8000 |
| **Dashboard Target** | Hetzner Docker: prediction-radar-dashboard-v2 :3000 |
| **Upstream (Traefik)** | `http://100.121.230.28:8098` (via Tailscale mesh) |
| **Health Check** | `curl -I https://predictionradar.app` + `curl http://100.121.230.28:8000/health` |
| **Cutover Risk** | **CRITICAL** — Primary revenue-generating SaaS. Stripe subscriptions, real-time predictions. All 4 containers must be healthy. |
| **Observed Config** | `APP_URL=https://predictionradar.app` confirmed in env vars |

---

### 4. frgops.fundsrecoverygroup.tech

| Field | Value |
|-------|-------|
| **Primary Domain** | `frgops.fundsrecoverygroup.tech` |
| **DNS Provider** | Cloudflare (assumed) |
| **Edge Router** | Hostinger Traefik (:80/:443) |
| **SSL** | Let's Encrypt (Traefik) |
| **Frontend Target** | Hostinger local :3000 |
| **API Target** | FRGCRM API (currently errored on AIOPS) |
| **Upstream** | `http://localhost:3000` |
| **Health Check** | `curl -I https://frgops.fundsrecoverygroup.tech` |
| **Cutover Risk** | **HIGH** — CRM operations portal. FRGCRM API ERRORED. |

---

### 5. radar.fundsrecoverygroup.tech

| Field | Value |
|-------|-------|
| **Primary Domain** | `radar.fundsrecoverygroup.tech` |
| **DNS Provider** | Cloudflare (assumed) |
| **Edge Router** | Hostinger Traefik (:80/:443) |
| **SSL** | Let's Encrypt (Traefik) |
| **Frontend Target** | Possibly Prediction Radar alias or separate dashboard |
| **Upstream** | Likely `http://100.121.230.28:8098` (Tailscale) |
| **Health Check** | `curl -I https://radar.fundsrecoverygroup.tech` |
| **Cutover Risk** | **MEDIUM** — Needs verification of actual routing |

---

### 6. surplusai.io (SurplusAI Portal)

| Field | Value |
|-------|-------|
| **Primary Domain** | `surplusai.io` |
| **WWW** | `www.surplusai.io` |
| **DNS Provider** | Cloudflare (assumed) |
| **Edge Router** | Hostinger Traefik (:80/:443) |
| **SSL** | Let's Encrypt (Traefik) |
| **Frontend Target** | Hostinger or AIOPS (to verify) |
| **API Target** | SurplusAI API (scraper agent WAITING on AIOPS) |
| **Upstream** | To verify via Hostinger Traefik config |
| **Health Check** | `curl -I https://surplusai.io` |
| **Cutover Risk** | **HIGH** — SurplusAI scraper agent stuck in restart loop |
| **Observed Config** | `FRGOPS_ALLOWED_ORIGINS` includes `https://surplusai.io` |

---

## TRAEFIK ROUTING — HOSTINGER EDGE (Public Entry)

```
Domain                                  → Upstream                         SSL    Risk
───────────────────────────────────────────────────────────────────────────────────────
fundsrecoverygroup.com                  → localhost:3000 (FRGops)          ✅     HIGH
www.fundsrecoverygroup.com              → REDIRECT → apex                  ✅     HIGH
wheeler.frgop.io                        → localhost:3000 (Brain OS)        ✅     HIGH
predictionradar.app                     → 100.121.230.28:8098 (Tailscale)  ✅     CRITICAL
radar.fundsrecoverygroup.tech           → 100.121.230.28:8098 (Tailscale)  ✅     MEDIUM
frgops.fundsrecoverygroup.tech          → localhost:3000 (FRGCRM)          ✅     HIGH
surplusai.io                            → TBD (verify Hostinger config)    ✅     HIGH
chatwoot.wheeler.ai                     → localhost:3000 (Chatwoot)        ✅     MEDIUM
n8n.wheeler.ai                          → localhost:5678                   ✅     MEDIUM
docuseal.wheeler.ai                     → 100.121.230.28:3010 (Tailscale)  ✅     LOW
litellm.wheeler.ai                      → localhost:4000                   ✅     HIGH
changedetect.wheeler.ai                 → 100.121.230.28:5000 (Tailscale)  ✅     LOW
grafana.wheeler.ai                      → 100.121.230.28:3002 (Tailscale)  ✅     LOW
superset.wheeler.ai                     → 100.121.230.28:8088 (Tailscale)  ✅     LOW
uptime.wheeler.ai                       → 100.121.230.28:3001 (Tailscale)  ✅     LOW
healthchecks.wheeler.ai                 → 100.121.230.28:3130 (Tailscale)  ✅     LOW
ravynai.wheeler.ai                      → 100.121.230.28:8007 (Tailscale)  ✅     LOW
```

---

## TAILSCALE MESH — INTERNAL ROUTING

```
Service                 AIOPS Tailscale IP      Hostinger Tailscale IP
─────────────────────────────────────────────────────────────────────
Prediction Radar API    100.121.230.28:8000     100.98.x.x → 100.121.230.28:8000
Prediction Radar Web    100.121.230.28:8098     100.98.x.x → 100.121.230.28:8098
RavynAI API             100.121.230.28:8007     100.98.x.x → 100.121.230.28:8007
FRGCRM API (PM2)       localhost:8013           N/A (runs on AIOPS)
FRGCRM Mirror Test      localhost:8003           N/A (runs on AIOPS)
FRGCRM Agent Svc        localhost:8013           N/A (runs on AIOPS)
```

---

## SSL CERTIFICATE STATUS

| Domain | Provider | Expiry Check | Status |
|--------|----------|-------------|--------|
| fundsrecoverygroup.com | Cloudflare + LE | `curl -vI https://fundsrecoverygroup.com 2>&1 \| grep -A6 'Server certificate'` | ⚠️ Verify |
| predictionradar.app | Cloudflare + LE | `curl -vI https://predictionradar.app 2>&1 \| grep -A6 'Server certificate'` | ⚠️ Verify |
| All *.wheeler.ai | Let's Encrypt (Traefik) | Automated renewal via Traefik | ⚠️ Verify |
| All *.fundsrecoverygroup.tech | Let's Encrypt (Traefik) | Automated renewal via Traefik | ⚠️ Verify |

---

## HEALTH CHECK COMMANDS (per domain)

```bash
# fundsrecoverygroup.com
curl -o /dev/null -s -w "%{http_code}" https://fundsrecoverygroup.com
curl -o /dev/null -s -w "%{http_code}" https://www.fundsrecoverygroup.com

# predictionradar.app
curl -o /dev/null -s -w "%{http_code}" https://predictionradar.app
curl -s http://100.121.230.28:8000/health       # API (Tailscale)
curl -s http://100.121.230.28:8098               # Web (Tailscale)

# wheeler.frgop.io
curl -o /dev/null -s -w "%{http_code}" https://wheeler.frgop.io

# frgops.fundsrecoverygroup.tech
curl -o /dev/null -s -w "%{http_code}" https://frgops.fundsrecoverygroup.tech

# surplusai.io
curl -o /dev/null -s -w "%{http_code}" https://surplusai.io

# AI proxy
curl -o /dev/null -s -w "%{http_code}" https://litellm.wheeler.ai/health

# RavynAI
curl -o /dev/null -s -w "%{http_code}" https://ravynai.wheeler.ai/health
```

---

## CUTOVER RISK SUMMARY

| Domain | Risk Level | Key Concern |
|--------|-----------|-------------|
| predictionradar.app | **CRITICAL** | Revenue SaaS — Stripe + AI + real-time predictions |
| fundsrecoverygroup.com | **HIGH** | Primary brand domain — lead intake + CRM |
| wheeler.frgop.io | **HIGH** | Operations dashboard — internal tooling |
| frgops.fundsrecoverygroup.tech | **HIGH** | CRM ops portal — FRGCRM API errored |
| surplusai.io | **HIGH** | SurplusAI — scraper agent stuck |
| radar.fundsrecoverygroup.tech | **MEDIUM** | May be an alias — verify routing |
| *.wheeler.ai (all subdomains) | **LOW-MEDIUM** | Support services — monitoring, analytics, docs |

---

## NEXT ACTIONS (Phase 2)

- [ ] Verify actual Hostinger Traefik config (remote access needed)
- [ ] Verify Cloudflare DNS A records point to Hostinger 187.77.148.88
- [ ] Check all SSL certificate expiry dates
- [ ] Verify Tailscale mesh connectivity between Hostinger and AIOPS
- [ ] Confirm `radar.fundsrecoverygroup.tech` routing
- [ ] Confirm `surplusai.io` upstream target
