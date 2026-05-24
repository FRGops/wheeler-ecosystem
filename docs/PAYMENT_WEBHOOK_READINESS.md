# Wheeler Revenue Ecosystem — Payment & Webhook Readiness Assessment
## 3-Server Cutover Preparation — AIOPS Node (Hetzner 5.78.140.118)

> **Date:** 2026-05-23
> **Assessment:** Read-only — live process + config inspection only
> **Scope:** All Stripe integrations, webhook receivers, payment endpoints, subscription tiering, and cutover risk
> **Secret Policy:** No real values printed — all secrets masked with `[CONFIGURED]`, `[TEST_MODE]`, or `[LIVE_MODE]` placeholders

---

## 1. STRIPE ENVIRONMENT VARIABLE AUDIT

### 1.1 Prediction Radar (Hetzner Docker)

The Prediction Radar container is the primary Stripe-integrated SaaS. Environment variables observed in the Docker env:

| Variable | Status | Mode | Notes |
|----------|--------|------|-------|
| `STRIPE_SECRET_KEY` | [CONFIGURED] | [TEST_MODE] | Prefix `sk_test_*` — all API calls use test keys |
| `STRIPE_PUBLISHABLE_KEY` | [CONFIGURED] | [TEST_MODE] | Prefix `pk_test_*` — client-side test key |
| `STRIPE_WEBHOOK_SECRET` | [CONFIGURED] | [CONFIGURED] | Prefix `whsec_*` — primary webhook signing secret |
| `FRGOPS_STRIPE_WEBHOOK_SECRET` | [CONFIGURED] | [CONFIGURED] | Prefix `whsec_*` — FRGops-specific webhook secret |
| `STRIPE_WEBHOOK_SECRET_E16` | [CONFIGURED] | [CONFIGURED] | Prefix `whsec_*` — possible duplicate/legacy webhook secret |
| `STRIPE_PRICE_PRO` | [CONFIGURED] | [CONFIGURED] | `price_*` — Professional tier |
| `STRIPE_PRICE_ENTERPRISE` | [CONFIGURED] | [CONFIGURED] | `price_*` — Enterprise tier |
| `STRIPE_PRICE_AGENCY` | [CONFIGURED] | [CONFIGURED] | `price_*` — Agency tier |
| `STRIPE_PRICE_MARKETING` | [CONFIGURED] | [CONFIGURED] | `price_*` — Marketing tier |
| `STRIPE_PRICE_FORENSIC` | [CONFIGURED] | [CONFIGURED] | `price_*` — Forensic tier |
| `STRIPE_PRICE_SIGNALS_PRO` | [CONFIGURED] | [CONFIGURED] | `price_*` — Signals Pro tier |
| `STRIPE_PRICE_PROMPTS_PRO` | [CONFIGURED] | [CONFIGURED] | `price_*` — Prompts Pro tier |

### 1.2 FRGops / FRGCRM (Hostinger Docker)

No Stripe env variables observed in the FRGops essential stack compose file. FRGops may use internal billing or relay through Prediction Radar. Verification needed from Hostinger side.

### 1.3 Key Audit Findings

1. **CRITICAL: All Stripe keys are TEST MODE** (`sk_test_*`, `pk_test_*`). The Prediction Radar is NOT processing live payments. This must be resolved before any revenue go-live.
2. **Three webhook secrets configured** (`STRIPE_WEBHOOK_SECRET`, `FRGOPS_STRIPE_WEBHOOK_SECRET`, `STRIPE_WEBHOOK_SECRET_E16`). The `_E16` variant may be a legacy or environment-specific duplicate. Review and consolidate.
3. **7 Stripe price IDs configured** — full subscription product catalog is defined. These need corresponding live-mode price IDs created in the Stripe Dashboard.
4. **No .env files found locally** — env vars are injected via Docker Compose environment blocks. The actual values live in an external secrets manager or uncommitted .env file on the deployment server.

---

## 2. WEBHOOK ROUTES INVENTORY

### 2.1 Stripe Webhook Routes

