# Wheeler Ecosystem — Canary Deployment Plan

> **Classification**: PRODUCTION-SAFE — INTERNAL ONLY
> **Effective date**: 2026-05-23
> **Owners**: Platform Engineering / Release Engineering
> **Infrastructure**: 3-server (EDGE / AIOPS / COREDB) + Tailscale mesh
>
> **Purpose**: Define the standard operating procedure for rolling out new
> service versions via gradual traffic shifting (canary deployment), with
> automated health validation, rollback triggers, and promotion gates.

---

## Table of Contents

1. [Canary Philosophy & Constraints](#1-canary-philosophy--constraints)
2. [Traffic Splitting Architecture](#2-traffic-splitting-architecture)
3. [Canary Stage Progression](#3-canary-stage-progression)
4. [Health Checks & Validation](#4-health-checks--validation)
5. [Rollback Triggers & Thresholds](#5-rollback-triggers--thresholds)
6. [Promotion Gates](#6-promotion-gates)
7. [Canary Configuration File Format](#7-canary-configuration-file-format)
8. [Emergency Abort Procedure](#8-emergency-abort-procedure)
9. [Server-Specific Procedures](#9-server-specific-procedures)
10. [Canary Log Template](#10-canary-log-template)

---

## 1. Canary Philosophy & Constraints

### 1.1 Core Principle

> **Shift traffic gradually, validate at every step, and never let a bad
> release reach full production.** The canary deployment is the last line of
> defense between a green CI/CD pipeline and production users.

### 1.2 Scope

Canary deployments apply to these service categories:

| Category | Deployment Method | Canary Applies |
|----------|------------------|----------------|
| PM2 Node.js apps (AIOPS) | `pm2 reload` with fallback | Yes |
| PM2 Python apps (AIOPS) | New instance + port switch | Yes |
| Docker containers (all nodes) | New container + traffic shift | Yes |
| Static frontends (EDGE Nginx) | New directory + symlink swap | Yes |
| Database schema changes (COREDB) | Forward-only migrations | No (migrate in advance) |
| Configuration changes (all nodes) | Atomic file replace + reload | Yes |

### 1.3 Rules

| Rule | Explanation |
|------|-------------|
| **Only one canary at a time** | Never overlap canary deployments across services. |
| **Bake fully at each stage** | Complete the full bake time before promoting to the next stage. |
| **Metrics-driven promotion** | Automated promotion requires all metrics within threshold. Manual promotion requires SRE sign-off. |
| **Rollback must be faster than rollout** | Abort + rollback combined must take less time than the shortest canary stage. |
| **Pre-canary snapshot required** | A backup or snapshot of the affected service state must exist before starting. |
| **Canary is a deployment, not a test** | Pre-canary testing (staging, integration tests) must already be green. |

### 1.4 Constraints

- **AIOPS is the control plane**: all canary orchestration commands originate from AIOPS (5.78.140.118).
- **EDGE Traefik is the traffic router**: all canary traffic splitting happens at the EDGE node's Traefik instance (187.77.148.88).
- **Tailscale is the backchannel**: AIOPS reaches COREDB and EDGE via Tailscale mesh. Ensure Tailscale is healthy before starting.
- **DNS TTL must be planned**: if the canary involves a DNS change, the TTL must be lowered to 60 seconds at least 1 hour before the canary begins.
- **Sticky sessions**: Traefik session affinity should be disabled during canary to ensure uniform traffic distribution across stable and canary instances.

---

## 2. Traffic Splitting Architecture

### 2.1 Traefik Weighted Round-Robin

The EDGE Traefik instance acts as the canary traffic controller. Traffic is
split between the stable (current production) service and the canary (new
version) service using Traefik's weighted round-robin load balancing.

```
                         ┌───────────────────────┐
                         │   EDGE Node            │
                         │   187.77.148.88        │
                         │                        │
  Internet ──────────────│  Traefik (port 443)    │
                         │      │                 │
                         │      │  Weighted RR    │
                         │      │                 │
                         │  ┌───┴───────────┐     │
                         │  │                │     │
                         │  ▼ 95%            ▼ 5%  │
                         │  stable           canary│
                         │  instance         instance
                         └───┬───────────────┬─────┘
                             │               │
                    Tailscale │               │ Tailscale
                             ▼               ▼
                    ┌────────────────────────────────┐
                    │   AIOPS Node                   │
                    │   5.78.140.118                 │
                    │                                │
                    │  stable:3000    canary:3001    │
                    │  (PM2/Docker)   (PM2/Docker)   │
                    └────────────────────────────────┘
```

### 2.2 Traffic Weight Progression

| Stage | Stable Weight | Canary Weight | Duration (min) | Bake Time |
|-------|--------------|---------------|----------------|-----------|
| Stage 0 | 100% | 0% (pre-flight) | — | Health check only |
| Stage 1 | 95% | 5% | 10 min | 10 min |
| Stage 2 | 75% | 25% | 15 min | 15 min |
| Stage 3 | 50% | 50% | 20 min | 20 min |
| Stage 4 | 0% | 100% (full cutover) | — | 30 min post-cutover |
| Cleanup | — | — | — | Remove stable old version |

### 2.3 Traefik Configuration for Canary

Traefik uses two services for the same router with weighted load balancing:

```yaml
# Stable service (original production)
http:
  services:
    wheeler-api-stable:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:8082"    # AIOPS stable port
        healthCheck:
          path: /health
          interval: 10s
          timeout: 3s

    # Canary service (new version)
    wheeler-api-canary:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:8083"    # AIOPS canary port
        healthCheck:
          path: /health
          interval: 10s
          timeout: 3s

  routers:
    wheeler-api:
      rule: "Host(`api.wheeler.ai`)"
      entryPoints: ["websecure"]
      service: wheeler-api-stable        # Canary is added as secondary
      middlewares:
        - "chain-public@file"
      tls:
        certResolver: cloudflare
```

The weight is adjusted by modifying the Traefik dynamic configuration and
triggering an in-place reload (Traefik supports hot-reload of dynamic config).
Weight changes are applied via the Traefik API or by updating the dynamic.yml
file.

---

## 3. Canary Stage Progression

### 3.1 Stage 0 — Pre-Flight (0% traffic)

**Duration**: 5 minutes
**Traffic**: 0% (canary instance running but not receiving traffic)

Actions:
1. Deploy the canary instance (new PM2 process on alternate port, or new Docker container).
2. Verify the canary instance is running and all health checks pass.
3. Run the full validation suite against the canary instance directly (bypassing Traefik).
4. Check resource consumption (CPU, memory, open file handles).
5. Verify database connectivity (migrations already applied, no pending schema changes).
6. Verify Redis connectivity (cache state, session data).

Exit criteria:
- All validation tests pass.
- Resource consumption is within expected range (+/- 20% of stable).
- No errors in canary instance logs for 2 consecutive minutes.
- All health check endpoints return 200.

If Stage 0 fails: Abort canary. Fix issues. Retry from Stage 0.

### 3.2 Stage 1 — 5% Canary (10-minute bake)

**Duration**: 10 minutes (bake time)
**Traffic**: 5% canary, 95% stable

Actions:
1. Update Traefik weights to 5% canary / 95% stable.
2. Monitor error rates on both stable and canary for 10 minutes.
3. Compare latency percentiles (p50, p95, p99) between stable and canary.
4. Monitor canary instance resource usage (CPU, memory, disk).
5. Verify business metrics (successful API calls, completed transactions).
6. Watch application logs for warnings and errors.
7. Verify that AI API routing (LiteLLM) works correctly on the canary.
8. Verify that OpenRouter fallback is functional.

Exit criteria:
- Canary error rate < 1% AND within 50% deviation of stable error rate.
- Canary p95 latency < stable p95 latency * 1.5.
- No memory or resource leaks detected (memory growth < 5% over the 10 minutes).
- All business metrics within baseline range.
- Zero critical log entries.

If Stage 1 fails: Immediately revert Traefik weights to 0% canary / 100% stable.
Investigate root cause. Fix. Restart from Stage 0.

### 3.3 Stage 2 — 25% Canary (15-minute bake)

**Duration**: 15 minutes (bake time)
**Traffic**: 25% canary, 75% stable

Actions:
1. Update Traefik weights to 25% canary / 75% stable.
2. Run a burst load test against the canary (2x normal traffic rate for 30 seconds).
3. Monitor all Stage 1 metrics with heightened thresholds.
4. Check downstream service impact (database connections, Redis connections).
5. Verify that user-facing response times remain acceptable.
6. Check that the canary is not saturating COREDB connections.
7. Verify log volume is proportional to traffic shift (not emitting excess noise).

Exit criteria:
- Canary error rate < 0.5%.
- Canary p95 latency < stable p95 latency * 1.3.
- Burst load handled without degradation.
- Downstream service connections within safe limits.
- No database or Redis connection pool exhaustion.

If Stage 2 fails: Immediately revert to Stage 1 weights (5% canary) while
investigating. If cause is unclear within 5 minutes, full abort to 0% canary.

### 3.4 Stage 3 — 50% Canary (20-minute bake)

**Duration**: 20 minutes (bake time)
**Traffic**: 50% canary, 50% stable

Actions:
1. Update Traefik weights to 50% canary / 50% stable.
2. Run sustained load test over 3 minutes at normal traffic volume.
3. Compare aggregate metrics side-by-side (canary vs stable in Grafana).
4. Verify that error distribution between canary and stable is statistically equivalent.
5. Check that all canary-side features are reachable and functioning.
6. Run integration smoke tests through the public entrypoints.
7. Verify COREDB is not under excessive load.

Exit criteria:
- Canary error rate < stable error rate * 1.2 (can be slightly worse, not worse than 20% deviation).
- Canary p95 latency < stable p95 latency * 1.2.
- Sustained load handled without degradation.
- All integration smoke tests pass.
- COREDB resource usage within safe margins.

If Stage 3 fails: Full abort to 0% canary. This stage failure indicates a
significant issue that cannot be investigated in partial traffic.

### 3.5 Stage 4 — 100% Cutover (30-minute post-cutover bake)

**Duration**: 30 minutes (post-cutover monitoring)
**Traffic**: 100% canary (now production), 0% stable (old version)

Actions:
1. Update Traefik weights to 100% new / 0% old.
2. Keep the old (stable) instance running but receiving no traffic for 15 minutes.
3. Monitor all metrics at full production load for 30 minutes.
4. Run full end-to-end test suite against production.
5. Verify all public routes respond correctly (HTTP 200/301 as expected).
6. Verify all AI API routes (LiteLLM, DeepSeek, OpenRouter) return valid responses.
7. Check business metrics (signups, transactions, API usage) are at expected levels.
8. Verify EDGE Nginx logs show correct routing.

Exit criteria:
- All metrics within baseline thresholds for 30 minutes.
- Full end-to-end test suite passes.
- All public routes validated.
- AI API responses valid and timely.
- Business metrics on track.
- No user-reported incidents.

If Stage 4 fails: Revert Traefik weights to 100% old / 0% new. The old instance
is still running and warm, so cutover is nearly instantaneous (under 5 seconds).

### 3.6 Cleanup — Remove Old Version

**When to cleanup**: After at least 2 hours of stable 100% production operation
on the new version.

Actions:
1. Stop the old stable PM2 process or Docker container.
2. Archive old logs.
3. Update `ecosystem.config.js` or `docker-compose.yml` to reflect new state.
4. Tag the release in version control.
5. Close the canary deployment log entry.

**Important**: Always retain the old version's artifacts (Docker image, PM2
backup, config snapshot) for at least 24 hours in case a delayed issue surfaces
that requires rollback to a known-good version.

---

## 4. Health Checks & Validation

### 4.1 Health Check Layers

Each service has three layers of health checks during a canary:

| Layer | Frequency | Purpose |
|-------|-----------|---------|
| **L1 — Traefik health check** | Every 10s | Detect dead instances (stop routing traffic) |
| **L2 — Application health endpoint** | Every 15s | Service self-assessment (DB, Redis, dependencies) |
| **L3 — Synthetic transaction** | Every 60s | End-to-end validation through the public entrypoint |

### 4.2 Health Check Endpoints by Service Type

#### Web Services (Node.js/Python)

```
GET /health
  - Returns 200 if service is healthy
  - Body: { "status": "ok", "version": "x.y.z", "uptime": 12345, "db": "connected", "redis": "connected" }
  - Timeout: 3 seconds
  - Failure: 3 consecutive failures trigger unhealthy state

GET /health/deep
  - Returns 200 after running all dependency checks
  - Includes: database query, Redis ping, upstream service checks
  - Timeout: 10 seconds
  - Used during canary validation (not for routing)
```

#### AI Workers (LiteLLM, OpenClaw, Brain OS)

```
GET /health
  - Returns 200 if worker is alive
  - Body: { "status": "ok", "model_count": 12, "cache_hit_rate": 0.85 }

GET /health/ai
  - Test LiteLLM routing: POST /chat/completions with a small test prompt
  - Verify DeepSeek responds within 5 seconds
  - Verify OpenRouter fallback is configured and reachable
  - Returns 200 on success with response time
```

#### PostgreSQL (COREDB)

```bash
pg_isready -U wheeler -d wheeler_core -t 5
```
Used as a dependency check by application health endpoints.

#### Redis (COREDB)

```bash
redis-cli -h COREDB_TAILSCALE ping
```
Expected response: `PONG`

### 4.3 Canary-Specific Validation Suite

A dedicated validation script (`/opt/wheeler/scripts/canary-validate.sh`) runs
against the canary instance at each stage:

```bash
#!/bin/bash
# canary-validate.sh — Run full canary validation suite
# Usage: canary-validate.sh <CANARY_URL> <STABLE_URL> <SERVICE_NAME>

CANARY_URL="$1"
STABLE_URL="$2"
SERVICE="$3"

# 1. Health check
curl -sf "${CANARY_URL}/health" || exit 1

# 2. Deep health check
curl -sf "${CANARY_URL}/health/deep" || exit 2

# 3. Compare versions
CANARY_VER=$(curl -sf "${CANARY_URL}/health" | jq -r '.version')
STABLE_VER=$(curl -sf "${STABLE_URL}/health" | jq -r '.version')
echo "Canary: ${CANARY_VER}, Stable: ${STABLE_VER}"

# 4. Latency comparison (p95)
# ... (prometheus query comparison)

# 5. Error rate comparison
# ... (prometheus query comparison)

# 6. AI-specific validation (if applicable)
# Test LiteLLM routing
curl -sf -X POST "${CANARY_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' \
  || echo "WARN: AI validation failed"

echo "OK: All canary validations passed"
exit 0
```

### 4.4 AI API Validation

When canarying AI-dependent services (Brain OS, OpenClaw, Voice Agent), verify:

1. **LiteLLM routing**: Send a test prompt to the canary instance. Verify the
   request is routed through LiteLLM to the correct model provider (DeepSeek,
   Anthropic, OpenAI).

2. **DeepSeek responses**: Verify that DeepSeek API responses are valid JSON
   with the expected schema (model, choices, usage).

3. **OpenRouter fallback**: Intentionally cause a LiteLLM routing failure
   (e.g., by using a non-existent model name) and verify that OpenRouter
   fallback is triggered and returns a valid response.

4. **Cache hit verification**: Verify that LiteLLM caching (Redis-backed on
   COREDB) is functional and returning cached responses when expected.

---

## 5. Rollback Triggers & Thresholds

### 5.1 Automated Rollback Triggers

The canary orchestration script (`/opt/wheeler/scripts/canary-orchestrate.sh`)
monitors these metrics and automatically aborts the canary if any threshold is
breached:

| Trigger | Threshold | Measurement Window | Action |
|---------|-----------|-------------------|--------|
| **Error rate spike** | Canary error rate > 2% OR canary error rate > stable * 2x | Rolling 2 minutes | Abort canary immediately |
| **Latency degradation** | Canary p95 latency > stable p95 * 2x | Rolling 3 minutes | Abort canary immediately |
| **Health check failure** | 3 consecutive L1 health check failures | ~30 seconds | Traefik auto-removes canary; abort signaled |
| **Memory leak** | Canary RSS grows > 10% per minute for 5+ minutes | Rolling 5 minutes | Abort at end of stage |
| **Connection pool exhaustion** | COREDB active connections > 80% of max_connections | Rolling 1 minute | Abort canary immediately |
| **Crash loop** | Canary restarts > 3 times in 60 seconds | Rolling 60 seconds | PM2 auto-stops; abort signaled |
| **CPU saturation** | Canary instance CPU > 90% sustained for 2+ minutes | Rolling 2 minutes | Abort at end of stage |
| **Business metric drop** | Successful transaction rate < baseline * 0.9 | Rolling 5 minutes | Human review required |

### 5.2 Manual Rollback Decision Criteria

SRE on-call should evaluate manual rollback when:

- Automated triggers have not fired but the canary instance shows unusual
  behavior (e.g., intermittent timeouts, increased log volume, subtle data
  inconsistencies).
- A user-reported incident coincides with the canary deployment (even if
  not conclusively linked).
- The canary has reached Stage 3 (50%) and any metric is trending in the
  wrong direction, even if thresholds aren't breached yet.
- A security vulnerability is discovered in the canary version.
- A downstream dependency (external API, database) is experiencing issues
  that could be exacerbated by the canary.

### 5.3 Rollback Procedure

```bash
# Step 1: Signal abort to the orchestration script
touch /tmp/canary-abort-flag

# Step 2: Revert Traefik weights to 100% stable
# Update dynamic config or use Traefik API
curl -X PUT http://localhost:8080/api/providers/file \
  -d '{"services":{"wheeler-api-stable":{"weight":100},"wheeler-api-canary":{"weight":0}}}'

# Step 3: Verify traffic is back to stable
tail -f /var/log/traefik/access.log | grep -c canary-port

# Step 4: Stop the canary instance
pm2 stop wheeler-api-canary       # PM2
docker stop wheeler-api-canary    # Docker

# Step 5: Notify stakeholders
# Use the communication template (Section 10)

# Step 6: Log the abort
# Update the canary deployment log
```

---

## 6. Promotion Gates

### 6.1 Gate Types

| Gate | Type | Decision Maker | Description |
|------|------|---------------|-------------|
| **Stage 0 -> 1** | Automated | Script | All pre-flight checks pass |
| **Stage 1 -> 2** | Automated | Script | 5% metrics within thresholds for full bake time |
| **Stage 2 -> 3** | Semi-Automated | Script + Human | 25% metrics within thresholds; SRE acknowledges |
| **Stage 3 -> 4** | Manual | SRE On-Call | 50% metrics within thresholds; SRE approves full cutover |
| **Stay/Cleanup** | Manual | Release Manager | 2+ hours stable at 100%; release manager confirms |

### 6.2 Automated Gate Criteria

For gates that are automated (Stage 0->1, Stage 1->2), the orchestration
script evaluates these conditions:

```bash
# Example gate evaluation pseudo-logic
evaluate_gate() {
  local STAGE=$1

  # Error rate check
  CANARY_ERROR=$(query_prometheus "rate(http_requests_total{instance='canary',status=~'5..'}[5m])")
  STABLE_ERROR=$(query_prometheus "rate(http_requests_total{instance='stable',status=~'5..'}[5m])")
  if (( $(echo "$CANARY_ERROR > 0.02" | bc -l) )); then return 1; fi
  if (( $(echo "$CANARY_ERROR > $STABLE_ERROR * 2" | bc -l) )); then return 1; fi

  # Latency check
  CANARY_P95=$(query_prometheus "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{instance='canary'}[5m]))")
  STABLE_P95=$(query_prometheus "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{instance='stable'}[5m]))")
  if (( $(echo "$CANARY_P95 > $STABLE_P95 * 1.5" | bc -l) )); then return 1; fi

  # Health check
  if ! curl -sf "${CANARY_URL}/health/deep" > /dev/null 2>&1; then return 1; fi

  return 0
}
```

### 6.3 Manual Gate Requirements

For manual gates (Stage 2->3, Stage 3->4, Stay/Cleanup), the following must
be provided:

1. **Metrics dashboard link**: A Grafana snapshot URL comparing canary and
   stable metrics for the relevant time window.
2. **Validation report**: Output of the `canary-validate.sh` script.
3. **SRE sign-off**: A Slack message or PagerDuty note confirming approval.
4. **Stakeholder notification**: Confirmation that the relevant team leads
   have been notified (for revenue-affecting services).

### 6.4 Promotion Command

```bash
# Promote to next stage
/opt/wheeler/scripts/canary-promote.sh <SERVICE_NAME> <CURRENT_STAGE>

# This script will:
#   1. Verify current stage exit criteria
#   2. Update Traefik weights to next stage
#   3. Start monitoring for the new stage's bake time
#   4. Set up abort timer for automated rollback
```

---

## 7. Canary Configuration File Format

### 7.1 Configuration Schema

Each service with canary support has a canary configuration file at
`/opt/wheeler/configs/canary/<service-name>.yml`:

```yaml
# /opt/wheeler/configs/canary/frgcrm-api.yml
# Canary deployment configuration for FRGCRM API

canary:
  # Service identification
  service: frgcrm-api
  display_name: "FRGCRM API"
  server: aiops                                # aiops | edge | coredb

  # Instance configuration
  stable:
    deployment_type: pm2                       # pm2 | docker | nginx_static
    instance_name: frgcrm-api                  # PM2 process name or Docker container name
    port: 8082                                 # Service port
    tailscale_ip: 100.121.230.28              # Tailscale IP of the host

  canary:
    deployment_type: pm2
    instance_name: frgcrm-api-canary
    port: 8083                                 # Alternate port for canary instance
    tailscale_ip: 100.121.230.28
    env_overrides:                             # Environment variables that differ
      LOG_LEVEL: debug                         # Enable debug logging for canary

  # Traffic configuration
  traffic:
    traefik_router: frgcrm-api@file           # Traefik router name
    traefik_entrypoint: websecure
    public_host: api.wheeler.ai
    weights:
      stage_0: { stable: 100, canary: 0 }
      stage_1: { stable: 95, canary: 5 }
      stage_2: { stable: 75, canary: 25 }
      stage_3: { stable: 50, canary: 50 }
      stage_4: { stable: 0, canary: 100 }

  # Bake times per stage (in minutes)
  bake_times:
    stage_0: 5
    stage_1: 10
    stage_2: 15
    stage_3: 20
    stage_4: 30

  # Health check configuration
  health_checks:
    l1_endpoint: /health
    l1_interval_seconds: 10
    l1_timeout_seconds: 3
    l1_failure_threshold: 3

    l2_endpoint: /health/deep
    l2_interval_seconds: 15
    l2_timeout_seconds: 10

    l3_synthetic: true                         # Run synthetic transactions
    l3_interval_seconds: 60

  # Rollback thresholds
  thresholds:
    max_error_rate_percent: 2.0
    max_error_rate_vs_stable_multiplier: 2.0
    max_p95_latency_vs_stable_multiplier: 1.5
    max_memory_growth_percent_per_minute: 10.0
    max_coredb_connection_percent: 80.0
    max_crash_restarts_per_interval: 3
    crash_restart_interval_seconds: 60
    max_cpu_percent_sustained: 90.0

  # Promotion gates
  gates:
    stage_0_to_1: automated
    stage_1_to_2: automated
    stage_2_to_3: semi_automated             # SRE acknowledges
    stage_3_to_4: manual                      # SRE approves
    cleanup: manual                           # Release manager confirms

  # AI-specific validation (if applicable)
  ai_validation:
    enabled: false
    litellm_url: http://127.0.0.1:4049
    test_models:
      - deepseek-chat
      - claude-sonnet-4-20250514
    verify_openrouter_fallback: false

  # Notification channels
  notifications:
    slack_channel: "#canary-deployments"
    pagerduty_service_id: "PXXXXXX"
    on_stage_change: true
    on_abort: true
    on_complete: true

  # Pre-canary actions
  pre_canary:
    - type: snapshot_database
      database: frgcrm
      command: "pg_dump -h ${COREDB_TAILSCALE} -U wheeler frgcrm > /backups/pre-canary-frgcrm-$(date +%s).sql"
    - type: snapshot_pm2
      command: "pm2 save --force"
```

### 7.2 Configuration Validation

The canary config is validated before any deployment begins:

```bash
/opt/wheeler/scripts/canary-validate-config.sh /opt/wheeler/configs/canary/frgcrm-api.yml
```

This checks:
- All required fields are present.
- Ports do not conflict with other services (stable or canary).
- Tailscale IPs are reachable from the EDGE node.
- Traefik router name is valid.
- Health check endpoints are accessible on the stable instance.
- Rollback thresholds are within sane bounds.

---

## 8. Emergency Abort Procedure

### 8.1 When to Use Emergency Abort

Use the emergency abort procedure (skip normal stage reversion) when:

- **SEV1 incident**: A severity-1 incident is declared that may be related to the canary.
- **Security breach**: The canary version contains a known vulnerability.
- **Data corruption**: The canary instance is writing incorrect data to the database.
- **Revenue impact**: A revenue metric drops by more than 5% during the canary.
- **Complete canary failure**: The canary instance crashes and cannot recover.
- **External dependency failure**: A critical third-party API that the canary depends on is down.

### 8.2 Emergency Abort Steps

```
EMERGENCY ABORT — Canary Deployment
====================================

1. STOP TRAFFIC IMMEDIATELY
   ssh edge "cp /opt/traefik/dynamic-canary-rollback.yml /opt/traefik/dynamic.yml"
   # This restores the pre-canary Traefik configuration atomically.

2. VERIFY TRAFFIC RESTORED
   curl -s https://api.wheeler.ai/health | jq '.version'
   # Must return the STABLE version, not the canary version.

3. STOP CANARY INSTANCE
   # PM2:  pm2 stop frgcrm-api-canary
   # Docker: docker stop aiops-frgcrm-api-canary

4. DATABASE CHECK (if data corruption suspected)
   psql -h COREDB_TAILSCALE -U wheeler -d frgcrm -c "SELECT count(*) FROM critical_table;"
   # Compare with pre-canary baseline.

5. NOTIFY STAKEHOLDERS
   # Use EMERGENCY ABORT template (see Section 10)

6. LOG THE INCIDENT
   # Create a post-mortem entry with timeline and root cause

7. DO NOT RETRY
   # Do NOT restart the canary until root cause is identified and fixed.
   # The canary version is quarantined until a post-mortem is completed.

Total target time from decision to full abort: < 30 seconds.
```

### 8.3 Traefik Emergency Rollback Config

Maintain a known-good Traefik dynamic configuration backup at all times:

```bash
# Before any canary: backup current config
cp /opt/traefik/dynamic.yml /opt/traefik/dynamic-pre-canary.yml

# During emergency abort: restore it
cp /opt/traefik/dynamic-pre-canary.yml /opt/traefik/dynamic.yml

# Traefik picks up the change within 2 seconds (watch mode)
```

---

## 9. Server-Specific Procedures

### 9.1 EDGE Node (Hostinger — 187.77.148.88)

**Services eligible for canary**: Nginx static sites, Traefik itself, frontend
dashboards served by Nginx.

**Canary method for Nginx static sites**:
1. Deploy new site files to `/opt/wheeler/sites/<service>-canary/`.
2. Update Nginx config to add a canary upstream on an alternate internal port.
3. Use `nginx -t && nginx -s reload` to apply the change.
4. Validate routes via curl from EDGE localhost.
5. After cutover, swap symlink: `ln -sfn <service>-canary <service>`.

**Canary method for Traefik**: Traefik itself is canaried by deploying a new
Docker container on an alternate management port, validating the health check,
and then swapping the public port binding.

**Alert**: EDGE Nginx reload is not atomic — there may be a sub-second gap.
During canary weight changes, use Traefik exclusively (not Nginx) for traffic
splitting to avoid gaps.

### 9.2 AIOPS Node (Hetzner — 5.78.140.118)

**Services eligible for canary**: All PM2 apps (API services, AI workers,
orchestration), Docker containers (Langflow, Superset, RavynAI, Prediction
Radar).

**PM2 canary procedure**:
```bash
# 1. Start canary instance on alternate port
pm2 start ecosystem.canary.config.js --only frgcrm-api-canary

# 2. Verify canary is healthy
curl http://127.0.0.1:8083/health

# 3. Update Traefik weights on EDGE node
ssh edge "/opt/wheeler/scripts/traefik-weight.sh frgcrm-api 95 5"

# 4. Monitor via PM2
pm2 monit frgcrm-api-canary

# 5. After each stage promotion/demotion, adjust weights
ssh edge "/opt/wheeler/scripts/traefik-weight.sh frgcrm-api 75 25"

# 6. On full cutover, stop old stable and rename canary
pm2 stop frgcrm-api
pm2 restart frgcrm-api-canary --name frgcrm-api -- --port 8082
```

**Docker canary procedure**:
```bash
# 1. Start canary container on alternate port
docker compose -f docker-compose.canary.yml up -d frgcrm-api-canary

# 2. Verify canary is healthy
curl http://127.0.0.1:8083/health

# 3. Update Traefik weights (same as PM2)

# 4. On full cutover, stop old and rename canary
docker stop aiops-frgcrm-api
docker rename aiops-frgcrm-api-canary aiops-frgcrm-api
```

### 9.3 COREDB Node (Hetzner — 5.78.210.123)

**Services eligible for canary**: Schema migrations (not canaried — applied in
advance), Redis configuration changes, MinIO bucket policy changes.

**COREDB changes are pre-applied**: Any database schema migration must be
fully applied and verified on COREDB BEFORE the canary deployment begins. The
canary instance uses the already-migrated schema. Backward-incompatible schema
changes must be applied in a separate migration window with the application
already prepared for both old and new schemas (dual-write pattern).

---

## 10. Canary Log Template

### 10.1 Canary Deployment Log

Every canary deployment must be logged in
`/opt/wheeler/logs/canary/<service>-<date>-<start-time>.log`:

```
================================================================================
CANARY DEPLOYMENT LOG
================================================================================
Service:        frgcrm-api
Canary version: v2.3.1 (commit: a1b2c3d)
Stable version: v2.3.0 (commit: e4f5g6h)
Start time:     2026-05-23 14:00:00 UTC
Operator:       ops-user@wheeler.ai
Canary config:  /opt/wheeler/configs/canary/frgcrm-api.yml

--- STAGE 0: PRE-FLIGHT ---
14:00:00  Canary deployed on port 8083
14:00:05  Health check: PASS (200 OK)
14:00:10  Deep health check: PASS
14:00:15  Resource baseline: CPU 12%, MEM 450MB, FDs 128
14:00:20  DB connectivity: PASS
14:00:25  Redis connectivity: PASS
14:00:30  Log check: 0 errors, 2 warnings (expected: deprecated API notice)
14:02:00  2-min log stability: PASS
14:03:00  Stage 0 exit criteria: ALL MET
14:03:00  GATE: automated promotion to Stage 1 — APPROVED

--- STAGE 1: 5% CANARY ---
14:03:00  Traefik weights updated: stable=95, canary=5
14:03:10  Traffic verified flowing to canary (8 req/s)
14:08:00  5-min check: canary error rate 0.1%, stable error rate 0.1%
14:13:00  10-min check: canary error rate 0.08%, stable error rate 0.09%
14:13:00  Latency: canary p95=45ms, stable p95=42ms (within 1.5x)
14:13:00  Memory: canary 452MB, stable 448MB (no leak)
14:13:00  Stage 1 exit criteria: ALL MET
14:13:00  GATE: automated promotion to Stage 2 — APPROVED

--- STAGE 2: 25% CANARY ---
14:13:00  Traefik weights updated: stable=75, canary=25
14:14:00  Burst load test: canary handled 200 req/s peak without errors
14:21:00  8-min check: canary error rate 0.05%, stable error rate 0.07%
14:28:00  15-min check: all metrics within thresholds
14:28:00  DB connections: canary=12, stable=15 (safe)
14:28:00  Stage 2 exit criteria: ALL MET
14:28:00  GATE: semi-automated promotion to Stage 3 — SRE acknowledged

--- STAGE 3: 50% CANARY ---
14:28:00  Traefik weights updated: stable=50, canary=50
14:31:00  Sustained load test: 3 min at normal volume — PASS
14:38:00  10-min check: error rates within threshold
14:48:00  20-min check: all metrics within thresholds
14:48:00  COREDB connections: 45/100 (45%)
14:48:00  Stage 3 exit criteria: ALL MET
14:48:00  GATE: manual promotion to Stage 4 — SRE APPROVED (approver: oncall-sre)

--- STAGE 4: 100% CUTOVER ---
14:48:00  Traefik weights updated: stable=0, canary=100
14:48:05  All traffic flowing to new version
14:49:00  End-to-end tests: ALL PASS
14:49:30  Public route validation: ALL PASS
14:50:00  AI API validation: LiteLLM OK, DeepSeek OK, OpenRouter OK
14:53:00  5-min post-cutover: metrics stable
15:03:00  15-min post-cutover: metrics stable
15:18:00  30-min post-cutover: metrics stable
15:18:00  Stage 4 exit criteria: ALL MET

--- CLEANUP ---
17:18:00  2-hour stability confirmed. Old stable stopped.
17:18:05  Old stable PM2 process: pm2 stop frgcrm-api (old)
17:18:10  Logs archived to /opt/wheeler/logs/archive/frgcrm-api-v2.3.0/
17:18:15  Release tagged: v2.3.1 in git
17:18:20  24-hour retention snapshot created

================================================================================
CANARY COMPLETED SUCCESSFULLY
================================================================================
Duration: 3h 18m
Final version: v2.3.1
Issues encountered: None
```

### 10.2 Incident/Abort Log Template

```
================================================================================
CANARY ABORT LOG — EMERGENCY
================================================================================
Service:        frgcrm-api
Canary version: v2.3.1
Stable version: v2.3.0
Abort time:     2026-05-23 14:35:00 UTC
Operator:       oncall-sre@wheeler.ai
Abort trigger:  Error rate threshold exceeded at Stage 2 (canary: 3.2%, stable: 0.1%)

--- ABORT SEQUENCE ---
14:35:00  Abort flag set
14:35:02  Traefik weights reverted: stable=100, canary=0
14:35:03  Traffic verified back to stable
14:35:05  Canary instance stopped
14:35:10  Database integrity check: PASS (no data corruption)
14:36:00  Stakeholders notified (#canary-deployments, #incidents)

--- ROOT CAUSE (to be filled post-mortem) ---
Suspected: Memory leak in new connection pool handling
Evidence: Canary RSS grew from 450MB to 1.4GB over 20 minutes

--- POST-MORTEM REFERENCE ---
Incident ticket: INC-2026-05-23-001
Post-mortem scheduled: 2026-05-24 10:00 UTC

================================================================================
CANARY ABORTED
================================================================================
```

### 10.3 Stakeholder Communication Templates

**Canary start notification**:
```
[CANARY START] frgcrm-api v2.3.0 -> v2.3.1
Start: 14:00 UTC | Operator: ops-user
Stages: 5% (10m) -> 25% (15m) -> 50% (20m) -> 100% (30m)
Expected completion: ~15:30 UTC
Dashboard: https://grafana.wheeler.ai/d/canary-overview
Abort contact: @oncall-sre in #canary-deployments
```

**Stage promotion notification**:
```
[CANARY PROMOTE] frgcrm-api: Stage 1 -> Stage 2 (25% traffic)
5% metrics: error 0.08%, p95 45ms — all within thresholds
Next gate: Automated (Stage 2 -> 3)
Estimated next promotion: 14:28 UTC
```

**Canary completion notification**:
```
[CANARY COMPLETE] frgcrm-api: v2.3.1 fully rolled out
Duration: 3h 18m | Issues: 0 | Rollbacks: 0
Production version is now v2.3.1
Old version (v2.3.0) will be cleaned up at 17:18 UTC
```

**Canary abort notification**:
```
[CANARY ABORT — EMERGENCY] frgcrm-api v2.3.1
Aborted at Stage 2 due to error rate threshold breach (3.2% vs 0.1% stable)
Traffic fully restored to v2.3.0 at 14:35 UTC
Duration: 35 minutes (aborted)
Incident: INC-2026-05-23-001
Root cause investigation in progress.
```

---

## Appendix A — Monitoring Dashboard Setup

A Grafana dashboard (`Canary Overview`) should be set up before any canary
deployment. The dashboard must show side-by-side comparisons of:

- Request rate (canary vs stable)
- Error rate (canary vs stable)
- p50, p95, p99 latency (canary vs stable)
- CPU usage (canary vs stable)
- Memory usage (canary vs stable)
- COREDB active connections
- COREDB query throughput
- Redis memory usage and hit rate
- LiteLLM cache hit rate (if applicable)
- Business transaction success rate

## Appendix B — Pre-Canary Checklist

Before starting any canary deployment:

- [ ] All CI/CD pipeline tests passing (unit, integration, e2e).
- [ ] Staging environment validated with the canary version.
- [ ] Database migrations applied and verified on COREDB.
- [ ] Canary configuration file created and validated.
- [ ] Traefik dynamic config backup created.
- [ ] PM2 process list snapshot created (`pm2 save --force`).
- [ ] Docker compose state backed up.
- [ ] Grafana canary dashboard configured.
- [ ] On-call SRE notified and available.
- [ ] Rollback plan reviewed by operator.
- [ ] Pre-canary snapshot of affected databases taken.

## Appendix C — Post-Canary Cleanup Checklist

After successful cleanup (2+ hours stable):

- [ ] Old PM2 process stopped and removed from `pm2 save`.
- [ ] Old Docker container and image removed.
- [ ] Old logs archived to cold storage.
- [ ] Release tagged in version control.
- [ ] Canary configuration file archived (not deleted — for audit).
- [ ] Canary deployment log reviewed and signed off.
- [ ] Grafana canary dashboard snapshot saved.
- [ ] Post-deployment monitoring alert thresholds adjusted for new version.
- [ ] 24-hour retention snapshot confirmed.
