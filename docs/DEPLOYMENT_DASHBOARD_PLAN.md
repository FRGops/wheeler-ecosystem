# Deployment Dashboard Plan

**Version:** 1.0
**Date:** 2026-05-23
**Owner:** Platform Engineering / Operations
**Servers:** EDGE (Hostinger / 187.77.148.88), AIOPS (Hetzner / 5.78.140.118), COREDB (Hetzner / 5.78.210.123)

---

## 1. Dashboard Purpose and Audience

### Executive Summary

The Deployment Dashboard serves as the single pane of glass for all deployment-related observability across the three-server infrastructure. It consolidates real-time deployment state, historical trends, health metrics, and alerting into a unified interface, eliminating the need for operators to SSH into individual servers or consult multiple disjointed tools.

### Audience Segments and Their Needs

| Audience | Primary Questions | Critical Widgets | Refresh Tolerance |
|---|---|---|---|
| **Ops Team** | "What is running where? Is anything degraded? Who deployed last?" | Current Release Overview, Server Deployment State, Active Alerts | Near-real-time (less than 30s) |
| **Developers** | "Did my build pass? Are my tests green? Is my service healthy post-deploy?" | Build/Test Status, Deployment History Timeline, AI Deployment Health | Near-real-time for CI, 1 min for deployment state |
| **Management** | "How often do we deploy? What is our success rate? How reliable are we?" | Deployment History Timeline (sparklines), Rollback History, success rate metrics | Hours to days (trend data) |
| **SRE / On-Call** | "Is there an active incident? What just changed? How do I roll back?" | Unhealthy Deploys / Active Alerts, Rollback History, Current Release Overview | Real-time (less than 15s) |

### Access Control

- **Read-only:** Developers, Management (view dashboard, no actions)
- **Operator:** Ops Team (view dashboard, acknowledge alerts, trigger rollbacks from dashboard)
- **Admin:** Platform Engineering (full access including dashboard configuration, threshold tuning, data source management)

### Non-Goals (Out of Scope for v1)

- Editing deployment configurations from the dashboard
- Triggering new deployments (that remains in CI/CD pipeline)
- ChatOps integration (Slack bot commands deferred to v2)
- Cost analytics / cloud billing integration
- End-user traffic analytics (separate analytics dashboard)

---

## 2. Dashboard Layout

### Primary Layout: 3x3 Grid (1920x1080 target resolution)

```
+------------------------------------------------------------------------------------------------------+
|  HEADER BAR: [Logo] Deployment Dashboard  |  Last Refreshed: 14:32:05 UTC  |  [gear Settings] [bell Alerts: 2] |
|  ENV TABS: [ALL] [EDGE] [AIOPS] [COREDB]                                                             |
+------------------------------------------------------------------------------------------------------+
|                                          |                               |                            |
|  +------------------------------------+  +-----------------------------+  +--------------------------+ |
|  |                                    |  |                             |  |                          | |
|  |  1. CURRENT RELEASE OVERVIEW       |  |  2. DEPLOYMENT HISTORY      |  |  3. ROLLBACK HISTORY     | |
|  |  (span: 2 rows)                    |  |     TIMELINE                |  |                          | |
|  |                                    |  |                             |  |                          | |
|  |  Server | Service | Version | Tag  |  |  Deploy Frequency (7 days)  |  |  Date       Service Reason| |
|  |  -------+---------+---------+------|  |  (sparkline)                |  |  ---------- ------- ------| |
|  |  EDGE   | api     | v2.4.1  | a3f  |  |  Success Rate: 94.3%       |  |  2026-05-22 api     cfg  | |
|  |  EDGE   | web     | v1.9.0  | b7c  |  |                             |  |  2026-05-20 worker  bug  | |
|  |  AIOPS  | litellm | v0.8.2  | f1a  |  |  2026-05-23 14:28 pass api  |  |  2026-05-18 api     perf | |
|  |  AIOPS  | worker  | v3.2.0  | d4e  |  |  2026-05-23 13:01 pass web  |  |                          | |
|  |  COREDB | db      | v5.1.3  | e2f  |  |  2026-05-23 11:45 fail wrkr |  |  Rollback Rate: 5.7%     | |
|  |  COREDB | cache   | v2.0.0  | a1b  |  |  2026-05-22 22:10 pass api  |  |  Mean Recovery: 4.2 min   | |
|  +------------------------------------+  |  ... (scrollable, 50 rows)  |  +--------------------------+ |
|                                          +-----------------------------+                            |
|                                          |                               |                            |
|                                          +-------------------------------+  +--------------------------+ |
|                                          |                               |  |                          | |
|                                          |  4. UNHEALTHY DEPLOYS        |  |  5. PENDING MIGRATIONS   | |
|                                          |     / ACTIVE ALERTS           |  |                          | |
|                                          |                               |  |                          | |
|                                          |  warning CRITICAL: AIOPS      |  |  Migration     DB   Risk  | |
|                                          |    worker error rate 8.2%     |  |  ----------------------- | |
|                                          |    (SLA threshold: 5%)        |  |  add_user_idx  core MED  | |
|                                          |    Since: 14:15 UTC          |  |  add_audit_tbl core LOW  | |
|                                          |                               |  |  alter_pmt_tbl fin  HIGH | |
|                                          |  warning WARNING: EDGE api    |  |                          | |
|                                          |    Latency p95 2.8s           |  |  Last Applied:           | |
|                                          |    (SLA threshold: 2s)        |  |  2026-05-23 10:00 (a3f)  | |
|                                          |    Since: 12:00 UTC          |  |                          | |
|                                          |                               |  |                          | |
|                                          |  RESOLVED (last 24h): 3      |  |                          | |
|                                          +-------------------------------+  +--------------------------+ |
|                                          |                               |                            |
+------------------------------------------------------------------------------------------------------+
|                                          |                               |                            |
|  +------------------------------------+  +-----------------------------+  +--------------------------+ |
|  |                                    |  |                             |  |                          | |
|  |  6. SERVER DEPLOYMENT STATE        |  |  7. BUILD / TEST STATUS     |  |  8. AI DEPLOYMENT HEALTH | |
|  |                                    |  |                             |  |                          | |
|  |  EDGE (Hostinger)                  |  |  Service  Status   Cov%     |  |  LiteLLM: green Healthy   | |
|  |  +--------------------------+      |  |  ---------------------     |  |  DeepSeek: green OK       | |
|  |  | CPU [||||....] 12%        |      |  |  api      pass    87%     |  |  OpenRouter: green Standby| |
|  |  | RAM [||||||..] 58%        |      |  |  web      pass    72%     |  |                          | |
|  |  | Disk[|||||||.] 71%        |      |  |  litellm  pass    65%     |  |  Latency p95: 1.2s        | |
|  |  | Uptime: 34d 12h          |      |  |  worker   fail    --      |  |  Tokens Today: 847,231    | |
|  |  +--------------------------+      |  |  db       run     --      |  |  Error Rate: 0.3%         | |
|  |                                    |  |                             |  |  Circuit Breaker: CLOSED  | |
|  |  AIOPS (Hetzner)                   |  |  Last Run: 2026-05-23 14:15 |  |  Failover Count: 0        | |
|  |  +--------------------------+      |  +-----------------------------+  |                          | |
|  |  | CPU [|||||...] 45%        |      |                                    |  Model Availability:      | |
|  |  | RAM [|||||||.] 62%        |      |                                    |  deepseek-chat    green   | |
|  |  | Disk[||||....] 38%        |      |                                    |  deepseek-reason  green   | |
|  |  | Uptime: 34d 12h          |      |                                    |  openai/gpt-4o    green   | |
|  |  +--------------------------+      |                                    +--------------------------+ |
|  |                                    |                                                               |
|  |  COREDB (Hetzner)                  |                                                               |
|  |  +--------------------------+      |                                                               |
|  |  | CPU [|||.....] 22%        |      |                                                               |
|  |  | RAM [||||||||] 78%        |      |                                                               |
|  |  | Disk[|||||...] 52%        |      |                                                               |
|  |  | Uptime: 34d 12h          |      |                                                               |
|  |  +--------------------------+      |                                                               |
|  +------------------------------------+                                                               |
|                                                                                                      |
+------------------------------------------------------------------------------------------------------+
|  FOOTER: Version 1.0  |  Data Sources: PM2, Docker, Prometheus, GitHub Actions, LiteLLM  |  API Status: green |
+------------------------------------------------------------------------------------------------------+
```

