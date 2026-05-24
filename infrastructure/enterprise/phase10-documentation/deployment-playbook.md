# Wheeler Enterprise — Deployment Playbook

**Version:** 1.0.0 | **Last Updated:** 2026-05-23 | **Owner:** SRE Team
**Classification:** Critical — Operational

---

## 1. Deployment Types

```
Type                    Scope                  Risk    Approval        Window
──────────────────────  ─────────────────────  ──────  ──────────────  ──────────
Hotfix (P1)             Single service patch   LOW     Post-deploy     Any time
Feature Deploy          New feature release    MEDIUM  Standard         Business hours
Infrastructure Change   Config, network, FW    HIGH    SRE Lead         Maintenance window
Dependency Update       Third-party packages   MEDIUM  Standard         Business hours
Database Migration      Schema change          HIGH    DBA + SRE Lead   Maintenance window
Full-Stack Deploy       Multiple services       CRITICAL  CTO + SRE Lead  Scheduled window
Security Patch          CVE fix                 HIGH    SRE Lead         Any time (with care)
Rollback (any)          Revert to old version   MEDIUM  Post-execute     Any time
```

### 1.1 Emergency Deployment (Hotfix)

```
 USE WHEN: P1/P2 incident requires immediate code change.

 BYPASSES:
  ├ Normal approval process (retroactively approved)
  ├ Maintenance window restriction
  └ Full test suite (smoke tests only — pick the critical path)

 REQUIRES:
  [ ] Brief justification documented (1-2 sentences)
  [ ] At least two engineers aware (pair deploy)
  [ ] Rollback plan prepared and tested
  [ ] Post-deploy monitoring for 30 minutes minimum
  [ ] Retroactive approval from SRE Lead within 24 hours
  [ ] Post-mortem if the hotfix itself caused issues

 PROCEDURE:
 ──────────
 1. Announce in #infra-notices: "EMERGENCY DEPLOY: <service> — <reason>"
 2. Verify backup is current (last successful < 24 hours ago)
 3. Deploy following the standard procedure for the service type
 4. Run smoke tests immediately
 5. Monitor for 30 minutes (Grafana dashboards open)
 6. Update #infra-notices with results
 7. Log the deployment in deployment-log.txt
 8. File retroactive approval request
```

---

## 2. Pre-Deployment Checklist

```
 ╔═══════════════════════════════════════════════════════════════╗
 ║  THIS CHECKLIST MUST BE COMPLETED BEFORE EVERY DEPLOYMENT.   ║
 ║  NO EXCEPTIONS. EVEN HOTFIXES REQUIRE ITEMS MARKED [REQ].    ║
 ╚═══════════════════════════════════════════════════════════════╝

 [ ] BACKUPS [REQ]
     [ ] Database backups completed within last 24 hours
     [ ] Volume backups completed within last 24 hours
     [ ] Config backups captured (docker-compose.yml, traefik config)
     [ ] Current image tags recorded (`docker ps --format '{{.Image}}'`)
     [ ] Current PM2 state saved (`pm2 save`)

 [ ] TESTING [REQ]
     [ ] Tests pass in CI/CD pipeline
     [ ] No known regressions
     [ ] Database migrations tested in staging/QA environment
     [ ] Down migration tested (for DB changes)
     [ ] Load/performance impact assessed (if applicable)

 [ ] APPROVAL
     [ ] Change window approved (see Section 6)
     [ ] SRE Lead or CTO approval (if required by deployment type)
     [ ] DBA approval (if database migration)
     [ ] Security review (if infrastructure change)

 [ ] NOTIFICATION
     [ ] Team notified in #infra-notices at least 30 minutes before
     [ ] Users notified via status page (if expected downtime > 0)
     [ ] On-call engineer aware and monitoring during deploy

 [ ] ROLLBACK PLAN [REQ]
     [ ] Rollback procedure documented and tested
     [ ] Previous version/image tag identified
     [ ] Database rollback tested (if migration included)
     [ ] Configuration rollback tested (if config change)
     [ ] Estimated rollback time: < __ minutes

 [ ] MONITORING [REQ]
     [ ] Grafana dashboards open for the service being deployed
     [ ] Alertmanager silence created for expected alerts (if any)
     [ ] Uptime Kuma monitors paused for the service (if applicable)
     [ ] Log aggregation confirmed working (Loki receiving logs)

 [ ] DEPENDENCY CHECK
     [ ] All upstream dependencies stable (database, Redis, NATS)
     [ ] All dependent services identified and verified healthy
     [ ] API compatibility verified (breaking changes communicated)
     [ ] Environment variables reviewed (new vars added? old removed?)
```