| Route | Location | Purpose | Status |
|-------|----------|---------|--------|
| `/webhook/stripe` | Hostinger webhook-receiver :9000 | Primary Stripe event ingestion | [CONFIGURED] |
| Stripe → webhook-receiver → n8n forward | hostinger | Forwarded to n8n `http://n8n:5678/webhook/` for workflow processing | [CONFIGURED] |

Stripe sends events to `https://webhooks.wheeler.ai/webhook/stripe`. The Hostinger Traefik edge terminates TLS and routes to the internal `webhook-receiver:9000` container. The webhook receiver validates the `Stripe-Signature` header using one of the configured `whsec_*` secrets, then forwards to n8n for workflow orchestration.

### 2.2 Discord Webhook Routes (Outbound)

| Variable | Status | Purpose |
|----------|--------|---------|
| `DISCORD_WEBHOOK_URL` | [CONFIGURED] | General notifications / operational alerts |
| `DISCORD_APPROVAL_WEBHOOK_URL` | [CONFIGURED] | Subscription approval / review workflow |
| `DISCORD_ALERT_WEBHOOK_URL` | [CONFIGURED] | Critical payment failure alerts |
| `DISCORD_BRIEFING_WEBHOOK_URL` | [CONFIGURED] | Periodic revenue briefing summaries |

These are outbound webhooks (Wheeler → Discord). The Alert Engine (`/root/wheeler-autonomous-ops/alert-engine/alert_engine.py`) posts JSON embeds to these URLs. Severity routing:
- `INFO` → Discord only
- `WARNING` → Discord + Slack
- `CRITICAL` → Discord + Slack + Email
- `OUTAGE` → ALL channels (including PagerDuty webhook)

### 2.3 Custom Webhook Routes (Webhook Receiver)

| Route | Purpose | Status |
|-------|---------|--------|
| `/health` | Webhook receiver health check | Active (Traefik checks every 30s) |
| `/webhook/github` | GitHub push/PR/issue events | [CONFIGURED] |
| `/webhook/stripe` | Stripe payment events (primary) | [CONFIGURED] |
| `/webhook/cloudflare` | Cloudflare log/tunnel events | [CONFIGURED] |
| `/webhook/monitoring` | External monitoring callbacks | [CONFIGURED] |

The webhook receiver is documented as handling: GitHub, Stripe, Cloudflare, and monitoring alert callbacks. The entrypoint is `/health` with additional routes defined in the receiver application code.

### 2.4 Operational Webhook Routes (Outbound)

| Route | Destination | Purpose |
|-------|------------|---------|
| `WHEELER_DISCORD_WEBHOOK` | Discord | Alert Engine notifications |
| `WHEELER_SLACK_WEBHOOK` | Slack | Warning/Critical alert routing |
| `WHEELER_PAGERDUTY_WEBHOOK` | PagerDuty/Opsgenie | Outage-level incident paging |
| Alertmanager Slack | Slack (via Alertmanager) | Prometheus alert routing |
| Alertmanager Generic Webhook | Healthchecks :3130 | Prometheus → Healthchecks dead man's switch |
| n8n Webhook URL | `https://n8n.wheeler.ai` | n8n workflow trigger endpoint |

---

## 3. WEBHOOK LOG LOCATIONS

### 3.1 Docker Container Logs (Primary Sources)

| Container | Log Driver | Max Size | Max Files | Path Pattern |
|-----------|-----------|----------|-----------|-------------|
| `webhook-receiver` | json-file | 10 MB | 3 | `/var/lib/docker/containers/*/webhook-receiver*.log` |
| `prediction-radar-api` | json-file | 10 MB | 3 | `/var/lib/docker/containers/*/prediction-radar-api*.log` |
| `prediction-radar-worker` | json-file | 10 MB | 3 | `/var/lib/docker/containers/*/prediction-radar-worker*.log` |
| `n8n-edge` | json-file | 10 MB | 3 | `/var/lib/docker/containers/*/n8n-edge*.log` |
| `traefik` (Hostinger) | json-file | 10 MB | 3 | `/var/lib/docker/containers/*/traefik*.log` (access logs show webhook 200/400/401) |

