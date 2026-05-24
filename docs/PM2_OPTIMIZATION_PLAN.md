# PM2 Optimization Plan -- Phase 2
## Target: AIOPS Server (5.78.140.118)

**Generated:** 2026-05-23 07:13 UTC
**Author:** Principal Infrastructure Optimization Engineer
**Status:** READ-ONLY AUDIT -- No changes applied

---

## 1. Executive Summary

A comprehensive audit of the Wheeler AIOPS PM2 ecosystem was conducted against the current running state. The server hosts 17 online processes (total ~1.95 GB RSS) on a 16-core / 30 GB RAM Hetzner CPX51 node. Three services show restart histories indicating unresolved dependency or configuration defects. All services run in fork mode with watching disabled and autorestart enabled. No cluster mode is in use, leaving significant throughput headroom on the table for I/O-bound services. Log growth is modest (7.3 MB total) but the two largest error logs (frgcrm-api at 5.7 MB, litellm at 322 KB) are driven by repeat-failure loops that should be addressed at root cause rather than by log rotation alone.

---

## 2. System Resource Profile

```
Host:          Hetzner CPX51 (AIOPS)
Hostname:      wheeler-aiops-01
Tailscale IP:  100.121.230.28
OS:            Linux (6.8.0-111-generic)
CPU:           16 cores
RAM:           30 GB total, ~13 GB available
Swap:          8 GB (512 KB used)
Load avg:      4.16 / 3.25 / 2.57
Uptime:        14 days 7h
```

**Resource headroom:** Ample. Total PM2 memory footprint is ~1.95 GB out of 30 GB (6.5%). Even with a 2x safety margin for growth and leak headroom, there is 10+ GB available for additional workloads or cluster-mode scaling.

---

## 3. Current PM2 State (Live Audit)

### 3.1 Online Processes (17 total)

| # | Process Name | PID | Memory | CPU | Restarts | Interpreter | max_memory_restart |
|---|-------------|-----|--------|-----|----------|-------------|-------------------|
| 1 | pm2-logrotate (module) | 2144808 | 94 MB | 0.3% | 0 | node | 500M |
| 2 | litellm | 120586 | 361 MB | 0.1% | **5** | python3 | **NOT SET** |
| 3 | frgcrm-api | 2358745 | 236 MB | 0.1% | **4** | none | 2G |
| 4 | openclaw-dashboard | 2360824 | 67 MB | 0.1% | 0 | node | 256M |
| 5 | ecosystem-guardian | 3153376 | 70 MB | 0.1% | 0 | node | 200M |
| 6 | voice-outreach-service | 3367659 | 54 MB | 0.1% | 0 | none | **NOT SET** |
| 7 | war-room-server | 3925091 | 65 MB | 0% | 1 | none | **NOT SET** |
| 8 | event-bus-relay | 223182 | 66 MB | 0.1% | 0 | node | 150M |
| 9 | design-agent-svc | 3819275 | 116 MB | 0.1% | 0 | node | 500M |
| 10 | horizon-agent-svc | 3819493 | 109 MB | 0.3% | 0 | node | 500M |
| 11 | paperless-agent-svc | 3819745 | 107 MB | 0.1% | 0 | node | 500M |
| 12 | prediction-radar-agent-svc | 3819956 | 107 MB | 0.1% | 0 | node | 500M |
| 13 | ravyn-agent-svc | 3820164 | 108 MB | 0.1% | 0 | node | 500M |
| 14 | frgcrm-agent-svc | 3820365 | 101 MB | 0.1% | 0 | node | 500M |
| 15 | insforge-agent-svc | 3820605 | 73 MB | 0.1% | 0 | node | 500M |
| 16 | surplusai-scraper-agent-svc | 3820831 | 108 MB | 0.1% | 0 | node | 500M |
| 17 | voice-agent-svc | 3821078 | 107 MB | 0.3% | 0 | node | 500M |

**Total RSS:** 1,950 MB (~1.9 GB)
**All processes:** fork mode, watch disabled, autorestart true (except backup-verification)

### 3.2 Stopped Processes (1 total)

| # | Process Name | Reason |
|---|-------------|--------|
| 1 | backup-verification | Intentionally stopped (autorestart=false) |

Note: 20 additional processes previously registered in PM2 have been removed via `pm2 delete`, reducing the process table from 37 to 18 entries. This is a healthy cleanup.

---

## 4. Root Cause Analysis -- Restart Loops

### 4.1 litellm (5 restarts) -- CRITICAL

**Root cause:** Missing Python dependency `websockets` and missing Redis authentication.