---

## 3. Docker Service Deployment

### 3.1 Full Step-by-Step Procedure

```
 ESTIMATED DURATION: 5-10 minutes per service
 DOWNTIME: 0-30 seconds (rolling restart via Docker Compose)

 ─────────────────────────────────────────────────────────────────────

 STEP 1: PREPARE AND BACKUP (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. SSH to the target server via Tailscale:
    ┌─────────────────────────────────────────────────────────────┐
    │ ssh root@100.121.230.28  # AIOPS                           │
    │ # or                                                       │
    │ ssh root@100.98.163.17    # EDGE                            │
    └─────────────────────────────────────────────────────────────┘

 2. Record current state:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/aiops/<service-dir>                │
    │                                                           │
    │ # Record current image tags                               │
    │ docker ps --filter "name=<service>" --format '{{.Image}}' \│
    │   > /tmp/pre-deploy-image-$(date +%Y%m%d-%H%M%S).txt     │
    │                                                           │
    │ # Backup compose file                                     │
    │ cp docker-compose.yml docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S) │
    └─────────────────────────────────────────────────────────────┘

 3. Pull the new image:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker compose pull <service-name>                         │
    │ # Expected output:                                         │
    │ # [+] Pulling 1/1                                          │
    │ #  ✔ <service> Pulled                                     │
    │ #  ✔ <digest> Already exists or freshly pulled            │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: DEPLOY (1-2 min)
 ─────────────────────────────────────────────────────────────────────
 ⚠ Use rolling update to minimize downtime:

 ┌─────────────────────────────────────────────────────────────┐
 │ # Option A: Rolling update (preferred, zero-downtime)       │
 │ docker compose up -d <service-name>                         │
 │                                                           │
 │ # Expected output:                                         │
 │ # [+] Running 1/1                                          │
 │ #  ✔ Container <service>  Started                         │
 │                                                           │
 │ # Option B: Full restart (if config changed significantly) │
 │ docker compose stop <service-name>                         │
 │ docker compose up -d <service-name>                        │
 │                                                           │
 │ # Option C: Blue-green (for critical services, see 6.5)    │
 │ docker compose -f docker-compose-blue.yml up -d             │
 │ # ... validate ... switch Traefik ... stop green           │
 └─────────────────────────────────────────────────────────────┘

 3. Watch container start:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker ps --filter "name=<service>" --format '{{.Status}}'  │
    │ # Expected: "Up 10 seconds (healthy)"                      │
    │                                                           │
    │ docker logs --tail 20 <service-name>                     │
    │ # Check for startup errors                                │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: VALIDATE DEPLOYMENT (3 min)
 ─────────────────────────────────────────────────────────────────────
 1. Health check:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Container health                                         │
    │ docker ps --filter "name=<service>" --filter "health=healthy" -q │
    │ # Should return container ID if healthy                    │
    │                                                           │
    │ # API health endpoint                                     │
    │ curl -f http://localhost:<port>/health                    │
    │ # Expected: HTTP 200                                      │
    └─────────────────────────────────────────────────────────────┘

 2. Log check:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker logs --tail 50 <service-name> 2>&1 | \             │
    │   grep -iE 'error|fail|panic|fatal'                       │
    │ # Expected: NO OUTPUT (no errors)                          │
    └─────────────────────────────────────────────────────────────┘

 3. Metrics check:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Open Grafana dashboard for this service                  │
    │ # Check within 3 minutes:                                  │
    │ # [ ] Request rate normal (not spiking or zero)            │
    │ # [ ] Error rate < 0.5%                                   │
    │ # [ ] P95 latency within baseline                          │
    │ # [ ] Container CPU/memory within expected range           │
    │ # [ ] No restart loops (restart count stable)              │
    └─────────────────────────────────────────────────────────────┘

 4. Cross-service check:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Verify dependencies still accessible                     │
    │ docker exec <service-name> curl -sf http://postgres:5432   │
    │ docker exec <service-name> redis-cli -h redis PING        │
    │                                                           │
    │ # Verify upstream services still reach this service       │
    │ curl -f https://<service>.wheeler.ai/health              │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: FINALIZE (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. Mark deployment complete:
    ┌─────────────────────────────────────────────────────────────┐
    │ echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | DEPLOY | <service> | \│
    │   <old-version> → <new-version> | SUCCESS | $(whoami)" \   │
    │   >> /root/infrastructure/deployment-log.txt              │
    └─────────────────────────────────────────────────────────────┘

 2. Announce in Slack:
    ┌─────────────────────────────────────────────────────────────┐
    │ "DEPLOY COMPLETE: <service> <old-version> → <new-version>" │
    │ "Health: PASS | Errors: 0 | Latency: normal"               │
    │ "Monitoring for 30 min"                                    │
    └─────────────────────────────────────────────────────────────┘

 3. Monitor for 30 minutes (standard deploy) or 2 hours (major deploy).
    Keep Grafana dashboard open. DO NOT close your laptop.

 4. If anything goes wrong: SEE ROLLBACK PLAYBOOK.
```