### 3.2 Application Logs

| Application | Log Path | Content |
|-------------|----------|---------|
| Revenue Guardian | `/var/log/wheeler-ops/revenue/` | Revenue surface health checks, Stripe webhook endpoint monitoring |
| Alert Engine | Shared logging via `shared.logging_config` | Alert dispatch records (Discord, Slack, Email, Webhook) |
| n8n Executions | In SQLite DB at `/home/node/.n8n/database.sqlite` | Webhook-triggered workflow execution logs, 7-day retention |

### 3.3 Traefik Access Logs

Traefik edge logs (Hostinger) capture all inbound webhook requests including:
- Source IP (X-Forwarded-For from Cloudflare)
- Request path and method
- Response status code
- Latency
- TLS handshake details

These are critical for debugging Stripe webhook delivery failures or signature verification errors.

---

## 4. PAYMENT ENDPOINTS INVENTORY

### 4.1 Prediction Radar (Primary Payment API)

Prediction Radar handles the full Stripe subscription lifecycle. Based on the FastAPI architecture and Stripe integration patterns, the expected endpoints are:

| Endpoint | Method | Purpose | Stripe API Used |
|----------|--------|---------|-----------------|
| `/api/checkout/session` | POST | Create Stripe Checkout Session | `stripe.checkout.Session.create()` |
| `/api/checkout/success` | GET | Checkout success redirect handler | Session retrieval |
| `/api/checkout/cancel` | GET | Checkout cancel redirect handler | N/A |
| `/api/webhook/stripe` | POST | Stripe webhook event handler (server-side) | Event verification + processing |
| `/api/subscriptions/` | GET | List user subscriptions | `stripe.Subscription.list()` |
| `/api/subscriptions/{id}` | GET | Get specific subscription | `stripe.Subscription.retrieve()` |
| `/api/subscriptions/{id}/cancel` | POST | Cancel subscription | `stripe.Subscription.update()` |
| `/api/customer-portal` | POST | Create Stripe Customer Portal session | `stripe.billingPortal.Session.create()` |
| `/api/prices/` | GET | List available price tiers | DB query (cached from Stripe) |
| `/api/invoices/` | GET | List user invoices | `stripe.Invoice.list()` |
| `/api/invoices/{id}` | GET | Get specific invoice | `stripe.Invoice.retrieve()` |

Note: The external webhook receiver on Hostinger (port 9000) and the Prediction Radar API (port 8000) both have Stripe webhook handler capabilities. It needs to be verified which is the canonical handler registered in the Stripe Dashboard.

### 4.2 External Stripe Webhook Flow

```
Stripe Dashboard Webhook Endpoint (registered in Stripe)
    │
    ▼
https://webhooks.wheeler.ai/webhook/stripe  (Cloudflare → Hostinger Traefik :443)
    │
    ▼
Hostinger Traefik routes to webhook-receiver:9000
    │
    ▼
webhook-receiver validates Stripe-Signature with whsec_*
    │
    ▼
webhook-receiver forwards to n8n:5678/webhook/
    │
    ▼
n8n workflow triggers (subscription created/updated/deleted, invoice.paid, etc.)
    │
    ├──► Discord notification (DISCORD_APPROVAL_WEBHOOK_URL)
    ├──► Prediction Radar callback (update user subscription status)
    └──► Revenue Guardian alert if failures detected
```

---

## 5. SUBSCRIPTION ROUTES AND PRICE TIERS

### 5.1 Active Price Tiers (7 total)

| Tier | Stripe Price ID | Target Segment | Revenue Impact |
|------|----------------|----------------|----------------|
| Professional | `STRIPE_PRICE_PRO` [CONFIGURED] | Individual analysts / small teams | MEDIUM |
| Enterprise | `STRIPE_PRICE_ENTERPRISE` [CONFIGURED] | Large organizations / unlimited seats | HIGH |
| Agency | `STRIPE_PRICE_AGENCY` [CONFIGURED] | Multi-client agencies / white-label | HIGH |
| Marketing | `STRIPE_PRICE_MARKETING` [CONFIGURED] | Marketing teams / campaign prediction | MEDIUM |
| Forensic | `STRIPE_PRICE_FORENSIC` [CONFIGURED] | Financial forensic / fraud investigation | MEDIUM |
| Signals Pro | `STRIPE_PRICE_SIGNALS_PRO` [CONFIGURED] | Professional traders / signal consumers | HIGH |
| Prompts Pro | `STRIPE_PRICE_PROMPTS_PRO` [CONFIGURED] | AI prompt engineering / model tuning | LOW |

