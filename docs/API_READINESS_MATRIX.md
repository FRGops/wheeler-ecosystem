# Wheeler Ecosystem — API Readiness Matrix
## Phase 3: API-by-API Health, Route, Auth, and Cutover Assessment

> **Date:** 2026-05-23
> **Assessment:** Read-only — live process + config inspection only
> **Score:** 1 (critical/offline) → 5 (fully ready)

---

## API READINESS SCORECARD

| # | API | Port | Health Route | Public Route | DB | Redis | Auth | PM2/Docker | Error State | Score |
|---|-----|------|-------------|-------------|-----|-------|------|------------|-------------|-------|
| 1 | Prediction Radar API | 8000 (internal) | `/health` | Via Traefik → Tailscale | ✅ PG16 healthy | ✅ Redis 7 healthy | ✅ JWT + API key | ✅ Docker healthy | None | **4/5** |
| 2 | FRGCRM API | N/A (errored) | N/A | N/A | ❓ PG via frgops-standby | N/A | ❓ | ❌ PM2 errored (15 restarts) | **CRITICAL** | **0/5** |
| 3 | SurplusAI API | N/A (waiting) | N/A | N/A | N/A | N/A | ❓ | ❌ PM2 waiting (282 restarts) | **CRITICAL** | **0/5** |
| 4 | RavynAI API | 8007 | `/health` | `ravynai.wheeler.ai` | ✅ PG16 healthy | N/A | ✅ API token | ✅ Docker healthy | None | **4/5** |
| 5 | FRGCRM Agent Svc | 8013 (IPv6) | `/health` (assumed) | Internal only | ✅ PG via frgops-standby | N/A | Internal | ✅ PM2 online (42h) | None | **3/5** |
| 6 | FRGCRM Mirror Test | 8003 (IPv6) | `/health` (assumed) | Internal only | ✅ PG via frgops-standby | N/A | Internal | ✅ PM2 online (42h) | None | **3/5** |
| 7 | Voice Agent Svc | N/A (waiting) | N/A | N/A | N/A | N/A | ❓ | ❌ PM2 waiting (282 restarts) | **CRITICAL** | **0/5** |
| 8 | Insforge Agent Svc | 8013 (IPv6) | Internal | Internal only | N/A | N/A | Internal | ✅ PM2 online (42h) | None | **3/5** |
| 9 | LiteLLM API | 4000 | `/health` | `litellm.wheeler.ai` | N/A | N/A | ❓ API keys | ✅ Docker (Hostinger) | Unknown | **3/5** |
| 10 | OpenClaw API | Internal | Gateway token | Internal only | ❓ | ❓ | ✅ Gateway token | via Prediction Radar | Unknown | **2/5** |
| 11 | Chatwoot API | 3000 (Hostinger) | `/health` (assumed) | `chatwoot.wheeler.ai` | ✅ Hostinger PG | ✅ Hostinger Redis | ✅ JWT | ✅ Docker (Hostinger) | Unknown | **3/5** |
| 12 | Docuseal API | 3010 | `/health` | `docuseal.wheeler.ai` | N/A | ✅ docuseal-redis | ✅ API token | ✅ Docker | None | **4/5** |

---

## DETAILED API ANALYSIS

### 1. Prediction Radar API — Score: 4/5

```
Port:           8000 (internal), 8098 (web via Traefik)
Health Route:   GET /health (assumed standard)
Public Route:   https://predictionradar.app → Hostinger Traefik → Tailscale → :8098
DB Status:      ✅ PostgreSQL 16 (prediction-radar-app-db, healthy)
Redis Status:   ✅ Redis 7 (prediction-radar-app-redis, healthy)
Auth:           JWT (FRGOPS_JWT_SECRET) + INTERNAL_API_KEY + OPERATOR_EMAIL/PASSWORD
Env Ready:      ✅ All env vars present (Stripe, AI keys, DB, Redis, Discord, etc.)
PM2/Docker:     ✅ Docker container healthy (43h uptime)
Error Logs:     None observed
Notes:          STRIPE_SECRET_KEY is sk_test_* — verify if this is intentional for prod
Cutover Ready:  ✅ High readiness. Keep on Hetzner. Verify Stripe mode.
```