### 3.2 Expected Output at Each Step

```
 COMMAND                                    EXPECTED OUTPUT
 ─────────────────────────────────────────  ─────────────────────────
 docker compose pull <svc>                  Pulling... Pulled. Digest: sha256:abc123...
 docker compose up -d <svc>                 [+] Running 1/1
                                            ✔ Container <svc> Started
 docker ps --filter name=<svc>              <svc>   Up 10 seconds (healthy)
 curl localhost:<port>/health               {"status":"ok","version":"1.2.3"}
 docker logs --tail 20 <svc>                [INFO] Server started on port XXXX
                                            [INFO] Database connection established
```

### 3.3 Common Failure Patterns and Responses

```
 SYMPTOM                                LIKELY CAUSE            RESPONSE
 ─────────────────────────────────────  ──────────────────────  ──────────────
 Container starts then immediately      Port conflict           Check port with ss -tlnp
 exits (Exit 1)                                                  Free port or change compose

 Container starts but health            Missing env var         docker logs to see error
 check never passes                                              Check env vars in compose

 Container starts but stays             Config file not found   Check volume mounts
 "starting" (never healthy)             or syntax error          docker exec <svc> cat config

 Container loops restart                OOM kill                 Check memory limits
 (restart count climbing)                                        Increase in compose or fix leak

 Container healthy but API              Wrong port or host       Check compose port mapping
 returns 502 or connection refused                               Verify Traefik routing

 Image pull fails (401/403)             Registry auth expired   Check Docker Hub login
                                                                 docker login

 Image pull fails (not found)           Wrong tag               Verify tag exists:
                                                                 docker manifest inspect <image>
```

---

## 4. PM2 Service Deployment

### 4.1 Full Step-by-Step Procedure

```
 ESTIMATED DURATION: 3-5 minutes per service
 DOWNTIME: 0-5 seconds (PM2 restart is near-instant)

 ─────────────────────────────────────────────────────────────────────

 STEP 1: PREPARE AND BACKUP (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. SSH to AIOPS:
    ┌─────────────────────────────────────────────────────────────┐
    │ ssh root@100.121.230.28                                  │
    └─────────────────────────────────────────────────────────────┘

 2. Record current state:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 save                                                  │
    │ pm2 list > /tmp/pm2-pre-deploy-$(date +%Y%m%d-%H%M%S).txt  │
    │                                                           │
    │ # Record current Git commit for each app                  │
    │ for app in frgcrm-agent-svc frgcrm-api frgcrm-mirror-test \│
    │   insforge-agent-svc surplusai-scraper-agent-svc voice-agent-svc; do │
    │   APP_DIR=$(pm2 show "$app" 2>/dev/null | grep 'exec cwd' | awk '{print $NF}') │
    │   cd "$APP_DIR" && echo "$app: $(git rev-parse HEAD)"     │
    │ done > /tmp/pm2-commits-pre-deploy.txt                    │
    └─────────────────────────────────────────────────────────────┘

 3. Pull latest code:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /opt/pm2-apps/frgcrm-agent-svc                          │
    │ git pull origin main                                      │
    │ # OR if using versioned directories:                      │
    │ git clone <repo> /opt/pm2-apps/frgcrm-agent-svc/v1.2.4   │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: DEPLOY (1 min)
 ─────────────────────────────────────────────────────────────────────
 1. Install dependencies (if changed):
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /opt/pm2-apps/<app-name>                                │
    │ npm ci --production                                       │
    │ # Expected: "added X packages in Ys"                       │
    └─────────────────────────────────────────────────────────────┘

 2. Deploy and restart:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Graceful reload (zero-downtime, if app supports it)      │
    │ pm2 reload <app-name>                                     │
    │ # OR full restart (brief downtime)                         │
    │ pm2 restart <app-name>                                    │
    │                                                           │
    │ # Expected output:                                        │
    │ # Use --update-env to update environment variables        │
    │ # [PM2] Applying action restartProcessId on app [<app>](id) │
    │ # [PM2] [<app>](id) ✓                                     │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: VALIDATE DEPLOYMENT (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. Check PM2 status:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 status                                                 │
    │ # Expected: status = "online", restarts = 0 (no new restarts)│
    └─────────────────────────────────────────────────────────────┘

 2. Check startup logs:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 logs <app-name> --lines 30 --nostream                 │
    │ # Expected: no errors, standard startup messages           │
    └─────────────────────────────────────────────────────────────┘

 3. Verify process is listening (if web service):
    ┌─────────────────────────────────────────────────────────────┐
    │ ss -tlnp | grep node  # Check listening ports              │
    └─────────────────────────────────────────────────────────────┘

 4. Hit health endpoint (if the PM2 app exposes one):
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -f http://localhost:<port>/health                     │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: FINALIZE (1 min)
 ─────────────────────────────────────────────────────────────────────
 1. Save PM2 state for resurrection on reboot:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 save                                                  │
    └─────────────────────────────────────────────────────────────┘

 2. Log deployment:
    ┌─────────────────────────────────────────────────────────────┐
    │ echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | PM2-DEPLOY | <app> | \│
    │   <old-commit> → <new-commit> | SUCCESS | $(whoami)" \     │
    │   >> /root/infrastructure/deployment-log.txt              │
    └─────────────────────────────────────────────────────────────┘

 3. Monitor PM2 metrics in Grafana for 15 minutes.
```