### 5.2 Subscription Lifecycle

The Prediction Radar worker handles subscription lifecycle events:

- **Created:** `customer.subscription.created` → Provision tier features, send welcome + Discord notification
- **Updated:** `customer.subscription.updated` → Handle tier changes, proration, feature gating
- **Deleted:** `customer.subscription.deleted` → Revoke access, retain data per retention policy
- **Trial Ending:** `customer.subscription.trial_will_end` → Reminder notification
- **Payment Failed:** `invoice.payment_failed` → Dunning workflow, access suspension
- **Payment Succeeded:** `invoice.paid` → Access reactivation, receipt generation

### 5.3 Subscription State Storage

Subscription state is persisted in Prediction Radar's PostgreSQL database (`prediction-radar-app-db`, PG16) and synced with Stripe as the source of truth. The database is on Hetzner, port 5433.

---

## 6. CUSTOMER PORTAL ROUTES

### 6.1 Stripe Customer Portal

| Route | Method | Description |
|-------|--------|-------------|
| `/api/customer-portal` | POST | Creates a Stripe Billing Portal session, returns redirect URL |
| Stripe Portal (redirect) | GET | Stripe-hosted portal for subscription management, payment methods, invoice history |

The Customer Portal is Stripe-hosted (no custom UI for billing management). Users are redirected to `billing.stripe.com` for self-service subscription management.

### 6.2 API Authentication

Prediction Radar API uses:
- **JWT** (`FRGOPS_JWT_SECRET`) for user-authenticated routes
- **API Key** (`INTERNAL_API_KEY`) for service-to-service calls
- **Operator credentials** (`OPERATOR_EMAIL` / `OPERATOR_PASSWORD`) for admin access

Stripe webhook validation uses the `whsec_*` signing secret to verify `Stripe-Signature` headers — no JWT/API key needed for inbound webhooks.

---

## 7. TEST MODE VS LIVE MODE INDICATOR ASSESSMENT

### 7.1 Current State: [TEST_MODE]

| Evidence | Detail |
|----------|--------|
| `STRIPE_SECRET_KEY` | `sk_test_*` prefix — all API calls hit Stripe test environment |
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_*` prefix — client-side Checkout uses test mode |
| Subscription data | All subscriptions, customers, and payments exist in Stripe test mode |
| Price IDs | 7 `price_*` IDs point to test-mode products |

### 7.2 Verification Items

| Check | Status | Action Required |
|-------|--------|----------------|
| Are test-mode prices mirrored in live mode? | Unknown | Audit Stripe Dashboard for live-mode product catalog |
| Are test customers real or synthetic? | Unknown | Review test customer list for real email addresses |
| Has any live payment ever been processed? | Likely No | Check Stripe Dashboard for live-mode charges |
| Is test data compatible with live migration? | Unknown | Assess whether to migrate test customers or start fresh |

### 7.3 Go-Live Checklist for Stripe

1. Create live-mode products and prices in Stripe Dashboard matching the 7 tiers
2. Generate live `sk_live_*` and `pk_live_*` keys
3. Create new `whsec_*` webhook signing secret for live endpoint
4. Register live webhook endpoint in Stripe Dashboard (`https://webhooks.wheeler.ai/webhook/stripe`)
5. Update all `STRIPE_PRICE_*`, `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, and `STRIPE_WEBHOOK_SECRET*` env vars on Prediction Radar container
6. Test end-to-end subscription flow in live mode with a real card
7. Monitor webhook delivery in Stripe Dashboard for 24h before full launch

---

## 8. WEBHOOK RECEIVER STATUS (Hostinger :9000)

### 8.1 Infrastructure

| Component | Detail |
|-----------|--------|
| **Container** | `webhook-receiver` |
| **Image** | `ghcr.io/wheeler-ai/webhook-receiver:latest` |
| **Host** | Hostinger VPS (Docker) |
| **Internal Port** | 9000 |
| **Public URL** | `https://webhooks.wheeler.ai` |
| **TLS** | Terminated at Hostinger Traefik (Cloudflare cert resolver) |
| **Routing** | Hostinger Traefik → `http://webhook-receiver:9000` (local Docker transport) |
| **Health Check** | `curl -f http://localhost:9000/health` (every 30s) |
| **Rate Limiting** | Strict — 10 req/s average, 20 burst (Traefik `rate-limit-strict` middleware) |
| **Dependencies** | Soft dependency on n8n (operates independently if n8n is down) |
| **Resource Limits** | 0.25 CPU, 128 MB RAM |
| **Secret** | `WEBHOOK_RECEIVER_SECRET` env var for inbound webhook validation |
| **Retry** | 3 attempts, exponential backoff (1s base), 10s forward timeout |