### Responsive Layout Fallbacks

| Viewport | Layout |
|---|---|
| 1920px+ | Full 3x3 grid, all panels visible |
| 1366-1919px | 2-column layout, panels stack in 2 columns |
| 768-1365px | Single column, panels stack vertically |
| Less than 768px (mobile) | Only Current Release + Active Alerts visible; tap to expand others |
| Terminal (TUI) | 2-column layout with tab cycling between panel groups |

---

## 3. Panel Specifications

### Panel A: Current Release Overview

**Purpose:** At-a-glance answer to "What version of everything is deployed and is it healthy?"

**Data Schema:**
```json
{
  "server": "string (EDGE | AIOPS | COREDB)",
  "service": "string (api | web | litellm | worker | db | cache)",
  "version": "string (Semantic version, e.g. v2.4.1)",
  "commit_hash": "string (short hash, e.g. a3f2b1c)",
  "commit_full": "string (full 40-char SHA)",
  "deploy_timestamp": "ISO8601",
  "deployed_by": "string (GitHub username or CI actor)",
  "deploy_method": "string (pm2 | docker | systemd | manual)",
  "health_status": "string (healthy | degraded | unhealthy | deploying | unknown)",
  "health_detail": "string (human-readable status message)",
  "pid": "number or null",
  "uptime_seconds": "number",
  "restart_count": "number (since last deploy)"
}
```

**Data Sources (in priority order):**
1. PM2 API (`pm2 jlist`) on each server -- gives PID, uptime, restart count, status
2. Git tags on each server (`git describe --tags --always`) -- gives version and commit hash
3. `/var/log/wheeler/deploy/latest.json` -- structured deploy log written by CI on successful deploy
4. Health check endpoint on each service (`GET /health`) -- returns JSON with version, uptime, dependency statuses

**Refresh Interval:** 30 seconds

**Color Coding:**

