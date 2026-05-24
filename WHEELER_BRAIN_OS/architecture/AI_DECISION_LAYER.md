# Wheeler Brain OS — AI Decision Layer

## 1. Overview

The AI Decision Layer transforms raw ecosystem telemetry into actionable intelligence. It sits above the observability stack and below the executive console, applying AI models to detect anomalies, predict failures, recommend optimizations, and eventually make autonomous decisions within bounded authority.

### The Core Loop

```
Observe → Analyze → Recommend → Decide → Act → Verify → Learn
   ↑                                                          │
   └──────────────────────────────────────────────────────────┘
```

---

## 2. Decision Architecture

### 2.1 Layer Stack

```
┌─────────────────────────────────────────────────────────┐
│                 EXECUTIVE DECISION INTERFACE              │
│   CEO Console · War Room · Discord Alerts · Claude Code  │
├─────────────────────────────────────────────────────────┤
│                 RECOMMENDATION ENGINE                     │
│   Prioritized, contextualized, risk-scored suggestions   │
├─────────────────────────────────────────────────────────┤
│                 ANALYSIS MODELS                           │
│   Anomaly Detection · Trend Analysis · Pattern Mining    │
├─────────────────────────────────────────────────────────┤
│                 PREDICTION MODELS                         │
│   Failure Prediction · Resource Forecasting · Cost Model │
├─────────────────────────────────────────────────────────┤
│                 DATA FUSION LAYER                         │
│   Metrics + Logs + Events + Graph + History              │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Decision Authority Levels

```
Level 0 — ADVISORY (current):
  AI produces recommendations → Human operator decides → Human executes
  Example: "COREDB disk at 85%, recommend cleanup of old backups"

Level 1 — ASSISTED (near-term):
  AI recommends + drafts execution plan → Human approves → AI executes
  Example: "3 containers using :latest. Pin to current digest? [APPROVE]"

Level 2 — SUPERVISED (medium-term):
  AI decides + executes → Human reviews within time window → Override if needed
  Example: Auto-restart unhealthy container, notify operator

Level 3 — AUTONOMOUS (long-term, bounded):
  AI decides + executes within defined safety boundaries → Human notified
  Example: Auto-scale resources, auto-rollback failed deploys
```

---

## 3. Anomaly Detection Engine

### 3.1 Detection Models

```
MODEL 1 — Statistical Threshold:
  Method: Rolling Z-score on metric time series
  Data: Prometheus metrics (15s scrape interval)
  Alert: Z-score > 3.0 for 3 consecutive samples
  Examples:
    - Container memory > 2σ above 7-day baseline
    - API latency p99 > 3σ above hourly median
    - PM2 restart rate spike

MODEL 2 — Seasonal Decomposition:
  Method: STL decomposition (trend + seasonal + residual)
  Data: Prometheus 30-day history
  Alert: Residual component > threshold (anomaly after removing seasonality)
  Examples:
    - Traffic drop that's not explained by time-of-day pattern
    - Database connections growing against diurnal pattern

MODEL 3 — Multi-Metric Correlation:
  Method: PCA on metric vectors, monitor reconstruction error
  Data: All Prometheus metrics for a service
  Alert: Reconstruction error spike (metrics moved in unexpected ways)
  Examples:
    - CPU up but request rate flat = possible crypto-mining or infinite loop
    - Memory up but connections flat = possible memory leak

MODEL 4 — Log Pattern Anomaly:
  Method: Log clustering (drain3 or similar), alert on new/unseen clusters
  Data: Loki log streams
  Alert: New log pattern appears that wasn't in training corpus
  Examples:
    - New ERROR pattern after deploy = regression
    - Connection refused pattern appearing = dependency failure
```

### 3.2 Anomaly Scoring

```
Each anomaly receives a composite score (0.0 - 1.0):

score = w1 * statistical_significance
      + w2 * blast_radius (from ecosystem graph)
      + w3 * trend_direction (accelerating = higher)
      + w4 * historical_precedent (has this happened before?)
      + w5 * business_impact (revenue system = higher weight)

Thresholds:
  score < 0.3 → Log only
  score 0.3-0.6 → Discord #monitoring
  score 0.6-0.8 → Discord #alerts + Pager
  score > 0.8 → Discord #war-room + Incident declared