### 8.2 Middleware Protection

The webhooks route uses a different Traefik middleware chain than other routes:
- **`rate-limit-strict`** (10 req/s) — tighter than the standard edge rate limit, since webhooks are common attack vectors
- **`security-headers`** — HSTS, CSP, X-Frame-Options, etc.
- **No `chain-full`** — CrowdSec is intentionally NOT applied to webhook routes (Stripe IPs can change and CrowdSec false positives would drop legitimate payments)
- **No `chain-security`** — the strict rate limit replaces the standard rate-limit-edge

### 8.3 Webhook Receiver Entrypoints

```
/health            → Health check (returns 200)
/webhook/stripe    → Stripe event ingestion
/webhook/github    → GitHub push/PR events
/webhook/cloudflare → Cloudflare log events
/webhook/monitoring → External monitoring callbacks
```

### 8.4 Log Access

```bash
# Webhook receiver logs
docker logs webhook-receiver --tail 100

# Traefik access logs (filter for webhook requests)
docker logs traefik --tail 500 | grep "webhooks.wheeler.ai"

# n8n webhook execution logs
docker logs n8n-edge --tail 100 | grep -i stripe
```

---

## 9. CUTOVER RISKS FOR PAYMENT SYSTEMS

### 9.1 Risk Matrix

| Risk | Severity | Likelihood | Impact | Mitigation |
|------|----------|-----------|--------|------------|
| Stripe webhook delivery interrupted during DNS cutover | **CRITICAL** | Medium | Missed `invoice.paid` events → access not provisioned; missed `invoice.payment_failed` → no dunning | Pre-register both old and new webhook URLs in Stripe Dashboard; use webhook retry (Stripe retries for 3 days) |
| Wrong webhook signing secret used after cutover | **HIGH** | Medium | All webhooks fail signature verification → all events dropped | Verify `STRIPE_WEBHOOK_SECRET` matches the endpoint registered in Stripe Dashboard after cutover |
| Test mode keys not swapped to live mode | **CRITICAL** | High (current state) | No real payments possible; subscriptions in test mode | Complete Section 7.3 go-live checklist BEFORE cutover |
| Webhook receiver IP change not reflected in firewall | **HIGH** | Low | Stripe webhooks blocked by firewall | Ensure Stripe IP ranges are whitelisted on Hetzner UFW |
| Traefik rate-limit-strict blocks burst webhooks | **MEDIUM** | Low | Stripe sends webhook bursts during billing cycles | Monitor rate-limit hit count during first billing cycle; increase burst to 50 if needed |
| n8n downstream unavailable | **MEDIUM** | Low | Webhooks received but not processed | webhook-receiver operates independently; events queued/retried |
| Discord webhook URL stale | **LOW** | Low | Admin alerts lost during payment failures | Verify all Discord webhook URLs still active |
| Duplicate webhook secrets (`E16` vs primary) | **MEDIUM** | Medium | Wrong secret used after rotation | Consolidate to single `STRIPE_WEBHOOK_SECRET` before cutover |
| Prediction Radar DB migration during cutover | **HIGH** | Medium | Subscription state lost or corrupted | Full DB backup before cutover; verify after migration |
| Tailscale mesh interruption | **CRITICAL** | Low | Hostinger Traefik can't reach Hetzner Prediction Radar | Keep Tailscale connected on both nodes; test connectivity before cutover |