---

## 5. Database Migration Deployment

### 5.1 The Careful Procedure

```
 ╔═══════════════════════════════════════════════════════════════╗
 ║  DATABASE MIGRATIONS ARE THE SINGLE MOST DANGEROUS TYPE     ║
 ║  OF DEPLOYMENT. A FAILED MIGRATION CAN CAUSE DATA LOSS.     ║
 ║                                                             ║
 ║  REQUIREMENTS BEFORE PROCEEDING:                            ║
 ║  1. Migration tested in staging environment                 ║
 ║  2. Down migration tested (rollback path verified)          ║
 ║  3. Backup taken within the last 1 hour                     ║
 ║  4. Maintenance window approved                             ║
 ║  5. DBA or SRE Lead present (pair deployment)               ║
 ╚═══════════════════════════════════════════════════════════════╝

 ESTIMATED DURATION: 10-20 minutes (depends on migration size)
 DOWNTIME: Variable (minutes to hours for large data migrations)

 ─────────────────────────────────────────────────────────────────────

 STEP 1: PRE-FLIGHT (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Take a FRESH backup (even if one exists from overnight):
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/enterprise/phase6-backup           │
    │ bash backup-databases.sh --database <db_name> --urgent     │
    │ # Wait for completion and verify                            │
    │ ls -lh /opt/backups/databases/<db_name>/latest.dump.gpg   │
    └─────────────────────────────────────────────────────────────┘

 2. Analyze the migration for risk:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Read the migration file                                  │
    │ cat /path/to/migrations/V1234__description.sql            │
    │                                                           │
    │ # Risk assessment questions:                              │
    │ # - Does it DROP anything?                                 │
    │ # - Does it change column types?                          │
    │ # - Does it add NOT NULL without DEFAULT?                │
    │ # - Does it modify large tables (>1M rows)?               │
    │ # - Does it run data transformation scripts?              │
    │ # - Has the estimated runtime been verified?              │
    └─────────────────────────────────────────────────────────────┘

 3. If migration modifies a large table, estimate runtime:
    ┌─────────────────────────────────────────────────────────────┐
    │ # On staging, time the migration                           │
    │ # Rule of thumb: ALTER TABLE on 1M rows ≈ 2-10 seconds    │
    │ #                ALTER TABLE on 10M rows ≈ 20-120 seconds  │
    │ #                Data migration script: depends on complexity│
    └─────────────────────────────────────────────────────────────┘

 4. NOTIFY: Post in #infra-notices:
    "DATABASE MIGRATION STARTING: <db_name> — V1234__description"
    "Estimated downtime: <X minutes>"
    "Rollback plan: <tested/restore from backup>"

 STEP 2: STOP WRITES (1 min)
 ─────────────────────────────────────────────────────────────────────
 1. Put applications in read-only mode or stop them:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Option A: Stop write-capable services                    │
    │ pm2 stop frgcrm-agent-svc insforge-agent-svc              │
    │ docker stop prediction-radar-api ravynai-api               │
    │                                                           │
    │ # Option B: Set database to read-only (if apps tolerate)   │
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "ALTER SYSTEM SET default_transaction_read_only = on;"│
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "SELECT pg_reload_conf();"                           │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: RUN MIGRATION (1-X min)
 ─────────────────────────────────────────────────────────────────────
 1. Run the migration:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Using Flyway                                            │
    │ flyway -url=jdbc:postgresql://localhost:5432/wheeler \     │
    │   -user=postgres -password=${PG_PASSWORD} \                │
    │   migrate                                                │
    │                                                           │
    │ # OR manual psql                                         │
    │ docker exec -i postgres-aio-main psql -U postgres \       │
    │   -d wheeler < /path/to/migrations/V1234__description.sql│
    │                                                           │
    │ # Expected: SQL executed without errors                   │
    └─────────────────────────────────────────────────────────────┘

 2. Verify migration applied:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 1;" │
    │ # Should show V1234 as the latest                          │
    └─────────────────────────────────────────────────────────────┘

 3. Run quick integrity checks:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check new/modified tables are accessible                 │
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "\dt"  # List all tables                              │
    │                                                           │
    │ # Check for constraint violations                          │
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "SELECT conname, conrelid::regclass FROM pg_constraint WHERE contype = 'c' AND convalidated = false;" │
    │ # Should return 0 rows (all constraints valid)             │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: RE-ENABLE WRITES (1 min)
 ─────────────────────────────────────────────────────────────────────
 1. Re-enable applications:
    ┌─────────────────────────────────────────────────────────────┐
    │ # If DB was set read-only                                  │
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "ALTER SYSTEM SET default_transaction_read_only = off;"│
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "SELECT pg_reload_conf();"                           │
    │                                                           │
    │ # Restart apps if they were stopped                       │
    │ pm2 restart frgcrm-agent-svc insforge-agent-svc           │
    │ docker start prediction-radar-api ravynai-api             │
    └─────────────────────────────────────────────────────────────┘

 STEP 5: DEPLOY APPLICATION CODE (Docker/PM2) (3-5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Deploy the application code that depends on the new schema.
    Follow Section 3 (Docker) or Section 4 (PM2) procedures.

 2. If the old application code is incompatible with the new schema,
    you MUST deploy the new code IMMEDIATELY after the migration.
    A migration WITHOUT the matching code deploy will break things.

 STEP 6: VALIDATE (3 min)
 ─────────────────────────────────────────────────────────────────────
 1. Run application smoke tests:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -f https://ravynai.wheeler.ai/health                 │
    │ curl -f https://predictionradar.wheeler.ai/health         │
    └─────────────────────────────────────────────────────────────┘

 2. Verify data writes succeed:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Have the application perform a test write                │
    │ # Verify it appears in the database                        │
    └─────────────────────────────────────────────────────────────┘

 3. Announce completion:
    "DATABASE MIGRATION COMPLETE: V1234 — <description>"
    "Duration: X minutes | Status: SUCCESS"
    "Rollback plan ready: <tested down migration / restore from backup>"

 POST-MIGRATION MONITORING:
 ──────────────────────────
 [ ] Monitor PostgreSQL connection count (should be normal)
 [ ] Monitor application error rate (should be < 0.5%)
 [ ] Monitor query latency (should be at or below baseline)
 [ ] Monitor for deadlocks or lock contention
 [ ] Keep rollback window open for 2 hours (do not delete old backup)
```