| Status | Color | CSS Class | Icon |
|---|---|---|---|
| healthy | Green (#22c55e) | `.status-healthy` | Circle checkmark |
| deploying | Yellow (#eab308) | `.status-deploying` | Spinner animation |
| degraded | Orange (#f97316) | `.status-degraded` | Warning triangle |
| unhealthy | Red (#ef4444) | `.status-unhealthy` | Exclamation circle |
| unknown | Gray (#6b7280) | `.status-unknown` | Question mark |

**Interactions:**
- Click a row to expand and see: recent deploy history for that service, raw health check response JSON, link to service logs
- Hover over commit hash to see full commit message and link to GitHub commit
- Filter by server using the environment tabs in the header
- Sort by any column (server, service, version, status, uptime)

**Data Collection Implementation (Conceptual Python agent):**
```python
# Runs on each server, pushes to aggregator
import json, subprocess, time, os

def collect_current_release():
    result = {}
    # PM2 process list
    pm2_output = subprocess.run(["pm2", "jlist"], capture_output=True, text=True)
    processes = json.loads(pm2_output.stdout)
    for proc in processes:
        name = proc["name"]
        result[name] = {
            "status": proc["pm2_env"]["status"],
            "pid": proc["pid"],
            "uptime_seconds": int(time.time() - proc["pm2_env"]["pm_uptime"] / 1000),
            "restart_count": proc["pm2_env"]["restart_time"],
            "version": proc.get("axm_monitor", {}).get("version", "unknown"),
        }
    # Git tags
    for service_dir in ["/opt/wheeler/api", "/opt/wheeler/web", "/opt/wheeler/workers"]:
        if os.path.isdir(service_dir):
            tag = subprocess.run(
                ["git", "describe", "--tags", "--always"],
                capture_output=True, text=True, cwd=service_dir
            )
            # Merge version info into result
    return result
```

---

### Panel B: Deployment History Timeline

**Purpose:** Chronological log of all deployments, success/failure status, and trend metrics.

**Data Schema:**
```json
{
  "id": "string (UUID)",
  "timestamp": "ISO8601",
  "service": "string",
  "server": "string (EDGE | AIOPS | COREDB)",
  "version_from": "string",
  "version_to": "string",
  "commit_from": "string",
  "commit_to": "string",
  "deployed_by": "string",
  "trigger": "string (manual | ci | rollback)",
  "duration_seconds": "number",
  "status": "string (success | failed | rolled_back | aborted)",
  "error_message": "string or null",
  "affected_services": ["string array"],
  "rollback_triggered": "boolean",
  "log_file_path": "string (path to full deploy log on server)"
}
```

**Data Source:** `/var/log/wheeler/deploy/*.json` on each server. One JSON file per deployment, named `{timestamp}_{service}_{status}.json`.

**Log File Format (example):**
```json
{
  "deploy_id": "dpl_a1b2c3d4",
  "timestamp": "2026-05-23T14:28:05Z",
  "service": "api",
  "server": "EDGE",
  "version_from": "v2.4.0",
  "version_to": "v2.4.1",
  "commit_from": "e2f3a1b",
  "commit_to": "a3f2b1c",
  "deployed_by": "github-actions[bot]",
  "trigger": "ci",
  "duration_seconds": 47,
  "status": "success",
  "steps": [
    {"step": "pre-deploy-check", "status": "pass", "duration_ms": 1200},
    {"step": "pull-image", "status": "pass", "duration_ms": 8500},
    {"step": "stop-old", "status": "pass", "duration_ms": 800},
    {"step": "start-new", "status": "pass", "duration_ms": 3200},
    {"step": "health-check", "status": "pass", "duration_ms": 5000},
    {"step": "smoke-test", "status": "pass", "duration_ms": 28000}
  ],
  "affected_services": ["api"],
  "rollback_triggered": false
}
```

**Refresh Interval:** 60 seconds

**Visualizations:**
- **Deploy Frequency Sparkline:** 7-day and 30-day bar chart showing deploys per day
- **Success Rate:** Gauge or large percentage number (94.3%), color-coded: green (>= 95%), yellow (85-95%), red (< 85%)
- **Mean Time to Deploy:** Average duration of successful deployments
- **Deploy by Service:** Stacked bar chart showing deployment count per service per week

**Scroll Behavior:** Virtual scrolling, load last 50 deployments initially, "Load More" button for history beyond 50

**Interactions:**
- Click any deployment row to expand and see step-by-step detail with durations
- Click a failed deployment to see error message and link to full log
- Filter by: date range, service, server, status, deployed_by

---

### Panel C: Rollback History

**Purpose:** Every rollback event tracked with root cause, making patterns visible and enabling postmortems.

**Data Schema:**
```json
{
  "rollback_id": "string",
  "triggered_at": "ISO8601",
  "resolved_at": "ISO8601 or null",
  "service": "string",
  "server": "string",
  "version_rolled_from": "string",
  "version_rolled_to": "string",
  "reason_category": "string (config_error | code_bug | infra_failure | dependency | timeout | manual)",
  "reason_detail": "string (human-written or auto-generated reason)",
  "triggering_condition": "string (e.g. health_check_failed_3x, error_rate > 5%)",
  "automatic": "boolean (was rollback triggered automatically or by human?)",
  "triggered_by": "string",
  "recovery_duration_seconds": "number",
  "affected_users_estimate": "number or null",
  "postmortem_url": "string or null"
}
```

**Data Source:** `/var/log/wheeler/rollback/*.json` on each server.

**Refresh Interval:** 60 seconds

**Metrics Displayed:**
- Total rollbacks (all-time, last 30 days, last 7 days)
- Rollback rate: rollbacks / total deploys (target: less than 3%)
- Mean time to recover (MTTR): average recovery_duration_seconds
- Top rollback reasons (pie chart or bar chart)
- Rollbacks by service (bar chart)

**Interactions:**
- Click row to see full rollback detail, including what health checks failed
- Link to associated deployment in Panel B
- Link to postmortem document if exists
- Filter by reason category, service, automatic vs manual

---

### Panel D: Unhealthy Deploys / Active Alerts

**Purpose:** The most critical panel -- operators should check this first. Shows everything currently wrong.

**Data Schema:**
```json
{
  "alert_id": "string",
  "severity": "string (critical | warning | info)",
  "status": "string (active | acknowledged | resolved)",
  "server": "string",
  "service": "string",
  "metric": "string (error_rate | latency_p95 | health_check | cpu | memory | disk | process_down)",
  "current_value": "number",
  "threshold": "number",
  "operator": "string (> | < | ==)",
  "message": "string",
  "first_triggered": "ISO8601",
  "last_updated": "ISO8601",
  "acknowledged_by": "string or null",
  "acknowledged_at": "ISO8601 or null",
  "resolved_at": "ISO8601 or null",
  "runbook_url": "string (link to resolution procedure)"
}
```

**Data Sources:**
1. Health check endpoints (`GET /health` on each service) -- returns `{"status": "healthy|degraded|unhealthy", "checks": {...}}`
2. PM2 process status -- `stopped` or `errored` triggers `process_down`
3. Docker container health -- `docker ps --filter "health=unhealthy"`
4. Error rate from application metrics (Prometheus or custom `/metrics` endpoint)
5. Resource thresholds from system metrics

**Refresh Interval:** 15 seconds (the fastest panel)

**Visual Behavior:**
- **Critical alerts:** Red background with subtle pulse animation (CSS `@keyframes pulse-alert`). Must NOT be epilepsy-triggering; use slow 2-second pulse with low opacity change.
- **Warning alerts:** Yellow/orange, static background
- **Info alerts:** Blue, static background
- **Resolved alerts:** Move to "Recently Resolved" collapsible section below active alerts

**Interactions:**
- Acknowledge button: marks alert as acknowledged, records who and when. Acknowledged alerts show dimmer but remain visible.
- Mute button: silences alert for configurable period (15m, 1h, 4h, 24h)
- Runbook link: opens resolution procedure
- Click to expand: shows alert history (how long it has been firing), related metrics graph, suggested actions

**Alert Lifecycle State Machine:**
```
[Triggered] --(auto)--> [Active]
[Active] --(operator click)--> [Acknowledged]
[Active] --(metric returns to normal)--> [Resolved]
[Acknowledged] --(metric returns to normal)--> [Resolved]
[Resolved] --(moved to history after 24h)--> [Archived]
```

---

### Panel E: Pending Migrations

**Purpose:** Show all database migrations that have been created but not yet applied, with risk assessment.

**Data Schema:**
```json
{
  "migration_id": "string (Alembic revision ID)",
  "migration_name": "string (human-readable name)",
  "database": "string (core | finance | analytics)",
  "server": "string (COREDB)",
  "created_at": "ISO8601",
  "created_by": "string",
  "risk_level": "string (low | medium | high)",
  "estimated_downtime_seconds": "number or null",
  "locks_table": "boolean",
  "modifies_large_table": "boolean (table > 1M rows)",
  "has_rollback": "boolean (does migration have a downgrade() defined?)",
  "description": "string (from migration docstring)",
  "current_head": "string (currently applied revision)",
  "pending_count": "number (how many revisions behind head)",
  "head_revision": "string (latest available revision)"
}
```

**Data Source:** Run `alembic current` and `alembic heads` on COREDB for each database, parse output, compare.

**Collection Script (conceptual):**
```bash
#!/bin/bash
# Run on COREDB server, outputs JSON for dashboard
for DB in core finance analytics; do
    cd /opt/wheeler/$DB
    CURRENT=$(alembic current 2>/dev/null | grep -v "^$" | awk '{print $1}')
    HEAD=$(alembic heads 2>/dev/null | head -1)
    PENDING=$(alembic history -r $CURRENT:$HEAD 2>/dev/null | grep "->" | wc -l)
    # For each pending migration, extract metadata
    alembic history -r $CURRENT:$HEAD -v 2>/dev/null
done
```

**Refresh Interval:** 5 minutes (migrations change rarely)

**Risk Level Definitions:**

| Risk | Criteria | Examples |
|---|---|---|
| **Low** | New table, new index, no data modification | `CREATE TABLE audit_log`, `CREATE INDEX idx_email` |
| **Medium** | Adds column with default, modifies existing index, backfill < 100K rows | `ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}'` |
| **High** | Locks large table, data type change, backfill > 100K rows, no rollback defined | `ALTER TABLE payments ALTER COLUMN amount TYPE numeric(12,4)`, schema migrations without `downgrade()` |

**Visual Display:**
- Table with columns: Migration, Database, Risk (color-coded badge), Age (days since created), Has Rollback (check/cross icon)
- Risk color: Low = green, Medium = yellow, High = red
- Section at bottom: "Last Applied" showing most recent migration applied, when, and by whom
- Warning banner if HIGH risk migrations are pending for more than 7 days

---

### Panel F: Server Deployment State

**Purpose:** Hardware-level view of each server running deployment workloads.

**Data Schema (per server):**
```json
{
  "server": "string",
  "host": "string",
  "provider": "string",
  "ip": "string",
  "cpu_percent": "number",
  "cpu_cores": "number",
  "ram_used_gb": "number",
  "ram_total_gb": "number",
  "ram_percent": "number",
  "disk_used_gb": "number",
  "disk_total_gb": "number",
  "disk_percent": "number",
  "uptime_days": "number",
  "uptime_hours": "number",
  "load_avg_1m": "number",
  "load_avg_5m": "number",
  "load_avg_15m": "number",
  "services": [
    {
      "name": "string",
      "status": "string (online | stopped | errored | launching)",
      "pid": "number",
      "cpu_percent": "number",
      "memory_mb": "number",
      "uptime_seconds": "number",
      "restart_count": "number",
      "port": "number or null"
    }
  ],
  "docker_containers": [
    {
      "name": "string",
      "image": "string",
      "status": "string (running | stopped | unhealthy)",
      "cpu_percent": "number",
      "memory_mb": "number",
      "health": "string (healthy | unhealthy | starting | none)"
    }
  ]
}
```

**Data Sources:**
- CPU/RAM/Disk/Uptime: Prometheus `node_exporter` metrics or direct `/proc` reads via agent
- PM2 processes: `pm2 jlist`
- Docker containers: `docker stats --no-stream --format json` and `docker ps --format json`

**Refresh Interval:** 10 seconds (resource metrics change rapidly)

**Visual Display per Server:**
- Progress bars for CPU, RAM, Disk with percentage and absolute values
- Color thresholds for bars:
  - CPU: green < 60%, yellow 60-80%, red > 80%
  - RAM: green < 70%, yellow 70-85%, red > 85%
  - Disk: green < 75%, yellow 75-90%, red > 90%
- Service list below each server with status indicators
- Uptime shown in human-readable format (e.g. "34d 12h 7m")

**Tab Behavior:** The environment tabs (ALL/EDGE/AIOPS/COREDB) in the header filter all panels. Selecting "EDGE" shows only EDGE server data across all panels.

---

### Panel G: Build / Test Status

**Purpose:** Developer-focused view of CI pipeline status for each service.

**Data Schema:**
```json
{
  "service": "string",
  "last_run_id": "string",
  "last_run_number": "number",
  "status": "string (success | failure | running | queued | cancelled)",
  "started_at": "ISO8601",
  "completed_at": "ISO8601 or null",
  "duration_seconds": "number or null",
  "branch": "string",
  "commit_hash": "string",
  "commit_message": "string",
  "triggered_by": "string",
  "workflow_name": "string",
  "test_summary": {
    "total": "number",
    "passed": "number",
    "failed": "number",
    "skipped": "number"
  },
  "coverage_percent": "number or null",
  "coverage_delta": "number or null (change from previous run)",
  "lint_issues": "number",
  "artifact_url": "string or null",
  "workflow_url": "string"
}
```

**Data Source:** GitHub Actions API

**API Endpoints Used:**
```
GET /repos/{owner}/{repo}/actions/workflows
GET /repos/{owner}/{repo}/actions/runs?branch=main&per_page=5
GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs
GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/zip  (for coverage data)
```

**Polling Strategy:**
- Check every 30 seconds while any workflow is `running` or `queued`
- When all workflows are idle, reduce to 5-minute polling
- GitHub webhooks preferred for production: listen for `workflow_run` and `workflow_job` events, push updates via WebSocket

**Visual Display:**
- Table with service name, status icon (animated spinner for running), coverage % with change indicator (up arrow green, down arrow red)
- Last run timestamp with relative time ("3 minutes ago", "2 hours ago")
- Click to expand: see individual job statuses (lint, test, build, deploy), test counts, link to GitHub Actions run

**Coverage Trend:** Small inline sparkline showing coverage % over last 10 runs per service

---

### Panel H: AI Deployment Health

**Purpose:** Dedicated view for AI infrastructure health including LiteLLM proxy, model availability, and usage.

**Data Schema:**
```json
{
  "litellm_status": "string (healthy | degraded | down)",
  "litellm_uptime_seconds": "number",
  "litellm_version": "string",
  "models": [
    {
      "model_id": "string (deepseek-chat, openai/gpt-4o, etc.)",
      "provider": "string (deepseek | openrouter | openai)",
      "status": "string (available | degraded | unavailable | fallback)",
      "is_primary": "boolean",
      "is_fallback": "boolean",
      "latency_p50_ms": "number",
      "latency_p95_ms": "number",
      "latency_p99_ms": "number",
      "error_rate_percent": "number",
      "requests_last_hour": "number",
      "tokens_input_today": "number",
      "tokens_output_today": "number",
      "circuit_breaker_state": "string (closed | half_open | open)",
      "circuit_breaker_failure_count": "number",
      "circuit_breaker_threshold": "number",
      "last_health_check": "ISO8601",
      "health_check_status": "string (pass | fail | timeout)"
    }
  ],
  "failover_events_today": "number",
  "failover_active": "boolean",
  "failover_active_since": "ISO8601 or null",
  "aggregated": {
    "total_requests_today": "number",
    "total_tokens_today": "number",
    "total_cost_estimate_usd": "number",
    "mean_latency_ms": "number",
    "p95_latency_ms": "number",
    "error_rate_percent": "number"
  }
}
```

**Data Sources:**
1. LiteLLM `/metrics` endpoint (Prometheus format) -- request counts, latencies, token counts
2. LiteLLM `/health` endpoint -- returns `{"status": "healthy", "models": [...]}`
3. LiteLLM `/v1/models` -- lists available models
4. Custom health check service that sends test inference requests to each model every 30 seconds
5. PM2 API for LiteLLM process status

**Refresh Interval:** 30 seconds

**Visual Display:**
- LiteLLM status banner at top (green/yellow/red)
- Model grid: each model as a card showing name, provider, latency p95, error rate, circuit breaker state
- Aggregated stats bar: total requests, total tokens, estimated cost
- Failover banner: visible only when failover is active, shows which models are on fallback and for how long
- Token usage chart: hourly token consumption for last 24 hours (bar chart)
- Latency chart: p50/p95/p99 line chart for last hour

**Circuit Breaker Visualization:**

| State | Color | Icon | Behavior |
|---|---|---|---|
| CLOSED | Green | Shield check | Normal routing, all requests go to primary |
| HALF_OPEN | Yellow | Shield with dot | Testing primary with limited requests |
| OPEN | Red | Shield exclamation | All requests routed to fallback |

---

## 4. Implementation Options

### Option A: Grafana with Prometheus Data Source

**Architecture:**
```
Servers -> Prometheus (scrape) -> Grafana (visualize)
        -> Loki (logs)         -> Grafana (visualize logs)
        -> Alertmanager        -> Grafana (alert display)
```

**Pros:**
- Battle-tested, production-grade
- Rich ecosystem of pre-built dashboards and panels
- Excellent query language (PromQL, LogQL)
- Built-in alerting with Alertmanager integration
- Role-based access control (Grafana OSS and Enterprise)
- Native support for all data sources we need (Prometheus, Loki, PostgreSQL for migration data)
- Grafana Alerting can be configured as code (provisioning YAML)
- Large community, extensive documentation

**Cons:**
- Heavy dependency stack: Prometheus + Node Exporter + Process Exporter + Loki + Promtail + Grafana
- High resource consumption (Prometheus TSDB can grow large, Loki needs S3-compatible storage or large local disk)
- Complex initial setup and configuration
- Learning curve for PromQL (though less steep with Grafana's query builder)
- Grafana's panel layout is less flexible than custom HTML for some specialized panels (circuit breaker state, AI model grid)
- Requires opening metrics ports on each server or using a Pushgateway

**Effort Estimate:** 3-4 weeks for production-ready setup
**Monthly Cost:** $0 (self-hosted OSS) but requires approximately 8GB RAM, 4 vCPU for monitoring stack

---

### Option B: Custom React Dashboard with WebSocket Updates

**Architecture:**
```
Servers -> Agent (Python, runs on each server) -> NATS/Redis PubSub -> Aggregator (Python/FastAPI)
                                                                     -> WebSocket server
                                                                     -> React SPA
```

**Pros:**
- Complete control over UI/UX -- can build exactly the panels specified above
- Real-time WebSocket updates give sub-second latency for critical panels
- Can embed actions directly (acknowledge alert, trigger rollback, restart service)
- Single binary/page to deploy
- Can be optimized for our specific data shapes (reducing bandwidth)
- Modern stack enjoyable for the team to work on
- Responsive design from the start

**Cons:**
- Significant development effort (build everything from scratch)
- Must handle all edge cases: reconnection, state reconciliation, auth, CORS
- No pre-built alerting -- must implement alert evaluation, notification channels, alert lifecycle
- Must build own metric storage if we want historical trends (or integrate with Prometheus anyway)
- Higher maintenance burden long-term
- Security considerations: WebSocket auth, data validation, rate limiting
- Testing surface area is large

**Technology Stack Recommendation:**
- Frontend: React 18 + TypeScript, Vite, TailwindCSS, Recharts (charts), TanStack Table (tables)
- Backend: FastAPI (Python), SQLite or PostgreSQL for state, Redis for pub/sub
- Data collectors: Python agents on each server pushing via HTTP POST or Redis
- Deployment: Docker Compose on EDGE server

**Effort Estimate:** 6-10 weeks for feature-complete dashboard
**Monthly Cost:** $0 (self-hosted) plus development time

---

### Option C: Terminal-Based TUI (k9s-Style Custom Application)

**Architecture:**
```
Servers -> SSH agent (runs commands remotely) -> TUI renderer (Python Textual or Go Bubble Tea)
        -> Local aggregator process
```

**Pros:**
- Extremely lightweight -- runs directly in terminal, no browser needed
- Perfect for SSH-only environments and low-bandwidth connections
- Can be the fastest to build (limited UI surface area)
- Keyboard-driven navigation is fast for experienced operators
- No web security concerns
- Works over mosh/tmux for persistent sessions
- Low resource consumption (less than 100MB RAM)

**Cons:**
- Only usable by ops team with terminal access -- developers and management cannot view
- Limited visualization capabilities (no sparklines easily, no rich charts)
- Cannot embed external content (CI links, GitHub links) in clickable form
- Harder to share -- each user must install or SSH into a jump host
- No persistent state between sessions (unless backed by a server)
- Accessibility concerns (screen readers, color-blindness accommodation is harder)
- Cannot display rich media (deployment screenshots, architecture diagrams)

**Technology Options:**
- **Textual (Python):** Rich widget library, CSS-like layout, async support. Best for teams strong in Python.
- **Bubble Tea (Go):** Elm architecture for TUIs, great performance, single binary deployment. Best if team is Go-heavy.
- **k9s plugin:** Extend k9s with custom views. Limited but very quick to set up if already using k9s.

**Effort Estimate:** 2-4 weeks for functional TUI
**Monthly Cost:** $0

---

### Comparison Matrix

| Criteria | Grafana | Custom React | TUI |
|---|---|---|---|
| **Development time** | 3-4 weeks (config) | 6-10 weeks (build) | 2-4 weeks (build) |
| **Real-time updates** | 10-30s (scrape interval) | Sub-second (WebSocket) | 5-15s (polling) |
| **Ops team UX** | Good | Good | Excellent |
| **Developer UX** | Good | Excellent | Poor (no access) |
| **Management UX** | Adequate | Excellent | Poor (no access) |
| **Alerting** | Built-in (Alertmanager) | Must build | Must build |
| **Historical data** | Built-in (Prometheus TSDB) | Must build or integrate | None (or basic) |
| **Maintenance** | Low (OSS ecosystem) | High (custom code) | Medium (custom code) |
| **Security surface** | Medium | High | Low |
| **Infrastructure cost** | Approximately 8GB RAM + 4vCPU | Approximately 2GB RAM + 2vCPU | Negligible |
| **Extensibility** | Plugins, community panels | Full control | Code changes |

### Recommended Approach: Hybrid (Grafana + Custom Panels)

**Phase 1:** Deploy Grafana + Prometheus + node_exporter for infrastructure metrics (Server Deployment State, basic health). This gives us immediate value within 2 weeks.

**Phase 2:** Build a lightweight custom aggregator service (FastAPI) that collects deployment-specific data (Current Release, Deployment History, Rollback History, AI Health). Expose this as JSON APIs and/or Prometheus metrics.

**Phase 3:** Serve a custom React frontend for the deployment-specific panels (Panels A, B, C, D, E, H) while embedding Grafana panels via iframe for infrastructure metrics (Panel F) and CI status (Panel G).

**Phase 4 (optional):** Migrate everything to custom React once the custom dashboard proves its value, sunsetting Grafana for this use case.

---

## 5. Data Pipeline

### Architecture Overview

```
+-----------------------------------------------------------------------------+
|                           DATA COLLECTION LAYER                             |
|                                                                             |
|  +---------------+---------------+---------------+                         |
|  | EDGE Server    | AIOPS Server   | COREDB Server  |                        |
|  |                |                |                |                        |
|  | node_exporter  | node_exporter  | node_exporter  | (system metrics)       |
|  | pm2-exporter   | pm2-exporter   | pm2-exporter   | (process metrics)      |
|  | wheeler-agent  | wheeler-agent  | wheeler-agent  | (custom metrics)       |
|  | litellm-exp    | docker-exp     | pg-exporter    | (service metrics)      |
|  +-------+--------+-------+--------+-------+--------+                        |
|          |                 |                 |                                |
|          +-----------------+-----------------+                                |
|                            |                                                  |
+----------------------------+-------------------------------------------------+
                             |
                             v
+-----------------------------------------------------------------------------+
|                        METRICS AGGREGATION LAYER                            |
|                                                                             |
|  +----------------------------------------------------+                    |
|  |           Prometheus (scrape every 10-30s)          |                    |
|  |  - System metrics (node_exporter :9100)             |                    |
|  |  - Process metrics (pm2-exporter :9200)             |                    |
|  |  - Docker metrics (cadvisor :8080)                  |                    |
|  |  - DB metrics (postgres_exporter :9187)             |                    |
|  |  - LiteLLM metrics (:4000/metrics)                  |                    |
|  +--------------------------+-------------------------+                    |
|                             |                                               |
|  +--------------------------+-------------------------+                    |
|  |         wheeler-aggregator (FastAPI)               |                    |
|  |  - Receives push from wheeler-agent on each        |                    |
|  |    server (deploy logs, rollback logs,             |                    |
|  |    current release state, migration status)        |                    |
|  |  - Polls GitHub Actions API for CI status          |                    |
|  |  - Polls LiteLLM /health for AI status             |                    |
|  |  - Stores state in SQLite or Redis                 |                    |
|  |  - Exposes REST API + WebSocket                    |                    |
|  +--------------------------+-------------------------+                    |
|                             |                                               |
+-----------------------------+-----------------------------------------------+
                              |
                              v
+-----------------------------------------------------------------------------+
|                        VISUALIZATION LAYER                                  |
|                                                                             |
|  +------------------+    +--------------------------+                      |
|  |   Grafana         |    |  Custom React SPA        |                      |
|  |  (infra metrics)  |    |  (deploy panels)         |                      |
|  |                   |    |                          |                      |
|  |  Data:            |    |  Data:                   |                      |
|  |  Prometheus       |    |  wheeler-aggregator      |                      |
|  |                   |    |  REST + WebSocket        |                      |
|  +------------------+    +--------------------------+                      |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Metrics Collection Detail

**Prometheus `prometheus.yml` scrape configuration:**

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    environment: production

scrape_configs:
  # System metrics from each server
  - job_name: 'node_exporter'
    static_configs:
      - targets:
        - '187.77.148.88:9100'   # EDGE
        - '5.78.140.118:9100'    # AIOPS
        - '5.78.210.123:9100'    # COREDB
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):\d+'
        replacement: '${1}'

  # PM2 process metrics (via pm2-prometheus-exporter or custom exporter)
  - job_name: 'pm2'
    static_configs:
      - targets:
        - '187.77.148.88:9200'
        - '5.78.140.118:9200'
        - '5.78.210.123:9200'

  # Docker container metrics (via cadvisor)
  - job_name: 'docker'
    static_configs:
      - targets: ['5.78.140.118:8080']  # AIOPS runs Docker

  # PostgreSQL metrics
  - job_name: 'postgres'
    static_configs:
      - targets: ['5.78.210.123:9187']  # COREDB

  # LiteLLM metrics
  - job_name: 'litellm'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['5.78.140.118:4000']  # AIOPS

  # Custom wheeler-aggregator metrics (deploy count, rollback count, etc.)
  - job_name: 'wheeler_aggregator'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['187.77.148.88:9500']  # Runs on EDGE
```

### Wheeler-Agent Design (per-server collector)

Each server runs a lightweight Python agent (`wheeler-agent`) that:

1. **Collects current release state** every 30s: reads PM2 jlist, git tags, health endpoints
2. **Watches deploy logs**: inotify on `/var/log/wheeler/deploy/`, pushes new deployment events to aggregator
3. **Watches rollback logs**: inotify on `/var/log/wheeler/rollback/`, pushes new rollback events to aggregator
4. **Health checks**: runs `pm2 status`, checks Docker health, reports to aggregator

**Communication Protocol:**
```
wheeler-agent --HTTP POST--> wheeler-aggregator /api/v1/ingest
                              {
                                "source": "EDGE",
                                "timestamp": "2026-05-23T14:28:05Z",
                                "event_type": "deployment|rollback|state_snapshot|health_check",
                                "payload": { ... }
                              }
```

**Agent Configuration (wheeler-agent.yaml):**
```yaml
server:
  name: EDGE
  host: 187.77.148.88
  provider: Hostinger

aggregator:
  url: http://187.77.148.88:9500   # EDGE server runs the aggregator
  api_key: ${WHEELER_API_KEY}

collectors:
  pm2:
    enabled: true
    interval_seconds: 30
  deploy_logs:
    enabled: true
    watch_path: /var/log/wheeler/deploy/
  rollback_logs:
    enabled: true
    watch_path: /var/log/wheeler/rollback/
  git_tags:
    enabled: true
    repos:
      - /opt/wheeler/api
      - /opt/wheeler/web
      - /opt/wheeler/workers
  health_checks:
    enabled: true
    endpoints:
      - http://localhost:3000/health   # api
      - http://localhost:3001/health   # web
    interval_seconds: 15
```

### Log Aggregation (Optional Enhancement)

For richer deployment log access from the dashboard:

```
Deploy logs (/var/log/wheeler/deploy/*.json)
    |
    v
Promtail (tail + push to Loki)
    |
    v
Loki (log aggregation, indexed by labels: server, service, status)
    |
    v
Grafana (LogQL queries for deployment log exploration)
```

This is optional for Phase 1 -- Phase 1 just reads the structured JSON files directly.

---

## 6. Alert Thresholds

### Alert Severity Definitions

| Severity | Icon | Color | Response Time | Notification Channel | Auto-Escalation |
|---|---|---|---|---|---|
| **CRITICAL** | Red exclamation | #ef4444 | Less than 5 minutes | PagerDuty/SMS + Dashboard flash | Escalate to Engineering Manager if unacknowledged after 10 min |
| **WARNING** | Yellow triangle | #eab308 | Less than 30 minutes | Slack #ops-alerts + Dashboard | Escalate to on-call if unacknowledged after 1 hour |
| **INFO** | Blue circle | #3b82f6 | Next business day | Dashboard only (no push) | None |

### Threshold Definitions

#### Infrastructure Alerts

| Metric | Operator | Warning | Critical | Duration | Description |
|---|---|---|---|---|---|
| CPU usage | greater than | 80% | 95% | > 5 min | Sustained high CPU on any server |
| RAM usage | greater than | 85% | 95% | > 5 min | Memory pressure, risk of OOM kill |
| Disk usage | greater than | 80% | 90% | immediate | Risk of disk full |
| Disk growth rate | greater than | 5% per day | 10% per day | > 1 day | Disk filling faster than expected |
| Load average / cores | greater than | 2.0 | 4.0 | > 10 min | CPU saturation |
| Swap usage | greater than | 10% | 30% | > 5 min | System under memory pressure |

#### Process / Service Alerts

| Metric | Operator | Warning | Critical | Duration | Description |
|---|---|---|---|---|---|
| PM2 process status | == | -- | stopped | immediate | Process is down |
| PM2 restart count | delta | > 3 in 1h | > 10 in 1h | > 1h | Process crash-looping |
| Docker container health | == | -- | unhealthy | > 1 min | Container failing health checks |
| Service health check | == | degraded | unhealthy | > 2 consecutive | Service returning degraded/unhealthy |
| Port not listening | == | -- | true | immediate | Expected port not bound |

#### Application Alerts

| Metric | Operator | Warning | Critical | Duration | Description |
|---|---|---|---|---|---|
| HTTP error rate (5xx) | greater than | 2% | 5% | > 5 min | Elevated server errors |
| HTTP latency p95 | greater than | 2s | 5s | > 5 min | Slow responses |
| Request queue depth | greater than | 100 | 500 | > 2 min | Requests backing up |
| Failed login rate | greater than | 10/min | 50/min | > 5 min | Possible brute force attack |

#### AI / LiteLLM Alerts

| Metric | Operator | Warning | Critical | Duration | Description |
|---|---|---|---|---|---|
| LiteLLM proxy down | == | -- | true | immediate | AI services unavailable |
| Model error rate | greater than | 5% | 15% | > 5 min | Primary model failing |
| Circuit breaker open | == | true | true (and > 5min) | immediate | All traffic on fallback |
| Token usage spike | greater than | 2x normal | 5x normal | > 15 min | Possible abuse or runaway loop |
| Model latency p95 | greater than | 5s | 10s | > 5 min | Model responding slowly |
| Failover active | == | true (>10 min) | true (>30 min) | > 10/30 min | Extended time on fallback provider |

#### CI / Build Alerts

| Metric | Operator | Warning | Critical | Duration | Description |
|---|---|---|---|---|---|
| CI run failed | == | true | -- | per run | Main branch build failure (info per failure, warn if > 3 consecutive) |
| Coverage decrease | delta | < -5% | < -10% | per run | Significant coverage drop |
| CI queue time | greater than | 15 min | 30 min | per run | Runners are congested |

#### Deployment Alerts

| Metric | Operator | Warning | Critical | Duration | Description |
|---|---|---|---|---|---|
| Deploy failure | == | true | -- | immediate | Any deploy failure generates info alert |
| Deploy duration | greater than | 5 min | 15 min | per deploy | Deployment taking unusually long |
| Consecutive deploy failures | >= | 3 | 5 | rolling | Deployment pipeline may be broken |
| Rollback triggered | == | true | -- | immediate | Auto-rollback = warning; any rollback = info |
| Deployment success rate | less than | 90% (7 day) | 80% (7 day) | 7 day window | Deployment reliability degraded |

### Escalation Path

```
Alert Fires (CRITICAL)
    |
    +-- 0 min: Dashboard shows alert, sound notification (if browser open)
    |
    +-- 2 min: PagerDuty/SMS notification to primary on-call
    |
    +-- 5 min: If unacknowledged, notify secondary on-call
    |
    +-- 10 min: If unacknowledged, notify Engineering Manager
    |
    +-- 30 min: If unacknowledged, notify VP Engineering

Alert Fires (WARNING)
    |
    +-- 0 min: Dashboard shows alert, Slack #ops-alerts message
    |
    +-- 30 min: If unacknowledged, notify primary on-call (PagerDuty)
    |
    +-- 2 hours: If unacknowledged, notify Engineering Manager

Alert Fires (INFO)
    |
    +-- Dashboard badge counter increments, no push notification
```

### Alert Suppression Rules

- **Maintenance mode:** When a deployment is in progress for a service, suppress alerts for that service for duration + 60 seconds
- **Flapping protection:** If an alert fires and resolves more than 3 times in 10 minutes, suppress for 30 minutes with a "flapping" annotation
- **Business hours only:** INFO alerts for non-critical services can be configured to only fire during business hours (09:00-18:00 UTC)
- **Acknowledged alarms:** Do not re-notify for 30 minutes after acknowledgment

---

## 7. Implementation Phases

### Phase 1: Basic Health Status Page (Weeks 1-2)

**Goal:** A static HTML page served from the EDGE node that shows current deployment state. No real-time updates (manual refresh). No historical data. But it is up and useful.

**Deliverables:**

1. **Wheeler-Agent on each server** (simple Python script, systemd service)
   - Collects PM2 process list, git tags, health check results
   - Pushes JSON snapshot to aggregator via HTTP POST every 30 seconds

2. **Wheeler-Aggregator on EDGE** (FastAPI, systemd service)
   - Receives snapshots from agents
   - Stores latest snapshot in memory + SQLite file
   - Serves `/api/v1/state` JSON endpoint
   - Serves static HTML at `/`

3. **Static HTML dashboard** (single `index.html`, vanilla JS)
   - Panel A: Current Release Overview (server/service/version/status table)
   - Panel F: Server Deployment State (CPU/RAM/Disk bars per server)
   - Auto-refresh every 30 seconds via `setInterval(fetch, 30000)`
   - Basic CSS with color-coded status

4. **Health check endpoints** standardized across all services:
   - `GET /health` must return: `{"status": "healthy|degraded|unhealthy", "version": "vX.Y.Z", "uptime": N}`

**Success Criteria:**
- Operators can see what version of each service is deployed on each server
- Operators can see CPU/RAM/Disk usage per server
- Page loads in less than 2 seconds
- Data is no more than 60 seconds stale

---

### Phase 2: Real-Time Updates via WebSocket (Weeks 3-5)

**Goal:** Add WebSocket push for near-instant updates, plus additional panels.

**Deliverables:**

1. **WebSocket server** in wheeler-aggregator
   - Clients connect to `ws://aggregator:9500/ws`
   - Server pushes state diffs on any change (deploy complete, health change, alert fire/resolve)
   - Auto-reconnection with exponential backoff on client side

2. **Deployment and Rollback Log Watchers**
   - Wheeler-agent watches `/var/log/wheeler/deploy/` and `/var/log/wheeler/rollback/` using inotify
   - New JSON log files trigger immediate push to aggregator
   - No more 60-second polling gap

3. **Panel B: Deployment History Timeline**
   - Last 50 deployments with success/fail visualization
   - Click to expand step details

4. **Panel C: Rollback History**
   - All rollback events with reasons

5. **Panel D: Unhealthy Deploys / Active Alerts**
   - Alert evaluation engine in aggregator
   - Red flashing for critical alerts (CSS animation)
   - Acknowledge/mute functionality

6. **React migration** (replace static HTML)
   - React 18 + Vite + TailwindCSS
   - Component per panel
   - WebSocket context provider
   - Responsive grid layout

**Success Criteria:**
- Deployment events appear on dashboard within 2 seconds of completion
- Alert fires within 15 seconds of threshold breach
- WebSocket reconnects within 5 seconds of disconnect
- Dashboard stays usable under load (100 simultaneous viewers)

---

### Phase 3: Historical Trends and Analytics (Weeks 6-8)

**Goal:** Add historical data storage, trends, and analytics. Management-friendly views.

**Deliverables:**

1. **Time-series database** (Prometheus for metrics, or TimescaleDB for deployment events)
   - Store deployment duration, success/fail, frequency going back 90 days
   - Store rollback events for trend analysis

2. **Prometheus + Grafana integration**
   - Deploy Prometheus scraping node_exporter, pm2-exporter, LiteLLM metrics
   - Build Grafana dashboards for infrastructure metrics
   - Embed Grafana panels in React dashboard via iframe (or use Grafana's JSON API)

3. **Panel E: Pending Migrations**
   - Migration collector on COREDB
   - Risk assessment logic
   - Visual display with risk badges

4. **Panel G: Build/Test Status**
   - GitHub Actions API integration
   - Coverage trend sparklines
   - Build status in near real-time via webhook

5. **Analytics views:**
   - Deployment frequency trends (weekly, monthly)
   - Success rate trends
   - Mean time to recovery (MTTR) trends
   - Deployment lead time (commit to deploy)
   - Change failure rate

6. **Export functionality:**
   - Download deployment history as CSV
   - Share dashboard snapshot URL (read-only, time-bounded)

**Success Criteria:**
- 90 days of deployment history queryable
- Deployment frequency and success rate visible with trend lines
- DORA metrics calculable from stored data
- Management can view dashboard without ops-team assistance

---

### Phase 4: Predictive Alerts and ML-Based Anomaly Detection (Weeks 9-12)

**Goal:** Proactive alerting that catches issues before they become incidents.

**Deliverables:**

1. **Anomaly detection models:**
   - Time-series anomaly detection on: error rate, latency, request rate, CPU, memory, token usage
   - Models: moving average with standard deviation bands, or isolation forest for multivariate
   - Train on 30 days of historical data, retrain weekly

2. **Predictive alerts:**
   - "Disk will be full in 3 days at current growth rate"
   - "Error rate trend suggests threshold breach in 2 hours"
   - "Memory leak detected in service X (steady growth over 24h)"
   - "Deployment success rate declining (trending toward 85% threshold)"

3. **Deployment risk scoring:**
   - Before deploy, score the risk based on: change size (lines/files), time since last deploy, day of week, service history, author experience
   - Display risk score in Current Release Overview when deploying
   - High risk deploys get extra pre-deploy checks

4. **Automated runbooks:**
   - For known failure patterns, dashboard suggests specific remediation steps
   - "Error pattern matches memory leak in worker -- run `pm2 restart wheeler-worker`"

5. **Weekly health report:**
   - Auto-generated PDF/email summarizing: deploy count, success rate, MTTR, top incidents, AI costs, infrastructure health
   - Sent to management every Monday 09:00 UTC

**Success Criteria:**
- Predictive alerts fire at least 15 minutes before manual detection would occur (measured retroactively)
- Anomaly detection false positive rate less than 10%
- Deployment risk scores correlate with actual failure rate (high-risk deploys fail more often than low-risk)
- Weekly reports require zero manual data gathering

---

## Appendix A: Technology Stack Recommendations

### Phase 1 Stack

| Component | Technology | Rationale |
|---|---|---|
| Agent (server-side) | Python 3.11+ | Team familiarity, rich stdlib |
| Aggregator | FastAPI (Python) | Async, auto-docs, WebSocket support |
| Storage | SQLite | Zero-config, sufficient for Phase 1 |
| Frontend | Vanilla HTML/JS | Maximum simplicity, fast to build |
| Process manager | systemd | Already used, reliable |

### Phase 2+ Stack

| Component | Technology | Rationale |
|---|---|---|
| Frontend | React 18 + TypeScript + Vite | Modern DX, type safety, fast builds |
| Styling | TailwindCSS | Utility-first, fast to iterate |
| Charts | Recharts | React-native, composable, good defaults |
| Tables | TanStack Table (React Table) | Headless, powerful sorting/filtering |
| WebSocket | FastAPI built-in + reconnecting-websocket (client) | Simple, no extra dependencies |
| Metrics DB | Prometheus + VictoriaMetrics (optional) | Industry standard, rich query language |
| Logs | Loki (optional, Phase 3) | Lightweight, pairs with Grafana |

### Phase 3+ Stack

| Component | Technology | Rationale |
|---|---|---|
| Visualization | Grafana OSS | Rich dashboarding, alerting, plugins |
| Time-series DB | Prometheus TSDB | Already scraping, use built-in storage |
| Anomaly Detection | Python scikit-learn / statsmodels | Team familiarity, good enough for Phase 4 |

---

## Appendix B: Security Considerations

1. **Authentication:** Dashboard behind OAuth2 proxy (e.g., oauth2-proxy with GitHub OAuth) or basic auth for Phase 1
2. **Agent-to-Aggregator:** Shared API key in HTTP header (`Authorization: Bearer ${WHEELER_API_KEY}`), validated by aggregator
3. **WebSocket auth:** Token in connection query param (`ws://host/ws?token=...`), validated on connect
4. **CORS:** Aggregator only allows connections from dashboard origin
5. **Rate limiting:** Aggregator rate-limits agent ingest (max 1 request/second per agent) and WebSocket connections (max 5 per IP)
6. **Data sensitivity:** No secrets in dashboard data. Version numbers, commit hashes, error rates are not sensitive. Token counts and usage metrics are internal.
7. **TLS:** Dashboard served over HTTPS in production (via Nginx reverse proxy with Let's Encrypt)
8. **Audit log:** All acknowledge/mute/action events logged with user and timestamp

---

## Appendix C: Runbook -- Dashboard Itself Fails

If the dashboard/aggregator on EDGE goes down:

1. **Detection:** Health check on aggregator (separate from dashboard) alerts if down > 60s
2. **Impact:** Dashboard unavailable. Deployments continue normally. Alerts still fire at server level (PM2 restarts, health checks at load balancer).
3. **Recovery:** `systemctl restart wheeler-aggregator` on EDGE
4. **Fallback:** SSH into each server and run `pm2 status`, `pm2 logs`, `docker ps` manually
5. **Postmortem:** Investigate aggregator logs at `/var/log/wheeler/aggregator/`

---

*End of Deployment Dashboard Plan*