```

---

## 4. Failure Prediction Engine

### 4.1 Predictive Models

```
MODEL 1 — Resource Exhaustion Forecast:
  Input: 30-day Prometheus history for cpu, memory, disk, file descriptors
  Method: Linear regression + exponential smoothing
  Output: "Disk full in ~14 days at current growth rate"
          "Memory leak of ~5MB/hour, OOM in ~4 days"

MODEL 2 — Crash Loop Predictor:
  Input: PM2 restart count, interval between restarts, memory at crash
  Method: Pattern matching against known crash signatures
  Output: "Process X showing pre-crash pattern (memory cliff at 480MB)"
          "Restart interval decreasing: 30min→15min→8min (accelerating)"

MODEL 3 — Dependency Health Cascade:
  Input: Ecosystem graph dependencies + health status of each node
  Method: Bayesian network propagation
  Output: "If COREDB PostgreSQL degrades, blast radius = 12 services"
          "Current weakest link: LiteLLM (single instance, 0 redundancy)"

MODEL 4 — Deployment Risk Scorer:
  Input: Changed files, dependency graph, historical deploy outcomes
  Method: Random forest classifier trained on deploy success/failure logs
  Output: "This deploy touches 3 critical paths. Risk: HIGH (78%)"
          "Recommend: deploy during low-traffic window, have rollback ready"
```

### 4.2 Predictive Alerting

```
Instead of:  "COREDB disk > 90%" (reactive, already critical)
We want:     "COREDB disk trending to 90% in ~14 days" (proactive)

Lead time targets:
  Resource exhaustion: 7 days warning
  Crash prediction: 30 minutes warning
  Dependency cascade: Real-time (as each domino falls)
  Cost anomaly: 24 hours warning
```

---

## 5. Recommendation Engine

### 5.1 Recommendation Types

```
TYPE 1 — OPTIMIZATION:
  "Pin 7 containers from :latest to current digest"
  "Consolidate 3 Redis instances into COREDB Redis (saves 200MB RAM)"
  "Remove 3 stale /opt/opt/apps/ duplicate directories"

TYPE 2 — HARDENING:
  "3 containers missing cap_drop: ALL — apply standard hardening"
  "COREDB has no UFW — apply tailscale0-only ruleset"
  "backup-verification PM2 process is stopped — restart or document exception"

TYPE 3 — COST:
  "COREDB using only 8% RAM (2.3/30GB) — consider downsizing instance"
  "4 overlapping uptime-kuma instances — consolidate to 2"

TYPE 4 — RELIABILITY:
  "LiteLLM is single point of failure for 9 agents — add fallback model routing"
  "No automated backup for COREDB PostgreSQL — implement daily pg_dump"
  "wheeler-ecosystem has no git remote — create and push"

TYPE 5 — SECURITY:
  "DEEPSEEK_API_KEY last rotated >30 days ago — schedule rotation"
  "node-exporter on COREDB bound to 0.0.0.0:9100 — restrict to Tailscale IP"
```

### 5.2 Recommendation Prioritization

```
PRIORITY = f(impact, urgency, effort, risk)

impact:   How many services/revenue affected? (from ecosystem graph)
urgency:  Is this actively degrading or just suboptimal?
effort:   How many commands/minutes to implement?
risk:     What's the blast radius if the fix goes wrong?

Sort by:  PRIORITY descending
Display:  Top 5 with "Do this now" / "Do this week" / "Consider"
```

---

## 6. Drift Detection System

### 6.1 Desired State vs. Actual State

```
DESIRED STATE (declared in governance rules):
  - All containers: cap_drop ALL, mem_limit, cpus, 127.0.0.1 binds
  - All containers: healthcheck defined
  - All images: pinned to digest
  - All secrets: in .env files, none in compose
  - All admin panels: behind nginx basic auth

ACTUAL STATE (discovered every 60s):
  - docker inspect → actual cap_drop, mem_limit, cpus, port binds
  - docker ps → actual healthcheck, image tags
  - grep -r "password\|secret\|key" docker-compose.yml → hardcoded secrets
  - nginx -T → auth directives

DRIFT = ACTUAL ∖ DESIRED

Each drift item is:
  1. Logged to audit trail
  2. Scored by severity
  3. Queued for auto-remediation (Level 1-2) or operator notification (Level 0)
```

### 6.2 Drift Categories

```
CRITICAL DRIFT (auto-remediate or page immediately):
  - Container published to 0.0.0.0 (security boundary violation)
  - Secret found hardcoded in compose file
  - cap_drop ALL removed from a container