---

## 6. Infrastructure Configuration Deployment

### 6.1 Traefik Configuration Deployment

```
 RISK: HIGH — Misconfigured Traefik can take down ALL routing.

 PROCEDURE:
 ──────────
 1. BACKUP current config:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker cp traefik:/etc/traefik/traefik.yml \               │
    │   /tmp/traefik.yml.bak-$(date +%Y%m%d-%H%M%S)             │
    │ docker cp traefik:/etc/traefik/dynamic/ \                  │
    │   /tmp/traefik-dynamic.bak-$(date +%Y%m%d-%H%M%S)          │
    └─────────────────────────────────────────────────────────────┘

 2. VALIDATE config syntax:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker run --rm -v $PWD/traefik.yml:/traefik.yml \         │
    │   traefik:latest traefik validate --configFile=/traefik.yml│
    │ # Expected: "Configuration is valid"                        │
    │ # If errors: FIX THEM before proceeding                    │
    └─────────────────────────────────────────────────────────────┘

 3. APPLY config:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker cp /root/infrastructure/edge/traefik/traefik.yml \  │
    │   traefik:/etc/traefik/traefik.yml                        │
    │ docker restart traefik                                    │
    └─────────────────────────────────────────────────────────────┘

 4. VALIDATE immediately:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check Traefik health                                     │
    │ curl -f http://localhost:8080/api/rawdata                 │
    │                                                           │
    │ # Check key routes work                                   │
    │ curl -I https://wheeler.ai                                │
    │ curl -I https://grafana.wheeler.ai                        │
    └─────────────────────────────────────────────────────────────┘

 5. IF ROUTING BROKEN: Rollback immediately.
    ┌─────────────────────────────────────────────────────────────┐
    │ docker cp /tmp/traefik.yml.bak-* traefik:/etc/traefik/traefik.yml │
    │ docker restart traefik                                    │
    └─────────────────────────────────────────────────────────────┘
```