Error log evidence:
```
ModuleNotFoundError: Missing dependency No module named 'websockets'.
Run `pip install 'litellm[proxy]'`
```

Additionally, Redis cache operations fail with `Authentication required`, indicating the Redis URL lacks a password or the password is incorrect. The config specifies `redis://COREDB:6379` with no auth credentials, but the Redis instance requires authentication.

**Impact:** Every time litellm attempts certain Redis cache operations or handles websocket-dependent features, it crashes. PM2 restarts it. The 5 restarts span a ~2h uptime window, suggesting 2-3 crash/recovery cycles per hour during active use.

**Fix:**
1. `pip install 'litellm[proxy]'` to install websockets
2. Update REDIS_URL from `redis://COREDB:6379` to `redis://:PASSWORD@COREDB:6379` or set `LITELLM_CACHE_REDIS_PASSWORD`

### 4.2 frgcrm-api (4 restarts) -- HIGH

**Root cause:** Database connection misconfiguration in the scheduler component. While the PM2 env has `DATABASE_URL` pointing to COREDB (`100.118.166.117`), the internal scheduler code hardcodes `127.0.0.1:5432` for a different database query path.

Error log evidence:
```
psycopg2.OperationalError: connection to server at "127.0.0.1", port 5432 failed: Connection refused
Is the server running on that host and accepting TCP/IP connections?
```

The crash originates in `surplusai_event_consumer_job` at `/opt/wheeler/apps/frgcrm/api/scheduler.py:393`.

**Impact:** Every 60 seconds the scheduler attempts to connect to a non-existent local PostgreSQL, fails, and logs a full traceback. This does not consistently crash the main process (which stays online for 3h) but the 4 restarts indicate that some failure paths do terminate the process.

**Fix:**
1. Audit `scheduler.py` for hardcoded `127.0.0.1:5432` references, replace with environment-variable-driven config
2. Verify that the uvicorn process uses the correct `DATABASE_URL` from PM2 env

### 4.3 war-room-server (1 restart) -- LOW

**Root cause:** Missing Python dependency `psycopg2`.

Error log evidence:
```
ModuleNotFoundError: No module named 'psycopg2'
```

**Fix:** `pip install psycopg2-binary` in the relevant virtual environment.

### 4.4 event-bus-relay -- WARNING (previously in restart loop, now stable)

**Root cause:** Missing npm dependency `ioredis`.

Error log evidence (from earlier restart cycle):
```
Error: Cannot find module 'ioredis'
```

The relay restarted every 5 seconds for an extended period before the module was installed or the restart limit was exhausted. It is currently online (65.8 MB, 0 restarts shown -- meaning the counter was reset after stabilization).

**Fix:** Verify `ioredis` is installed in `/opt/apps/wheeler-brain-os/node_modules/`. If the relay runs from a different cwd, install it there.

---

## 5. Memory Leak Indicators

### 5.1 Current Assessment

All 17 online processes have been running for 2-3h with stable memory footprints. No process shows anomalous growth relative to its uptime:

| Process | Memory | Uptime | Memory/Hour (rate) | Assessment |
|---------|--------|--------|---------------------|------------|
| litellm | 361 MB | 2h | ~180 MB/h steady-state | Normal for LiteLLM proxy with model metadata |
| frgcrm-api | 236 MB | 3h | ~79 MB/h steady-state | Normal for Python/Uvicorn + SQLAlchemy |
| Agent services (8x) | ~108 MB avg | 112m | Stable | Consistent across all 8 agents -- no divergence |
| ecosystem-guardian | 70 MB | 3h | Stable | Normal for monitoring daemon |

**Verdict:** No active memory leaks detected. All processes show flat or expected memory profiles for their runtime. However, three services lack `max_memory_restart` safety nets (see Section 7).

### 5.2 Long-Term Monitoring

Without `max_memory_restart` on litellm, voice-outreach-service, and war-room-server, there is no automatic protection against future leaks. These three must have caps added.

---

## 6. Worker Count Analysis

### 6.1 Uvicorn Workers (frcgm-api)

The frgcrm-api is launched via uvicorn with `--workers 2` (per the active `.cjs` config). On a 16-core node, this underutilizes available CPU. However, uvicorn workers are independent processes each with their own memory footprint (~120 MB/worker), so scaling to 8 workers would consume ~1 GB for frgcrm-api alone.

**Current:** 2 workers
**Recommendation:** Increase to 4 workers. The load average of 4.16 suggests the system can absorb this, and the current memory footprint of 236 MB (for 2 workers + scheduler) leaves room.