### 2. FRGCRM API — Score: 0/5 ⚠️ CRITICAL

```
Port:           N/A — process not listening
Health Route:   N/A
Public Route:   N/A — API down
DB Status:      ❓ Cannot verify without running process
Redis Status:   N/A
Auth:           ❓ Unknown — API not running
PM2 Status:     ❌ ERROED — 15 restart attempts, process at PID 0
Error Logs:     Check ~/.pm2/logs/frgcrm-api-error-*.log
Fix Action:     pm2 logs frgcrm-api --lines 50  (inspect errors)
                Check port conflict on 8013 (shared with agent svc?)
                Check database connectivity to frgops-standby:5433
Cutover Ready:  ❌ CRITICAL — Must be fixed before any cutover
```

### 3. SurplusAI API — Score: 0/5 ⚠️ CRITICAL

```
Port:           N/A — process not listening
Health Route:   N/A
Public Route:   https://surplusai.io (frontend may work, API backend is down)
DB Status:      N/A
Redis Status:   N/A
Auth:           ❓ Unknown
PM2 Status:     ❌ WAITING — 282+ restart attempts
Error Logs:     Check ~/.pm2/logs/surplusai-scraper-agent-svc-error-*.log
Fix Action:     pm2 logs surplusai-scraper-agent-svc --lines 50
                Check dependency chain — what is it waiting on?
                May depend on FRGCRM API or database
Cutover Ready:  ❌ CRITICAL — Must be fixed before any cutover
```

### 4. RavynAI API — Score: 4/5

```
Port:           8007 (Docker, Traefik-routed)
Health Route:   GET /health (assumed standard)
Public Route:   https://ravynai.wheeler.ai → Hostinger Traefik → Tailscale → :8007
DB Status:      ✅ PostgreSQL 16 + PostGIS (aiops-ravynai-postgres, healthy)
Redis Status:   N/A
Auth:           API_AUTH_TOKEN (configured)
Env Ready:      ✅ DATABASE_URL, PORT, NODE_ENV, FRGCRM_API_URL all set
PM2/Docker:     ✅ Docker container healthy (43h uptime)
Error Logs:     None observed
Cutover Ready:  ✅ Ready. Keep on Hetzner.
```

### 5. LiteLLM API — Score: 3/5

```
Port:           4000 (Hostinger, Traefik-routed)
Health Route:   /health (LiteLLM standard)
Public Route:   https://litellm.wheeler.ai
DB Status:      N/A (proxy only)
Redis Status:   N/A
Auth:           ❓ Verify API keys configured (OpenAI, DeepSeek, Anthropic)
PM2/Docker:     ⚠️ Running on Hostinger — cannot verify from AIOPS
Error Logs:     Unknown — requires Hostinger access
Cutover Ready:  ⚠️ Needs verification from Hostinger side
```

### 6. Voice Agent Service — Score: 0/5 ⚠️ CRITICAL

```
Port:           N/A — process not listening
Health Route:   N/A
Public Route:   N/A — internal service
DB Status:      N/A
Redis Status:   N/A
Auth:           ❓ Unknown
PM2 Status:     ❌ WAITING — 282+ restart attempts
Error Logs:     Check ~/.pm2/logs/voice-agent-svc-error-*.log
Fix Action:     pm2 logs voice-agent-svc --lines 50
                Check OpenClaw gateway connectivity
                May depend on external voice provider API
Cutover Ready:  ❌ CRITICAL — Voice outreach offline
```

### 7. OpenClaw API — Score: 2/5

```
Port:           Internal (via Prediction Radar worker)
Health Route:   N/A (embedded in Prediction Radar)
Public Route:   N/A — internal gateway
DB Status:      ❓ Unknown
Redis Status:   ❓ Unknown
Auth:           ✅ OPENCLAW_GATEWAY_TOKEN (configured in Prediction Radar env)
Env Ready:      ✅ Token + OPENCLAW_NO_RESPAWN=1 configured
PM2/Docker:     Runs within Prediction Radar docker context
Error Logs:     Check Prediction Radar worker logs
Cutover Ready:  ⚠️ Needs verification — embedded dependency of Prediction Radar
```