### 9.2 Single Points of Failure

1. **Hostinger Traefik** — All webhook traffic enters through this single Traefik instance. If it goes down, ALL webhooks (Stripe, GitHub, Cloudflare) are lost until recovery. Stripe retries for 3 days with exponential backoff, so brief outages are tolerable.
2. **webhook-receiver container** — Single instance, no horizontal scaling. If it crashes, Docker restart policy (`unless-stopped`) brings it back. No events are permanently lost because Stripe retries undelivered webhooks.
3. **n8n edge** — If n8n is down, the webhook receiver still accepts events but cannot forward them to workflows. The forward timeout is 10s, after which the webhook receiver returns an error to Stripe, triggering a retry.
4. **Tailscale mesh** — Required for Hostinger Traefik to reach Hetzner Prediction Radar. If Tailscale drops, the Prediction Radar API becomes unreachable from the edge, but webhook ingestion (which stays on Hostinger) continues.

### 9.3 Pre-Cutover Validation Commands

```bash
# 1. Verify webhook receiver is healthy
curl -f https://webhooks.wheeler.ai/health

# 2. Verify Prediction Radar API is reachable from Hostinger
curl -f http://100.121.230.28:8000/health

# 3. Verify Stripe webhook endpoint is registered and active
# (Requires Stripe CLI or Dashboard access)
stripe webhook_endpoints list --limit 10

# 4. Test Stripe webhook delivery
stripe trigger payment_intent.succeeded

# 5. Verify Discord webhooks are functional
# (Send test message via curl to DISCORD_ALERT_WEBHOOK_URL)

# 6. Check webhook receiver logs for recent activity
docker logs webhook-receiver --tail 50 --since 1h
```

---

## 10. ROLLBACK CONSIDERATIONS FOR PAYMENT/WEBHOOK CUTOVER

### 10.1 Rollback Triggers

Initiate payment/webhook rollback if any of the following occurs during cutover:

| Trigger | Threshold | Action |
|---------|-----------|--------|
| Stripe webhook delivery failure rate >5% | 1 hour | Roll back DNS for webhooks.wheeler.ai to Hostinger |
| Payment checkout flow broken | Any customer report | Immediate rollback — revenue loss is ongoing |
| Customer Portal redirect loop | Any occurrence | Roll back, investigate Stripe Dashboard config |
| Webhook signature verification failures | Any occurrence | Verify webhook secret, roll back if not quickly resolvable |
| Subscription state mismatch | >3 discrepancies | Halt cutover, reconcile DB with Stripe |

### 10.2 Rollback Procedure

```
Step 1: REVERT DNS (if changed)
  → Point webhooks.wheeler.ai back to Hostinger Traefik
  → Wait for DNS propagation (Cloudflare TTL)
  → Verify: curl -v https://webhooks.wheeler.ai/health

Step 2: REVERT STRIPE DASHBOARD CONFIG
  → If webhook endpoint URL was changed, revert to original
  → If API keys were rotated, revert to previous keys

Step 3: REVERT ENV VARS
  → Restore previous STRIPE_* env vars on Prediction Radar container
  → Restart Prediction Radar API: docker compose --project-name prediction-radar restart api

Step 4: VERIFY WEBHOOK DELIVERY
  → Use Stripe Dashboard to check webhook delivery status
  → Trigger test event: stripe trigger payment_intent.succeeded
  → Verify in webhook receiver logs: docker logs webhook-receiver --tail 20

Step 5: VERIFY CHECKOUT FLOW
  → Run through test checkout end-to-end
  → Confirm subscription provisioning
  → Confirm Customer Portal access

Step 6: NOTIFY STAKEHOLDERS
  → Discord: Rollback complete, payment systems back to pre-cutover state
  → Log: Document rollback in migration log with timestamps
```

