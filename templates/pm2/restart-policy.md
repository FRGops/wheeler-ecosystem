# Wheeler — PM2 Restart Policy Documentation

> **Classification**: INTERNAL — Platform Engineering
> **Effective date**: 2026-05-23
> **Applies to**: All Wheeler services managed by PM2 on AIOPS (5.78.140.118)
>
> This document defines the restart policies, execution modes, memory limits,
> and graceful shutdown procedures for every PM2-managed service in the
> Wheeler ecosystem.

---

## Table of Contents

1. [Core Restart Settings](#1-core-restart-settings)
2. [Fork vs Cluster Mode](#2-fork-vs-cluster-mode)
3. [Memory Limit Guidelines](#3-memory-limit-guidelines)
4. [CPU Protection Strategies](#4-cpu-protection-strategies)
5. [Restart Loop Detection & Recovery](#5-restart-loop-detection--recovery)
6. [Graceful Shutdown Procedures](#6-graceful-shutdown-procedures)
7. [Service-Specific Policies](#7-service-specific-policies)

---

## 1. Core Restart Settings

### 1.1 Restart Parameters Overview

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| `autorestart` | `true` | true/false | Automatically restart on exit |
| `max_restarts` | `10` | 3-16 | Max restarts in rolling window |
| `restart_delay` | `5000` | 2000-30000 | Millisecond delay between restarts |
| `min_uptime` | `10000` | 5000-60000 | Min uptime before counting as stable |
| `max_memory_restart` | varies | 256M-4G | RSS threshold for forced restart |
| `kill_timeout` | `10000` | 5000-60000 | SIGTERM grace before SIGKILL |
| `listen_timeout` | `10000` | 5000-60000 | Max wait for 'ready' signal |

### 1.2 How Restart Counting Works

PM2 maintains a sliding window of restart events.  The window duration is
implicitly defined as `restart_delay * max_restarts`.  If the number of
restarts within this window exceeds `max_restarts`, PM2 stops the process
and marks it as `errored`.

**Example**:
- `max_restarts: 10`, `restart_delay: 5000`
- Window: 50 seconds (10 * 5000ms)
- If a process restarts 11 times within 50 seconds, PM2 stops it.

### 1.3 Autorestart Exceptions

| Scenario | Autorestart Behavior | Rationale |
|----------|---------------------|-----------|
| Normal exit (code 0) | Restart | Process finished; restart to keep it alive |
| Crash (code != 0) | Restart (counts toward max) | Unexpected failure; retry |
| SIGTERM from PM2 stop | No restart | Intentional stop by operator |
| SIGKILL after kill_timeout | Restart (counts toward max) | Forced kill; process didn't shut down |
| Memory threshold exceeded | Restart (counts toward max) | Proactive restart to prevent OOM |
| Manual `pm2 delete` | No restart | Process removed by operator |
| Max restarts exceeded | No restart (errored state) | Restart loop protection |

### 1.4 Restart Delay Tuning

| Risk Profile | restart_delay | max_restarts | Rationale |
|-------------|---------------|--------------|-----------|
| **Critical service** (revenue) | 2000ms / 5 | 5 | Fast retry; fail fast if repeated crash |
| **Standard service** | 5000ms / 10 | 10 | Balanced retry vs protection |
| **Heavy init service** (ML model load) | 15000ms / 16 | 3 | Long startup allows more retries |
| **Non-critical worker** | 10000ms / 8 | 8 | Slow retry; backpressure implied |
| **One-shot task** | N/A | 0 | No restart; task is fire-and-forget |

---

## 2. Fork vs Cluster Mode

### 2.1 Decision Matrix

| Characteristic | Fork Mode | Cluster Mode |
|---------------|-----------|--------------|
| **Port sharing** | Each instance needs unique port | All instances share one port |
| **Load balancing** | External (Nginx/Traefik) | Built-in (round-robin) |
| **Memory isolation** | Full isolation per process | Shared V8 heap possible |
| **State sharing** | No shared state (external Redis needed) | No shared state (external Redis needed) |
| **Node.js only** | Works with any runtime | Node.js only |
| **Python support** | Yes (always fork) | No |
| **IPC** | Slower (OS-level) | Faster (internal) |
| **Debugging** | Easier (independent processes) | Harder (shared port) |
| **Zero-downtime reload** | Not possible (needs external LB) | Yes (`pm2 reload` rolls instances) |
| **CPU-bound work** | Better (dedicated cores) | Worse (shared event loop) |
| **I/O-bound work** | Good | Excellent |

### 2.2 When to Use Fork Mode

Use fork mode for:

1. **Python services** (always).  Python does not use Node.js cluster.
   - LiteLLM, FastAPI apps, Celery workers, ML inference servers.

2. **Stateful services** where each instance has unique state.
   - Socket servers (WebSocket, Socket.io without Redis adapter).
   - In-memory caches that shouldn't be duplicated.

3. **Workers and consumers** that pull from queues.
   - Redis queue consumers (Bull/BullMQ), RabbitMQ consumers.
   - Use `instances: N` with unique worker IDs.

4. **CPU-bound Node.js services** that benefit from per-core isolation.
   - Image processing, PDF generation, heavy computation.
   - Use `instances: N` where N <= physical cores.

5. **Schedulers and cron jobs**.
   - Only one instance needed (`instances: 1`).

### 2.3 When to Use Cluster Mode

Use cluster mode for:

1. **Stateless HTTP APIs** (Express, Fastify, Koa, Hapi).
   - FRGCRM API, Wheeler Brain OS REST endpoints, OpenClaw Gateway.
   - Use `instances: "max"` to utilize all cores.
   - Must be stateless (session data in Redis, not memory).

2. **Next.js applications** (when not using standalone output).
   - Use `instances: "max"` for production.

3. **Services requiring zero-downtime reload**.
   - Cluster mode's `pm2 reload` restarts instances one at a time.
   - Fork mode requires external load balancer for zero-downtime.

### 2.4 Transitioning Between Modes

To change from fork to cluster (or vice versa):

1. **Fork to Cluster**:
   - Stop all instances.
   - Change `exec_mode` to `"cluster"`.
   - Set `instances` to `"max"`.
   - Ensure the app is stateless (session store is external).
   - Ensure the app handles SIGTERM for graceful rolling restart.
   - Start with `pm2 start`.

2. **Cluster to Fork**:
   - Stop all instances.
   - Change `exec_mode` to `"fork"`.
   - Assign unique ports per instance or use external load balancer.
   - Set explicit `instances` count.
   - Start with `pm2 start`.

**Warning**: Do not change `exec_mode` and then `pm2 reload`.  This does not
work.  You must `pm2 stop`, update config, `pm2 start`.

---

## 3. Memory Limit Guidelines

### 3.1 Maximum Memory Restart by Service Type

| Service Type | Memory Limit | Rationale |
|-------------|-------------|-----------|
| **Light REST API** (CRUD, proxy, gateway) | 256M - 512M | Minimal in-memory state, thin request/response |
| **Medium API** (business logic, ORM, caching) | 512M - 1G | More complex processing, larger codebase |
| **Heavy API** (AI orchestration, data transforms) | 1G - 2G | Large objects in memory during processing |
| **LiteLLM** (LLM proxy with caching) | 1G | Model metadata caching, response caching |
| **Brain OS** (AI orchestration engine) | 2G | Multiple concurrent task contexts |
| **OpenClaw Gateway** (multi-agent gateway) | 1G | Agent state, tool results caching |
| **Voice Agent** (call handling) | 512M | Limited concurrent calls, audio buffer |
| **Browser Agent** (Puppeteer/Playwright) | 1G | Browser instance overhead (~150-300MB per tab) |
| **Prediction Radar Worker** (ML inference) | 1G - 2G | Model weights in memory |
| **Prediction Radar Scheduler** (cron) | 512M | Lightweight scheduling, no models |
| **SurplusAI Scraper** (web scraping) | 512M | DOM parsing, temporary page data |
| **Data ETL Worker** (batch processing) | 512M - 1G | Batch data in memory during processing |
| **WebSocket Server** | 1G | Active connection state for many clients |

### 3.2 The 80% Rule

The memory limit should be set to at least **125% of the service's normal
maximum observed memory usage**.  This provides a 25% buffer before the forced
restart is triggered.

```
memory_limit >= normal_max_rss * 1.25
```

**Example**:
- Service normally peaks at 400MB RSS under load.
- `max_memory_restart` should be `512M` (512 > 400 * 1.25 = 500).

### 3.3 Memory Monitoring

Monitor memory trends per service:

```bash
# Check current memory usage of all PM2 processes
pm2 list

# Detailed memory info for a specific service
pm2 describe wheeler-frgcrm-api-prod

# Watch real-time memory
pm2 monit
```

Prometheus metrics for PM2 process memory are available via the PM2 exporter:

```
pm2_process_memory_rss{process="wheeler-frgcrm-api-prod"}
pm2_process_memory_heap_total{process="wheeler-frgcrm-api-prod"}
pm2_process_memory_heap_used{process="wheeler-frgcrm-api-prod"}
```

Alert when memory growth trend exceeds 10% per 5 minutes (potential memory leak):

```yaml
# Prometheus alert rule
- alert: PM2MemoryLeak
  expr: deriv(pm2_process_memory_rss[10m]) > 0.1 * pm2_process_memory_rss
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "{{ $labels.process }} may have a memory leak"
```

### 3.4 Memory vs System RAM

When setting memory limits, account for total system RAM:

**AIOPS Node (30GB total)**:
```
System overhead:            4GB  (OS, Docker daemon, monitoring agents)
Docker containers:         10GB  (Langflow, Superset, ClickHouse, etc.)
PM2 processes:             14GB  (remaining for PM2-managed services)
  - LiteLLM:                1GB
  - FRGCRM API:           512MB
  - SurplusAI Scraper:    512MB
  - Prediction Radar (x3): 3GB  (2 workers + scheduler)
  - Brain OS:              2GB
  - OpenClaw Gateway:      1GB
  - Voice Agent:          512MB
  - Browser Agent:         1GB
  - Headroom:              5.5GB
```

**Sum of PM2 memory limits must not exceed available RAM minus headroom for
the OS, Docker, and other services.**

---

## 4. CPU Protection Strategies

### 4.1 Instance Count vs CPU Cores

AI-OPS Node has 16 vCPUs.  PM2 instance configuration must respect this:

| Configuration | Effect | Risk |
|--------------|--------|------|
| `instances: "max"` (16) + cluster | 16 Node.js processes | High CPU contention if CPU-bound |
| `instances: 8` + cluster | 8 Node.js processes | Moderate, leaves cores for Docker |
| `instances: 4` + fork | 4 independent processes | Safest, explicit resource boundaries |
| `instances: "max"` (16) + fork | 16 independent processes | Each needs unique port; resource heavy |

**Recommendation**: Use `instances: "max" / 2` (8) for cluster-mode HTTP APIs
on AIOPS to leave CPU cores for Docker containers and system processes.

### 4.2 Event Loop Lag Protection

Node.js services should monitor event loop lag.  High event loop lag (> 50ms)
indicates CPU contention or blocking operations:

```javascript
// In-app monitoring
const { monitorEventLoopDelay } = require('perf_hooks');
const histogram = monitorEventLoopDelay({ resolution: 20 });
histogram.enable();

// Export to Prometheus via /metrics endpoint
setInterval(() => {
  const p50 = histogram.percentile(50) / 1e6;   // ms
  const p99 = histogram.percentile(99) / 1e6;   // ms
  // Report: event_loop_lag_p50, event_loop_lag_p99
}, 5000);
```

PM2 triggers a restart if the event loop is unresponsive for too long
(configured via `pm2 set pm2-server-monit:event_loop_lag_max <ms>`).

### 4.3 CPU Throttling Defense

**Strategy 1: CPU Quota via cgroups** (Docker deployments):
```yaml
deploy:
  resources:
    limits:
      cpus: "2.0"    # Max 2 CPU cores
```

**Strategy 2: Worker Concurrency Limits** (in-app):
```javascript
// Limit concurrent operations
const MAX_CONCURRENT = 4;  // per instance
const semaphore = new Semaphore(MAX_CONCURRENT);
```

**Strategy 3: External Rate Limiting** (Traefik):
```yaml
# Traefik middleware: max 100 req/s per service
http:
  middlewares:
    rate-limit-api:
      rateLimit:
        average: 100
        burst: 50
```

### 4.4 CPU Alerting

Prometheus alert for sustained high CPU:

```yaml
- alert: PM2HighCPU
  expr: pm2_process_cpu_percent{process=~"wheeler-.*"} > 85
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "{{ $labels.process }} CPU > 85% for 10 minutes"
```

---

## 5. Restart Loop Detection & Recovery

### 5.1 What is a Restart Loop?

A restart loop occurs when a process exits (or is killed) and PM2 restarts it,
but the underlying cause of the exit persists.  The process repeatedly starts
and crashes, consuming resources and generating noise without providing value.

### 5.2 PM2 Built-in Protection

PM2's `max_restarts` parameter is the primary defense:
- Window: `restart_delay * max_restarts` milliseconds.
- If `max_restarts` restarts occur within the window, PM2 stops the process.
- The process status changes to `errored`.

### 5.3 Detection Methods

**Method 1: PM2 Status**
```bash
pm2 list | grep -E "errored|stopped"
```
If any process shows `errored`, investigate immediately.

**Method 2: Restart Rate Monitoring**
```bash
pm2 describe <app-name> | grep "restarts"
```
Look for rapidly increasing restart counts.

**Method 3: External Detection Script**
```bash
#!/bin/bash
# /opt/wheeler/scripts/detect-restart-loop.sh
# Check for processes with excessive restart counts
THRESHOLD=5       # restart count threshold
WINDOW_SEC=300    # 5-minute window

pm2 jlist | jq -r '.[] | "\(.name) \(.pm2_env.restart_time)"' | while read name restarts; do
  if [ "$restarts" -gt "$THRESHOLD" ]; then
    echo "WARN: $name has $restarts restarts — possible restart loop"
    # Send alert to Slack/PagerDuty
  fi
done
```

Run this via cron every 5 minutes:
```
*/5 * * * * /opt/wheeler/scripts/detect-restart-loop.sh
```

**Method 4: Log Pattern Detection**
```bash
# Check for rapid successive crash patterns
grep -E "App \[.*\] exited with code" ~/.pm2/logs/*-error.log | \
  awk '{print $1, $2}' | uniq -c | sort -rn | head
```

### 5.4 Recovery Procedures

**Step 1: Isolate the Problem**
```bash
# Stop the errored process to prevent resource consumption
pm2 stop wheeler-<service>-prod

# Check the logs for crash reason
tail -200 ~/.pm2/logs/wheeler-<service>-prod-error.log
```

**Step 2: Diagnose the Root Cause**

Common causes of restart loops:

| Cause | Symptom | Fix |
|-------|---------|-----|
| **Port already in use** | `EADDRINUSE` in logs | Find and free the port; check for stale processes |
| **Missing dependency** | `MODULE_NOT_FOUND` in logs | Install missing npm/python package |
| **Database connection failure** | `ECONNREFUSED` to COREDB | Check COREDB connectivity; verify Tailscale |
| **Environment variable missing** | `undefined` in critical path | Set the required env var |
| **Memory limit too low** | Frequent max_memory_restart | Increase memory limit or fix memory leak |
| **Disk full** | `ENOSPC` in logs | Clean up disk space; check log rotation |
| **Syntax error** | `SyntaxError` in logs | Fix the code and redeploy |
| **Corrupted cache/model file** | `Invalid file` errors | Clear cache; redownload model |
| **Segfault** | `SIGSEGV` in logs | Check native addon compatibility; update Node.js |

**Step 3: Apply Fix**
```bash
# Fix the issue, then restart
pm2 start wheeler-<service>-prod

# Reset restart counter
pm2 reset wheeler-<service>-prod
```

**Step 4: Verify Stability**
```bash
# Monitor for 5 minutes
watch -n 10 "pm2 describe wheeler-<service>-prod | grep -E 'status|restarts|memory'"
```

### 5.5 Automated Recovery

For non-critical services, automated recovery can be attempted:

```bash
#!/bin/bash
# Automated recovery attempt for restart loops
# Only use for non-critical, well-understood failure modes.

APP=$1

if pm2 describe "$APP" | grep -q "errored"; then
  echo "Detected errored process: $APP"

  # Attempt 1: Reset and restart
  pm2 reset "$APP"
  pm2 start "$APP"
  sleep 30

  if pm2 describe "$APP" | grep -q "errored"; then
    echo "Attempt 1 failed.  Escalating to on-call."
    # Stop to prevent resource waste
    pm2 stop "$APP"
    # Trigger PagerDuty alert
    exit 1
  fi

  echo "Recovered successfully."
fi
```

---

## 6. Graceful Shutdown Procedures

### 6.1 The Shutdown Sequence

When PM2 stops a process (via `pm2 stop`, `pm2 reload`, `pm2 restart`, or
`pm2 delete`), it follows this sequence:

1. PM2 sends **SIGINT** (interrupt signal) to the process.
2. If the process does not exit within `kill_timeout` milliseconds, PM2 sends
   **SIGTERM** (terminate signal).
3. If the process still does not exit, PM2 sends **SIGKILL** (force kill).
4. SIGKILL cannot be caught or ignored by the process — it dies immediately.

The application must handle SIGINT/SIGTERM to perform graceful shutdown:
- Stop accepting new connections.
- Complete in-flight requests (up to a timeout).
- Close database connections.
- Close Redis connections.
- Flush logs.
- Exit with code 0.

### 6.2 Node.js Graceful Shutdown Example

```javascript
// Graceful shutdown for Express/Fastify HTTP servers

let server;
let isShuttingDown = false;

// Start server
server = app.listen(process.env.PORT, () => {
  console.log(`Server listening on port ${process.env.PORT}`);
  process.send('ready');  // Tell PM2 we're ready
});

// Handle SIGTERM (PM2 sends this first, then SIGINT)
process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

async function gracefulShutdown() {
  if (isShuttingDown) return;
  isShuttingDown = true;

  console.log('Received shutdown signal.  Starting graceful shutdown...');

  // Step 1: Stop accepting new connections
  server.close(() => {
    console.log('HTTP server closed.  No longer accepting connections.');
  });

  // Step 2: Set a hard timeout (less than PM2 kill_timeout)
  const forceExit = setTimeout(() => {
    console.error('Forced exit after timeout.');
    process.exit(1);
  }, 8000);  // 8 seconds (must be < 10s kill_timeout)

  try {
    // Step 3: Complete in-flight requests (already handled by server.close)
    // Step 4: Close database connections
    await database.disconnect();
    console.log('Database connections closed.');

    // Step 5: Close Redis connection
    await redis.quit();
    console.log('Redis connection closed.');

    // Step 6: Flush logs
    // (Winston/Bunyan can be flushed here)

    clearTimeout(forceExit);
    console.log('Graceful shutdown complete.');
    process.exit(0);
  } catch (err) {
    console.error('Error during graceful shutdown:', err);
    clearTimeout(forceExit);
    process.exit(1);
  }
}

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err);
  gracefulShutdown().finally(() => process.exit(1));
});
```

### 6.3 Python Graceful Shutdown Example

```python
# Graceful shutdown for Python services (uvicorn, FastAPI)

import signal
import sys
import asyncio

async def shutdown():
    """Perform graceful shutdown."""
    print("Starting graceful shutdown...")

    # Close database connections
    await database.disconnect()

    # Close Redis connections
    await redis.close()

    print("Graceful shutdown complete.")

def handle_sigterm(signum, frame):
    """Handle SIGTERM by running shutdown in the event loop."""
    print(f"Received signal {signum}.  Shutting down...")
    loop = asyncio.get_event_loop()
    loop.create_task(shutdown())
    # Give shutdown tasks time to complete
    loop.call_later(5, sys.exit, 0)

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)

# For uvicorn, set a graceful timeout:
# uvicorn.run(app, host="0.0.0.0", port=8080, timeout_graceful_shutdown=5)
```

### 6.4 PM2 Reload (Zero-Downtime)

For cluster-mode services, `pm2 reload` performs a rolling restart:

1. PM2 starts a new worker instance.
2. The new worker sends the 'ready' signal.
3. PM2 sends SIGINT to the oldest worker.
4. The old worker shuts down gracefully.
5. Steps 1-4 repeat for each instance.

Requirements for zero-downtime reload:
- `exec_mode: "cluster"`
- `wait_ready: true`
- The application handles SIGINT for graceful shutdown.
- The application emits `process.send('ready')` after the server is listening.

```bash
# Zero-downtime reload
pm2 reload wheeler-frgcrm-api-prod

# If changes include environment variables or exec_mode changes:
pm2 stop wheeler-frgcrm-api-prod
pm2 start ecosystem.config.js --only wheeler-frgcrm-api-prod
```

### 6.5 Service-Specific Shutdown Timeouts

| Service Type | kill_timeout | Rationale |
|-------------|-------------|-----------|
| **REST API** (quick requests) | 5000ms | Requests complete quickly; no long polling |
| **REST API** (file uploads) | 15000ms | Allow in-flight uploads to complete |
| **AI Worker** (LLM calls) | 30000ms | Wait for in-flight LLM API calls |
| **Browser Agent** | 15000ms | Close browser tabs gracefully |
| **Voice Agent** | 10000ms | End active calls; short enough to not hold up |
| **Data Worker** (ETL) | 60000ms | Allow batch to reach checkpoint |
| **WebSocket Server** | 10000ms | Close connections with close frame |

---

## 7. Service-Specific Policies

### 7.1 Complete Wheeler PM2 Service Policy Reference

| Service | Mode | Instances | Memory | kill_timeout | restart_delay |
|---------|------|-----------|--------|-------------|---------------|
| LiteLLM | fork | 1 | 1G | 10000 | 5000 |
| FRGCRM API | cluster | max | 512M | 8000 | 3000 |
| SurplusAI Scraper | fork | 1 | 512M | 15000 | 5000 |
| Prediction Radar Worker | fork | 2 | 1G | 30000 | 10000 |
| Prediction Radar Scheduler | fork | 1 | 512M | 10000 | 10000 |
| Wheeler Brain OS | cluster | max | 2G | 15000 | 5000 |
| OpenClaw Gateway | cluster | max | 1G | 10000 | 5000 |
| Voice Agent | fork | 1 | 512M | 10000 | 5000 |
| Browser Agent | fork | 1 | 1G | 15000 | 5000 |

### 7.2 Changing Restart Policies

To change a restart policy:

1. Update `ecosystem.config.js` with the new values.
2. Stop the service: `pm2 stop <service-name>`.
   (Do NOT use `pm2 reload` — parameter changes require a full stop/start.)
3. Start the service: `pm2 start ecosystem.config.js --only <service-name>`.
4. Verify the new settings: `pm2 describe <service-name>`.
5. Save the process list: `pm2 save --force`.

### 7.3 Emergency Policy Override

In case of repeated unexplained crashes, temporarily increase restart tolerance:

```bash
# Emergency override: allow more restarts for investigation breathing room
pm2 set wheeler-frgcrm-api-prod max_restarts 20
pm2 set wheeler-frgcrm-api-prod restart_delay 10000
```

This gives the on-call engineer 200 seconds (20 * 10s) to investigate without
the process being stopped.  Revert to standard values after investigation:

```bash
pm2 set wheeler-frgcrm-api-prod max_restarts 10
pm2 set wheeler-frgcrm-api-prod restart_delay 5000
pm2 save --force
```

**Do not forget to revert.**  Extended restart tolerance masks real problems
and can cause resource exhaustion.

---

## Appendix A — Restart Policy Audit Script

```bash
#!/bin/bash
# /opt/wheeler/scripts/audit-restart-policies.sh
# Audits all PM2 processes against documented restart policies.

echo "=== PM2 Restart Policy Audit ==="

pm2 jlist | jq -r '.[] | "\(.name) | mode=\(.pm2_env.exec_mode) | instances=\(.pm2_env.instances) | max_restarts=\(.pm2_env.max_restarts) | restart_delay=\(.pm2_env.restart_delay) | max_memory=\(.pm2_env.max_memory_restart) | kill_timeout=\(.pm2_env.kill_timeout)"'

echo ""
echo "Compare against the policy table in restart-policy.md Section 7.1."
echo "Flag any deviations for review."
```

## Appendix B — Restart Loop Alert Rule (Prometheus)

```yaml
groups:
  - name: pm2_alerts
    rules:
      - alert: PM2ProcessErrored
        expr: pm2_process_status{status="errored"} == 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PM2 process {{ $labels.process }} is in errored state"
          description: "The process has exceeded max_restarts and is stopped."

      - alert: PM2HighRestartRate
        expr: rate(pm2_process_restarts_total[5m]) * 300 > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PM2 process {{ $labels.process }} is restarting frequently"
          description: "{{ $value }} restarts in the last 5 minutes."

      - alert: PM2MemoryNearLimit
        expr: pm2_process_memory_rss / on(process) pm2_process_max_memory * 100 > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "PM2 process {{ $labels.process }} memory usage > 85% of limit"
```