### 6.2 Agent Service Workers (8 agent-svc processes)

All 8 agent services run as single-instance fork-mode Node.js processes. Each implements a polling loop at 5-minute intervals. This is architecturally correct -- adding instances would cause duplicate polling and potential race conditions on shared state.

**Current:** 1 instance each (correct)
**Recommendation:** No change. Cluster mode would be harmful for polling-based services.

### 6.3 LiteLLM Instances

LiteLLM is an I/O-bound proxy handling multiple LLM API backends. It runs as a single fork-mode instance.

**Current:** 1 instance
**Recommendation:** Increase to 2 instances with cluster mode. LiteLLM is stateless (state is in Redis) and the proxy benefits from concurrent request handling.

---

## 7. Memory Cap Recommendations

| Process | Current Cap | Current Mem | Recommended Cap | Rationale |
|---------|------------|-------------|-----------------|-----------|
| litellm | **NOT SET** | 361 MB | **768M** | Needs protection; 2x current usage for model metadata growth |
| frgcrm-api | 2G | 236 MB | **1G** | 2G is wasteful headroom for a 236MB process; 4x current usage |
| voice-outreach-service | **NOT SET** | 54 MB | **256M** | Python service, needs safety net |
| war-room-server | **NOT SET** | 65 MB | **256M** | Python service, needs safety net |
| openclaw-dashboard | 256M | 67 MB | **256M** | Current cap is appropriate |
| ecosystem-guardian | 200M | 70 MB | **200M** | Current cap is appropriate |
| event-bus-relay | 150M | 66 MB | **200M** | Too close to current usage; increase to 200M |
| design-agent-svc | 500M | 116 MB | **400M** | 500M is generous for a 116MB process; reduce to 400M |
| horizon-agent-svc | 500M | 109 MB | **400M** | Same as above |
| paperless-agent-svc | 500M | 107 MB | **400M** | Same as above |
| prediction-radar-agent-svc | 500M | 107 MB | **400M** | Same as above |
| ravyn-agent-svc | 500M | 108 MB | **400M** | Same as above |
| frgcrm-agent-svc | 500M | 101 MB | **400M** | Same as above |
| insforge-agent-svc | 500M | 73 MB | **300M** | Smallest agent, tighter cap |
| surplusai-scraper-agent-svc | 500M | 108 MB | **400M** | Same as others |
| voice-agent-svc | 500M | 107 MB | **400M** | Same as others |

**Total max memory budget under recommended caps:** ~6.5 GB (worst case all at cap simultaneously). With 13 GB available, this leaves 50% headroom.

---

## 8. Log Growth Analysis

### 8.1 Current State

```
Total log size: 7.3 MB
Location: /root/.pm2/logs/

Top files:
  5.7 MB  frgcrm-api-error.log    -- DB connection failure repeated every 60s
  642 KB  frgcrm-mirror-test-error.log -- Legacy, process no longer running
  322 KB  litellm-error.log       -- Missing websockets module, Redis auth failures
  305 KB  ecosystem-guardian-out.log -- Normal monitoring output
   94 KB  frgcrm-mirror-test-out.log  -- Legacy
   72 KB  litellm-out.log         -- Normal
   49 KB  war-room-server-error.log  -- Missing psycopg2
   36 KB  event-bus-relay-error.log  -- Missing ioredis (now resolved)
```

### 8.2 Issues

1. **frcgm-api-error.log (5.7 MB):** Growing rapidly due to repeated DB connection failures in the scheduler. Fixing the root cause will stop this growth.
2. **Legacy logs:** frgcrm-mirror-test logs remain from a decommissioned process. These should be archived or deleted.
3. **Scattered log locations:** Some services log to `/root/.pm2/logs/`, others to `/opt/logs/`, and agent services log to their own `./logs/` directories. No unified log aggregation.

### 8.3 Recommendations

1. Standardize all log output to `/opt/logs/pm2/<service-name>/` with the pattern `error.log` and `out.log`
2. Enable pm2-logrotate with 30-day retention, 10 MB max file size, max 5 files per service
3. Clean up legacy frgcrm-mirror-test logs after archiving
4. Fix root causes of error-log spam (items 4.1-4.3) to eliminate the growth at source

---

## 9. Cluster Mode Assessment

### 9.1 Candidates for Cluster Mode