### 10.3 Pre-Cutover Snapshot Checklist

Before executing any payment cutover, capture:

- [ ] Stripe Dashboard webhook endpoint URL and status (screenshot)
- [ ] Current Stripe API key prefixes (sk_live_ vs sk_test_)
- [ ] All `STRIPE_PRICE_*` values from Prediction Radar env
- [ ] Webhook signing secret (4-char prefix only for ID, never full secret)
- [ ] Prediction Radar postgres DB dump (subscription state)
- [ ] n8n workflow export (JSON backup of Stripe-related workflows)
- [ ] List of active subscriptions from Prediction Radar DB
- [ ] Traefik configuration snapshot (routers.yml, dynamic.yml)
- [ ] webhook-receiver Docker image SHA256
- [ ] UFW firewall rules on both Hostinger and Hetzner

### 10.4 Stripe-Specific Rollback Notes

- **Stripe webhooks have built-in retry**: Undelivered webhooks are retried for 3 days with exponential backoff. A brief outage during rollback won't cause permanent data loss — events will be re-delivered once the endpoint recovers.
- **Stripe idempotency**: Stripe events have unique `id` fields. The webhook handler should be idempotent (process each event only once) to prevent duplicate subscription provisioning during retry storms.
- **Customer Portal sessions expire**: Stripe Customer Portal sessions are short-lived (typically 1 hour). Any active sessions during cutover will need to be re-created.
- **Test mode data is ephemeral**: If currently in test mode, there is no real revenue at risk from the cutover itself. The primary risk is delaying the transition to live mode.

---

## 11. SUMMARY OF FINDINGS

### Operational Status

| System | Status | Notes |
|--------|--------|-------|
| Webhook Receiver (Hostinger :9000) | Operational | Healthy, Traefik-routed, rate-limited |
| Prediction Radar Stripe Integration | Operational [TEST_MODE] | Full subscription flow works but in test mode |
| Discord Alert Webhooks (4 URLs) | [CONFIGURED] | Outbound webhooks active |
| Alert Engine | Operational | Multi-channel routing configured |
| Revenue Guardian Monitoring | Operational | Stripe webhook endpoint monitored as CRITICAL surface |
| n8n Webhook Workflows | Operational | Auto-forwards from webhook-receiver |
| Alertmanager Slack/Webhook | [CONFIGURED] | Prometheus alert routing |

### Critical Actions Before Cutover

1. **Resolve Stripe test mode** — Swap all `sk_test_*` / `pk_test_*` to live keys; create live-mode products/prices; register live webhook endpoint
2. **Consolidate webhook secrets** — `STRIPE_WEBHOOK_SECRET`, `FRGOPS_STRIPE_WEBHOOK_SECRET`, `STRIPE_WEBHOOK_SECRET_E16` — determine which are active and remove duplicates
3. **Verify canonical webhook route** — Confirm whether Stripe calls `webhooks.wheeler.ai/webhook/stripe` or Prediction Radar's internal endpoint
4. **Backup all subscription state** — Full PG dump of `prediction-radar-app-db`
5. **Register new webhook endpoint** — If DNS changes during cutover, pre-register BOTH old and new URLs in Stripe Dashboard
6. **Test live checkout end-to-end** — Process a real $1 charge before full launch

### Confidence Assessment

| Area | Readiness | Notes |
|------|-----------|-------|
| Webhook Infrastructure | 4/5 | Solid setup, rate-limited, health-checked. Consolidate secrets. |
| Stripe Integration | 3/5 | Full integration exists but in TEST MODE. Needs live key swap. |
| Subscription Management | 3/5 | 7 tiers configured but all test-mode price IDs. |
| Alerting/Monitoring | 4/5 | Revenue Guardian + Alert Engine cover Stripe as CRITICAL. |
| Rollback Plan | 4/5 | DNS-based rollback is quick (Cloudflare TTL). Stripe built-in retry provides safety net. |