### 6.2 UFW Firewall Rule Deployment

```
 RISK: HIGH — Can lock you out of the server or break connectivity.

 SAFETY PROTOCOL:
 ───────────────
 1. ALWAYS deploy UFW rules from the server's out-of-band console
    (Hetzner Cloud Console or Hostinger VNC), NOT via SSH.
    A bad rule can kill SSH and lock you out.

 2. NEVER use `ufw enable` without a rule allowing SSH from
    your current IP or Tailscale subnet.

 PROCEDURE:
 ──────────
 1. Open TWO TERMINALS:
    ├ Terminal 1: SSH session (will disconnect if rule blocks it)
    └ Terminal 2: Cloud Console VNC (emergency access)

 2. Apply rules with a safety timer:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Apply new rules                                         │
    │ bash /root/infrastructure/enterprise/phase1-server-hardening/02-ufw-policies.sh aiops --apply │
    │                                                           │
    │ # Verify immediately                                      │
    │ ufw status verbose                                       │
    │                                                           │
    │ # SCHEDULE AUTO-REVERT as safety net:                    │
    │ echo "ufw disable" | at now + 2 minutes                  │
    │ # This disables UFW in 2 minutes if you get locked out    │
    │                                                           │
    │ # Test connectivity from another Tailscale node:         │
    │ ssh root@<tailscale-ip> "echo OK"                        │
    │                                                           │
    │ # If OK, cancel the auto-revert:                         │
    │ atq  # List pending at jobs                              │
    │ atrm <job-id>  # Cancel the auto-revert                  │
    └─────────────────────────────────────────────────────────────┘

    ⚠ IF YOU GET LOCKED OUT: Wait 2 minutes for the auto-revert,
       or use the cloud console VNC to run `ufw disable`.
```

---

## 7. Deployment Windows

### 7.1 Safe Deployment Windows

```
Server          Safe Window (UTC)     Reason
──────────────  ────────────────────  ──────────────────────────────────
EDGE            02:00-06:00           Lowest traffic (global audience,
                                      US asleep, EU early morning)
AIOPS           02:00-06:00           Same as EDGE + batch jobs finished
COREDB          02:00-04:00           After daily backup (03:00) completes
                                      Before batch jobs start (04:30)

BUSINESS HOURS (06:00-18:00 UTC):
  ├ Allowed: Feature deployments, PM2 deployments
  └ Blocked: Database migrations, infrastructure changes
             (unless hotfix P1)

PEAK TRAFFIC PERIODS (BLOCKED FOR ALL NON-P1 DEPLOYMENTS):
  ├ 12:00-18:00 UTC (US business hours)
  ├ 07:00-11:00 UTC (EU business hours)
  └ Monday 00:00-06:00 UTC (weekend catch-up traffic)
```

### 7.2 Deployment Blackout Calendar

```
Date Range              Reason                          Deployments Allowed?
──────────────────────  ──────────────────────────────  ──────────────────
Dec 20 — Jan 2          Holiday freeze                  P1 hotfix only
Jul 1 — Jul 5           4th of July week (US)           P1 hotfix only
Last week of quarter    Financial close period            P1/P2 only
First week of month     Billing/invoicing peak            P1/P2 only
Any national holiday    Reduced staffing                 P1/P2 only
```

---

## 8. Canary Deployments

### 8.1 Canary Deployment Pattern