| Service | Suitable? | Instances | Rationale |
|---------|-----------|-----------|-----------|
| litellm | **YES** | 2 | I/O-bound proxy, stateless (state in Redis), benefits from concurrent request handling |
| openclaw-dashboard | YES | 2 | Lightweight Express server, stateless |
| ecosystem-guardian | NO | 1 | Singleton monitor; multiple instances would duplicate alerts |
| event-bus-relay | NO | 1 | Singleton event relay; duplicates would cause double-delivery |
| frgcrm-api | N/A | fork | Uses uvicorn with `--workers` flag for internal multiprocessing |
| Agent services (8x) | **NO** | 1 each | Polling-based; cluster mode would cause duplicate polling and race conditions |
| voice-outreach-service | NO | 1 | Stateful call handling |
| war-room-server | NO | 1 | Python, not Node.js cluster compatible |

### 9.2 Why Not Cluster Mode for Agent Services

All 8 agent-svc processes share a common architecture:
- 5-minute polling interval (`POLLING_INTERVAL_MS: 300000`)
- Connect to centralized DB/Redis on COREDB via Tailscale
- Use DEEPSEEK_API_KEY (some direct, some via litellm proxy on localhost:4049)

Running these in cluster mode would launch N duplicate instances, each independently polling the same data sources and potentially processing the same records, leading to duplicate work, API key rate-limit exhaustion, and data integrity issues.

**Recommendation:** Keep agent services in fork mode with single instances. Their workload is controlled by polling frequency, not by concurrent request handling capacity.

---

## 10. Autorestart Tuning

| Service | Current | Recommended | Rationale |
|---------|---------|-------------|-----------|
| litellm | true | true | Critical infrastructure; must auto-recover |
| frgcrm-api | true | true | Critical API; must auto-recover |
| openclaw-dashboard | true | true | User-facing dashboard |
| ecosystem-guardian | true | true | Monitoring daemon; must keep running |
| voice-outreach-service | true | true | Production voice service |
| war-room-server | true | true | Production service |
| event-bus-relay | true | true | Event pipeline |
| design-agent-svc | true | true | Background agent, non-critical timing |
| horizon-agent-svc | true | true | Background agent |
| paperless-agent-svc | true | true | Background agent |
| prediction-radar-agent-svc | true | true | Background agent |
| ravyn-agent-svc | true | true | Background agent |
| frgcrm-agent-svc | true | true | Background agent |
| insforge-agent-svc | true | true | Background agent |
| surplusai-scraper-agent-svc | true | true | Background agent |
| voice-agent-svc | true | true | Background agent |
| backup-verification | false | false | Intentionally stopped batch job; manual run only |

**Restart delay uniformity:** All services use 5000ms restart delay except war-room-server (2000ms). Standardize to 5000ms for all services.