HIGH DRIFT (notify, remediate within 1 hour):
  - :latest tag appears on a production container
  - Container missing healthcheck
  - Container exceeding mem_limit

MEDIUM DRIFT (notify, remediate within 24 hours):
  - Non-standard cap_add without documentation
  - Container running as root without documented exception
  - Missing resource limits (unlimited mem/cpu)

LOW DRIFT (weekly review):
  - Image version behind latest secure version
  - Log retention exceeding policy
  - Non-critical CronJob failing
```

---

## 7. Cost Optimization Engine

### 7.1 Current Resource Utilization

```
AIOPS (Hetzner CPX51, 16 CPU, 30GB RAM, 338GB disk):
  RAM:  14GB used / 30GB total (47%) — healthy headroom
  Disk: 59GB used / 338GB total (19%) — significant headroom
  CPU:  Not measured in detail — needs baselining

COREDB (Hetzner, 16 CPU, 30GB RAM, 338GB disk):
  RAM:  2.3GB used / 30GB total (8%) — dramatically underutilized
  Disk: 15GB used / 338GB total (5%) — dramatically underutilized
  CPU:  Not measured in detail — needs baselining
```

### 7.2 Optimization Recommendations

```
IMMEDIATE (no risk):
  - COREDB: No action needed. Underutilization is intentional (database server
    should have headroom for spikes, replication, future growth)

MEDIUM-TERM (evaluate):
  - Consider moving prediction-radar workers from COREDB back to AIOPS
    to consolidate compute (but keep DB on COREDB for isolation)
  - Evaluate if AIOPS needs 30GB or if 16GB would suffice (currently 47% used,
    but agents + containers grow over time)

MONITORING:
  - Track cost per container per month
  - Track cost per agent per month
  - Alert if any resource crosses 80% sustained
```

---

## 8. Learning Loop

### 8.1 Feedback Collection

```
Every decision outcome is recorded:
  - Recommendation → Accepted/Rejected/Modified → Outcome → Re-evaluation

This builds a training corpus for:
  - Which recommendations are most valuable (operator accepts them)
  - Which predictions were accurate (did the predicted failure occur?)
  - Which auto-remediations worked (did the fix resolve the issue?)
```

### 8.2 Model Improvement Pipeline

```
Weekly:
  1. Evaluate prediction accuracy (predicted vs actual failures)
  2. Retrain anomaly detection baselines (rolling 30-day window)
  3. Update blast radius maps (ecosystem graph always current)
  4. Prune stale recommendations (already implemented or no longer relevant)
```

---

## 9. Integration with Agent Fleet

### 9.1 Agent Decision Inputs

```
ecosystem-guardian:    Supplies real-time state for drift detection
horizon-agent-svc:     Supplies external threat/opportunity signals
prediction-radar-agent: Supplies market context for cost decisions
design-agent-svc:      Supplies architecture optimization proposals

The AI Decision Layer consumes all agent outputs and synthesizes
cross-domain recommendations that no single agent can produce alone.
```

### 9.2 Agent Decision Outputs

```
AI Decision Layer publishes prioritized recommendations to:
  → war-room-server (incident context)
  → CEO Console (executive view)
  → Discord (operator alerts)
  → Claude Code skills (execution interface)

Agents receive decisions as structured events via event-bus-relay:
  { "type": "recommendation", "priority": "high", "action": "pin_images", ... }
```

---

## 10. Safety Constraints

```
1. NO AUTONOMOUS DESTRUCTIVE ACTIONS
   - Never: docker rm, pm2 delete, rm -rf, DROP TABLE
   - These always require human approval regardless of confidence

2. BOUNDED AUTONOMY
   - Auto-restart: allowed (already normal Docker/PM2 behavior)
   - Auto-scale: allowed within defined min/max
   - Auto-rollback: allowed if confidence >95% and blast radius <3 services

3. HUMAN-IN-THE-LOOP BY DEFAULT
   - All Level 0-1 decisions require explicit approval
   - Level 2 decisions have a 5-minute override window
   - Level 3 decisions are logged and reversible

4. KILL SWITCH
   - /slay --halt-autonomy stops all automated decision-making
   - All agents return to advisory-only mode
```

---

*End of AI Decision Layer Design*