```
 USE FOR: Critical services where even brief degradation is unacceptable.
 REQUIRES: At least 2 instances of the service running (or the ability
           to spin up a second instance quickly).

 CANARY FLOW:
 ───────────

  100% traffic            90% traffic             100% traffic
  ┌──────────┐           ┌──────────┐            ┌──────────┐
  │  v1.2.3  │           │  v1.2.3  │            │  v1.2.4  │
  │  stable  │           │  stable  │            │  stable  │
  └──────────┘           └──────────┘            └──────────┘
                              │                       ▲
                       10% traffic              Validated OK
                        ┌──────────┐
                        │  v1.2.4  │──── Validation ────┘
                        │  canary  │   (5-15 min)
                        └──────────┘

 PROCEDURE:
 ──────────
 1. Deploy v1.2.4 alongside v1.2.3 (separate container/port):
    ┌─────────────────────────────────────────────────────────────┐
    │ docker compose -f docker-compose-canary.yml up -d          │
    │ # Uses different port: e.g., 8001 instead of 8000          │
    └─────────────────────────────────────────────────────────────┘

 2. Verify canary health:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -f http://localhost:8001/health                       │
    └─────────────────────────────────────────────────────────────┘

 3. Route 10% traffic to canary (Traefik weighted round-robin):
    ┌─────────────────────────────────────────────────────────────┐
    │ services:                                                  │
    │   my-service:                                             │
    │     weighted:                                             │
    │       services:                                           │
    │         - name: stable                                    │
    │           weight: 90                                     │
    │         - name: canary                                    │
    │           weight: 10                                     │
    └─────────────────────────────────────────────────────────────┘

 4. Monitor canary for 5-15 minutes:
    - Error rate on canary vs stable
    - P95 latency on canary vs stable
    - Memory/CPU on canary vs stable

 5. Decision:
    ├ Canary healthy → Increase to 50%, then 100% (full rollout)
    └ Canary unhealthy → Remove from load balancer, investigate

 6. Full rollout: Route 100% to new version, remove old containers.

 NOTE: Canary requires Traefik weighted round-robin, which is
       available in Traefik v2+. Our Traefik supports this.
```

---

## 9. Blue-Green Deployment Pattern

```
 USE FOR: The most critical services where rollback must be instant.
 REQUIRES: Double the resources (blue + green running simultaneously).

 ARCHITECTURE:
 ────────────
 ┌─────────────┐     ┌─────────────────┐
 │   Traefik   │────▶│  BLUE (active)  │  ← Currently serving
 │   Router    │     │  v1.2.3         │     all traffic
 │             │     └─────────────────┘
 │             │
 │             │     ┌─────────────────┐
 │             │ - - │  GREEN (idle)   │  ← Deployed, verified,
 │             │     │  v1.2.4         │     ready to go
 └─────────────┘     └─────────────────┘

 PROCEDURE:
 ──────────
 1. Deploy GREEN environment (v1.2.4) alongside BLUE:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker compose -f docker-compose-green.yml up -d           │
    │ # GREEN uses different port, e.g., 8100 vs 8000            │
    └─────────────────────────────────────────────────────────────┘

 2. Validate GREEN thoroughly (no user traffic yet):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Health check                                            │
    │ curl -f http://localhost:8100/health                      │
    │                                                           │
    │ # Database connectivity                                   │
    │ docker exec green-app psql -h coredb -U postgres -c "SELECT 1" │
    │                                                           │
    │ # Run integration test suite against GREEN                │
    │ npm run test:integration -- --base-url=http://localhost:8100 │
    └─────────────────────────────────────────────────────────────┘

 3. Switch Traefik to point to GREEN:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Update Traefik config to route to GREEN port             │
    │ # Apply config: docker cp ... traefik:...                  │
    │ # Traefik reloads config automatically (no restart needed) │
    └─────────────────────────────────────────────────────────────┘

 4. Verify GREEN serving traffic:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl https://myservice.wheeler.ai/version                 │
    │ # Should return "1.2.4"                                   │
    └─────────────────────────────────────────────────────────────┘

 5. Monitor GREEN for 5-15 minutes.

 6. If GREEN is healthy:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Stop BLUE (keep it for instant rollback if needed)      │
    │ docker compose -f docker-compose-blue.yml stop            │
    │ # After 1 hour of stable GREEN, remove BLUE:             │
    │ docker compose -f docker-compose-blue.yml down            │
    └─────────────────────────────────────────────────────────────┘

 7. If GREEN has issues — INSTANT ROLLBACK:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Switch Traefik back to BLUE (BlUE was never stopped!)   │
    │ # This takes < 1 second — Traefik hot-swaps config        │
    └─────────────────────────────────────────────────────────────┘
```

---

## 10. Deployment Approval Process

```
 DEPLOYMENT TYPE           APPROVAL REQUIRED            DOCUMENTATION
 ────────────────────────  ───────────────────────────  ────────────────────
 Hotfix (P1)               SRE Lead (post-deploy)       Jira ticket + Slack
 Feature Deploy            SRE Lead or Tech Lead         Jira ticket + PR
 Infrastructure Change     SRE Lead + CTO                Change request doc
 Database Migration        SRE Lead + DBA                Migration plan doc
 Dependency Update         SRE Lead                      PR + changelog review
 Security Patch            SRE Lead (can be post)        CVE reference

 APPROVAL PROCESS:
 ─────────────────
 1. Engineer creates deployment request
 2. Pre-deployment checklist completed (Section 2)
 3. Approval granted by required authority
 4. Deployment window verified (Section 7)
 5. Deploy proceeds with pair (at least 2 people aware)
 6. Post-deployment log filed
```