**Max restarts uniformity:** Most services use max_restarts=10. The canonical config at `/opt/wheeler/ecosystem.config.js` uses different values per service type:
- API Gateway: 10
- AI/ML Workers: 5 (model loading is expensive; don't loop)
- LiteLLM: 5

**Recommendation:** Adopt tiered max_restarts:
- Critical services (litellm, frgcrm-api): 10 max_restarts
- Agent services: 5 max_restarts (polling, self-healing not time-critical)
- Infrastructure (guardian, relay, dashboard): 5 max_restarts

---

## 11. Duplicate Config Detection

### 11.1 Findings

The following four services have ecosystem config files in **both** `/opt/apps/` and `/opt/opt/apps/`:

| Service | /opt/apps/ config | /opt/opt/apps/ config | Conflict? |
|---------|-------------------|-----------------------|-----------|
| design-agent-svc | 793 bytes, May 23 05:12 | 635 bytes, May 20 21:58 | **YES -- different content** |
| prediction-radar-agent-svc | present | present | LIKELY |
| ravyn-agent-svc | present | present | LIKELY |
| wheeler-brain-os | present | present | LIKELY |

The `/opt/opt/apps/` directory is **not a symlink** -- it is a separate physical directory containing older config versions. The `/opt/apps/` versions were updated more recently (May 23 vs. May 20).

**Impact:** PM2 process definitions may differ depending on which config file was used to start the process. This creates configuration drift and ambiguity about which settings are actually in effect.

**Fix:** Consolidate to `/opt/apps/<service>/ecosystem.config.js` as the single source of truth. Archive or delete `/opt/opt/apps/` copies.

### 11.2 frgcrm-api Triple Config

frgcrm-api has **three** competing config files:
1. `/opt/wheeler/apps/frgcrm/api/ecosystem.config.js` -- port 8002, workers 4
2. `/opt/wheeler/apps/frgcrm/api/ecosystem.config.cjs` -- port 8082, workers 2 **(CURRENTLY ACTIVE)**
3. `/opt/wheeler/apps/frgcrm/pm2.config.js` -- port 8004 (staging)

The currently active config (cjs) is the one that was last used to start the process. The other two are stale and create confusion.

**Fix:** Consolidate to single `ecosystem.config.cjs` at `/opt/wheeler/apps/frgcrm/api/` with the correct port 8082 configuration.

---

## 12. Optimization Summary

### 12.1 Immediate Fixes (dependency installs)

| Priority | Action | Command |
|----------|--------|---------|
| CRITICAL | Install litellm proxy deps | `pip install 'litellm[proxy]'` |
| CRITICAL | Fix Redis auth for litellm | Update REDIS_URL with password |
| HIGH | Fix frgcrm-api DB config | Audit scheduler.py for hardcoded localhost |
| LOW | Install psycopg2 for war-room | `pip install psycopg2-binary` |
| LOW | Verify ioredis for event-bus-relay | `npm ls ioredis` in relay cwd |

### 12.2 Configuration Changes

| Priority | Change | Impact |
|----------|--------|--------|
| HIGH | Add `max_memory_restart: 768M` to litellm | Safety net for un-capped 361MB process |
| HIGH | Add `max_memory_restart: 256M` to voice-outreach-service | Safety net |
| HIGH | Add `max_memory_restart: 256M` to war-room-server | Safety net |
| MEDIUM | Reduce frgcrm-api max_memory_restart from 2G to 1G | Tighter guardrail |
| MEDIUM | Reduce agent-svc caps from 500M to 400M | Consistent, proportional limit |
| MEDIUM | Cluster mode for litellm (2 instances) | Better proxy throughput |
| MEDIUM | Cluster mode for openclaw-dashboard (2 instances) | Better dashboard throughput |
| LOW | Standardize restart_delay to 5000ms | Consistent behavior |
| LOW | Adopt tiered max_restarts (10/5/5) | Appropriate per service type |
| LOW | Consolidate duplicate config directories | Single source of truth |

### 12.3 Cleanup

| Action | Detail |
|--------|--------|
| Remove /opt/opt/apps/*/ecosystem.config.js duplicates | Archive then delete |
| Consolidate frgcrm-api to single config | Keep cjs, delete js and pm2.config.js |
| Archive legacy frgcrm-mirror-test logs | Compress and remove from active log dir |
| Standardize log paths | Move all to /opt/logs/pm2/<service-name>/ |

---

## 13. Rollout Phases

### Phase A: Dependency Remediation (read-only verification, then apply)
1. Install missing Python packages (websockets, psycopg2)
2. Verify ioredis installation
3. Fix Redis authentication in litellm config
4. Fix frgcrm-api scheduler DB connection string
5. Observe for 24h -- verify restart counts stop incrementing

### Phase B: Configuration Hardening (apply optimized ecosystem config)
1. Deploy new `optimized-ecosystem.config.js`
2. `pm2 reload` all affected services
3. Verify all 17 services come online with correct memory caps
4. Monitor for 1h

### Phase C: Cluster Mode Rollout
1. Convert litellm to cluster mode (2 instances)
2. Convert openclaw-dashboard to cluster mode (2 instances)
3. Load-test to verify no regression
4. Monitor memory per instance

### Phase D: Cleanup
1. Consolidate duplicate config files
2. Archive legacy logs
3. Standardize log paths
4. Update pm2-logrotate configuration

---

## 14. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| litellm cluster mode causes port conflicts | Low | High | Litellm uses single port; cluster mode handles socket sharing via Node.js cluster |
| Agent service memory caps too tight | Low | Medium | Caps at 400M allow 3.5x headroom above current 108MB usage; monitor for 1 week |
| Config consolidation breaks service start | Low | Medium | Backup all configs before deletion; test each service start individually |
| frgcrm-api scheduler fix requires code change | Medium | Low | Read-only audit first; code change done separately |
| pm2 reload causes brief outage | Low | Low | `pm2 reload` is zero-downtime for cluster mode; fork mode has sub-second restart |

---

## 15. Generated Artifacts

This plan is accompanied by two executable artifacts in `/root/templates/pm2/`:

1. **`optimized-ecosystem.config.js`** -- Complete optimized PM2 ecosystem configuration with all recommendations applied
2. **`apply-optimizations.sh`** -- Safe deployment script with backup, dry-run, and rollback capabilities

**IMPORTANT:** Both artifacts must be reviewed by a human operator before execution. They are generated as READ-ONLY analysis -- this plan intentionally makes NO changes to the running system.