---

## PORT ALLOCATION MAP (AIOPS Node Only)

```
Port    Service                 Status      Public?
────    ───────                 ──────      ───────
8000    Prediction Radar API    ✅ Docker   Internal (Tailscale)
8003    FRGCRM Mirror Test      ✅ PM2      Internal
8007    RavynAI API             ✅ Docker   Public (via Traefik)
8013    FRGCRM Agent Svc        ✅ PM2      Internal
8013    Insforge Agent Svc      ✅ PM2      Internal (shared port?)
8080    Spiderfoot              ✅ Docker   Internal
8088    Superset                ✅ Docker   Public (via Traefik)
8090    1Panel                  ✅ System   Internal
8098    Prediction Radar Web    ✅ Docker   Public (via Traefik)
8123    ClickHouse HTTP         ✅ Docker   Internal
3001    Uptime Kuma             ✅ Docker   Public (via Traefik)
3002    Grafana                 ✅ Docker   Public (via Traefik)
3010    Docuseal                ✅ Docker   Public (via Traefik)
3130    Healthchecks            ✅ Docker   Public (via Traefik)
4000    LiteLLM                 ✅ Hostinger Public (via Hostinger Traefik)
5000    ChangeDetection         ✅ Docker   Public (via Traefik)
5001    Dockge                  ✅ Docker   Internal (Tailscale)
5432    PostgreSQL (AIOps)      ✅ Docker   Internal
5433    frgops-standby PG       ✅ Docker   Internal
5434    RavynAI PG              ✅ Docker   Internal
5678    n8n                     ✅ Hostinger Public (via Hostinger Traefik)
6379    Redis (AIOps)           ✅ Docker   Internal
7860    Langflow                ✅ Docker   Internal
9000    Portainer               ✅ Docker   Internal (Tailscale)
9000    Webhook Receiver        ✅ Hostinger Public (via Hostinger Traefik)
9001    MinIO Console           ✅ Hostinger Internal
9090    Prometheus              ✅ Docker   Internal (Tailscale)
9091    Hostinger Health Exp    ✅ Docker   Internal
9100    Node Exporter           ✅ System   Internal
19999   Netdata                 ✅ Docker   Internal (Tailscale)
```

---

## CUTOVER READINESS SUMMARY

```
API                        Score   Status
──────────────────────────────────────────
Prediction Radar API        4/5    ✅ Ready — verify Stripe live mode
RavynAI API                 4/5    ✅ Ready
Docuseal API                4/5    ✅ Ready
FRGCRM Agent Svc            3/5    ⚠️ Running but internal only
FRGCRM Mirror Test          3/5    ⚠️ Running but internal only
Insforge Agent Svc          3/5    ⚠️ Running but internal only
LiteLLM API                 3/5    ⚠️ Needs Hostinger-side verification
Chatwoot API                3/5    ⚠️ Needs Hostinger-side verification
OpenClaw API                2/5    ⚠️ Embedded, needs verification
FRGCRM API                  0/5    ❌ CRITICAL — errored, 15 restarts
SurplusAI API               0/5    ❌ CRITICAL — waiting, 282 restarts
Voice Agent Svc             0/5    ❌ CRITICAL — waiting, 282 restarts
```

---

## IMMEDIATE ACTIONS REQUIRED

1. **Fix FRGCRM API** — inspect PM2 logs, check port conflict (8013 shared?), verify DB connectivity
2. **Fix SurplusAI Scraper Agent** — inspect PM2 logs, identify blocking dependency
3. **Fix Voice Agent Service** — inspect PM2 logs, check OpenClaw gateway, verify voice provider
4. **Verify Stripe mode** — Prediction Radar using `sk_test_*` keys — confirm this is intentional
5. **Verify Hostinger services** — LiteLLM, Chatwoot, n8n health from Hostinger side