---

## 11. Post-Deployment Validation Checklist

```
 [ ] IMMEDIATE (within 2 minutes):
     [ ] Container/process health confirmed
     [ ] Health endpoints return HTTP 200
     [ ] No ERROR/FATAL in application logs
     [ ] Database connectivity confirmed
     [ ] Redis connectivity confirmed
     [ ] Key API endpoints functional

 [ ] SHORT-TERM (within 15 minutes):
     [ ] Error rate < 0.5% (check Grafana)
     [ ] P95 latency at or below baseline
     [ ] CPU/memory within expected range
     [ ] No new alerts firing in Alertmanager
     [ ] Uptime Kuma checks passing
     [ ] SSL certificates valid on all endpoints

 [ ] EXTENDED (within 2 hours):
     [ ] Error rate stable (not creeping up)
     [ ] Memory usage stable (no leak)
     [ ] Database performance nominal
     [ ] All cron jobs / scheduled tasks running
     [ ] Backups running normally
     [ ] User reports normal (check support channels)

 [ ] 24-HOUR CHECK:
     [ ] Review 24-hour metrics vs 24-hour pre-deploy baseline
     [ ] Verify no slow memory leak (compare usage over 24h)
     [ ] Check disk growth (deployment may add logs/data)
     [ ] Verify deployment log entry complete and accurate

 ALL ITEMS MUST BE CHECKED. Re-check at each interval.
```

---

## 12. Deployment Log Format

```
 FILE: /root/infrastructure/deployment-log.txt
 ─────────────────────────────────────────────

 FORMAT (one line per deployment):
 TIMESTAMP | TYPE | SERVICE | OLD_VERSION → NEW_VERSION | STATUS | DEPLOYER

 EXAMPLES:
 2026-05-23T03:00:00Z | DOCKER | prediction-radar-api | 1.2.3 → 1.2.4 | SUCCESS | jsmith
 2026-05-23T03:15:00Z | PM2 | frgcrm-agent-svc | abc123 → def456 | SUCCESS | jsmith
 2026-05-23T04:00:00Z | DB-MIGRATE | wheeler_db | V1233 → V1234 | SUCCESS | jsmith+dba
 2026-05-23T04:30:00Z | INFRA | traefik-config | — | SUCCESS | jsmith
 2026-05-23T10:00:00Z | HOTFIX | ravynai-api | 2.1.0 → 2.1.1 | SUCCESS | jsmith+p1
```

---

## 13. Emergency Deployment Procedure

### 13.1 When to Use

```
 TRIGGERS:
 ─────────
 [ ] P1 incident requiring code change to resolve
 [ ] Security vulnerability with active exploitation
 [ ] Data integrity issue requiring immediate fix
 [ ] Critical third-party dependency broke with breaking change

 WHAT THIS BYPASSES:
 ───────────────────
 [ ] Normal approval process → retroactive approval within 24 hours
 [ ] Maintenance window restriction → deploy now
 [ ] Full test suite → run smoke tests only
 [ ] Pre-deployment notification → notify during/after deploy

 WHAT STILL APPLIES:
 ──────────────────
 [✓] Backup verification (must be current)
 [✓] Rollback plan (must be ready)
 [✓] Pair deployment (two engineers aware)
 [✓] Post-deployment logging
 [✓] Post-deployment monitoring (30 min minimum)
```

### 13.2 Emergency Deployment Checklist

```
 [ ] PRE-DEPLOY (5 min):
     [ ] Verify backup exists and is recent (< 24 hours)
     [ ] Identify rollback version/image tag
     [ ] Brief second engineer on what you're doing
     [ ] Prepare the fix (code is ready to deploy)
     [ ] Open Grafana dashboard for the service

 [ ] DEPLOY (5-10 min):
     [ ] Deploy following standard procedure for service type
     [ ] Watch logs during startup
     [ ] Run smoke tests immediately

 [ ] POST-DEPLOY (30 min):
     [ ] Monitor error rate, latency, resource usage
     [ ] Confirm incident is resolved
     [ ] Announce completion in #alerts-critical + #infra-notices
     [ ] Log deployment in deployment-log.txt
     [ ] File retroactive approval request
     [ ] Schedule post-mortem if incident was P1
```

---

## Document Control

| Version | Date       | Author   | Changes                      |
|---------|------------|----------|------------------------------|
| 1.0.0   | 2026-05-23 | SRE Team | Initial deployment playbook  |

**Next Review:** 2026-08-23
