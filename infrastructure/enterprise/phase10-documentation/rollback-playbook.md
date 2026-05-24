# Wheeler Enterprise — Rollback Playbook

**Version:** 1.0.0 | **Last Updated:** 2026-05-23 | **Owner:** SRE Team
**Classification:** Critical — Operational

---

## 1. Deployment Safety Pyramid

```
                      ┌─────────┐
                      │ ROLLBACK │  ← Last resort. Fast. Decisive.
                      └────┬────┘
                           │
                    ┌──────┴──────┐
                    │  VALIDATE   │  ← Verify health, metrics, logs
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │   DEPLOY    │  ← Execute deployment procedure
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │   BACKUP    │  ← Capture pre-deployment state
                    └─────────────┘

               EVERY DEPLOYMENT MUST START WITH BACKUP.
               NO EXCEPTIONS.
```

### 1.1 Rollback Decision Flowchart

```
                    ┌─────────────────────────┐
                    │  DEPLOYMENT COMPLETE     │
                    └────────────┬────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │  Run validation checks   │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
              ▼                  ▼                  ▼
        ALL PASS           PARTIAL FAIL        CRITICAL FAIL
              │                  │                  │
              ▼                  ▼                  ▼
    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
    │ DEPLOY OK    │   │ FIX FORWARD  │   │   ROLLBACK   │
    │ Monitor 30m  │   │ or ROLLBACK  │   │  IMMEDIATELY │
    └──────────────┘   └──────┬───────┘   └──────────────┘
                              │
                   ┌──────────┴──────────┐
                   │  Is fix < 10 min?   │
                   └──────────┬──────────┘
                              │
                   ┌──────────┼──────────┐
                   │          │          │
                   ▼          ▼          ▼
                  YES        NO        CANNOT FIX
                   │          │          │
                   ▼          ▼          ▼
              FIX FORWARD   ROLLBACK    ROLLBACK
```

### 1.2 Rollback Triggers (Immediate Rollback Required)

```
Trigger                                    Action
─────────────────────────────────────────  ────────────────────────────────
Any P1 alert fires within 5 min of deploy  IMMEDIATE ROLLBACK
HTTP 5xx rate > 5% for 2 min               IMMEDIATE ROLLBACK
P95 latency increases > 3x baseline         IMMEDIATE ROLLBACK
Database connection failures detected       IMMEDIATE ROLLBACK
Memory leak detected (ramp > 5%/min)        IMMEDIATE ROLLBACK
Data corruption detected                    IMMEDIATE ROLLBACK + FORENSICS
SSL certificate errors after deploy         IMMEDIATE ROLLBACK
API returns wrong/inconsistent data         ROLLBACK within 10 min
Non-critical service degraded               ROLLBACK within 30 min
Minor cosmetic issue                        FIX FORWARD (no rollback)
```

---

## 2. Container Rollback (Docker Services)

### 2.1 Pre-Deployment Backup

```
 BEFORE ANY CONTAINER DEPLOYMENT:
 ─────────────────────────────────

 1. Record current image tags:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker ps --format 'table {{.Names}}\t{{.Image}}' \        │
    │   > /tmp/pre-deploy-images-$(date +%Y%m%d-%H%M%S).txt     │
    └─────────────────────────────────────────────────────────────┘

 2. Back up current Docker Compose files:
    ┌─────────────────────────────────────────────────────────────┐
    │ cp /root/infrastructure/aiops/<service>/docker-compose.yml \│
    │    /root/infrastructure/aiops/<service>/docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S) │
    └─────────────────────────────────────────────────────────────┘

 3. Back up named volumes if deployment touches volume mounts:
    ┌─────────────────────────────────────────────────────────────┐
    │ # For critical data volumes                                │
    │ docker run --rm -v <volume_name>:/data -v /tmp/backup:/backup \│
    │   alpine tar czf /backup/<volume_name>-$(date +%Y%m%d).tar.gz -C /data . │
    └─────────────────────────────────────────────────────────────┘
```

### 2.2 Rollback Procedure

```
 STEP 1: STOP THE FAILED CONTAINER (5 seconds)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ cd /root/infrastructure/aiops/<service>                     │
 │ docker compose stop <service-name>                          │
 │ # Example: docker compose stop prediction-radar-api        │
 └─────────────────────────────────────────────────────────────┘

 STEP 2: RESTORE PREVIOUS IMAGE TAG (30 seconds)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Edit docker-compose.yml to use the previous image tag     │
 │ # Option A: Pin specific tag                                │
 │ sed -i 's|image: prediction-radar:.*|image: prediction-radar:20260522-v1.2.3|' \│
 │   docker-compose.yml                                       │
 │                                                           │
 │ # Option B: Restore from backup file (safer)               │
 │ cp docker-compose.yml.bak-20260523-140000 docker-compose.yml │
 └─────────────────────────────────────────────────────────────┘

 STEP 3: START WITH PREVIOUS IMAGE (30 seconds)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ docker compose up -d <service-name>                         │
 │                                                           │
 │ # Wait for healthy                                         │
 │ sleep 5                                                    │
 │ docker ps --filter "name=<service>" --filter "health=healthy" │
 └─────────────────────────────────────────────────────────────┘

 STEP 4: VOLUME COMPATIBILITY CHECK (CRITICAL)
 ─────────────────────────────────────────────────────────────────────
 ⚠ WARNING: If the new deployment made SCHEMA CHANGES to a database
            that the old code doesn't understand, the rollback will
            NOT work by simply reverting the image.

 Compatibility check:
 ┌─────────────────────────────────────────────────────────────┐
 │ # Check if volume data was modified by the new version      │
 │ # If schema migrations ran, you MUST also rollback the DB   │
 │ # (See Section 4: Database Migration Rollback)              │
 │                                                           │
 │ # Check for new files/folders in volumes:                  │
 │ docker run --rm -v <volume_name>:/data alpine \            │
 │   find /data -newer /data/.deploy-marker -ls               │
 └─────────────────────────────────────────────────────────────┘

 STEP 5: VALIDATE ROLLBACK (2 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Health check                                              │
 │ curl -f http://localhost:<port>/health || echo "HEALTH FAIL"│
 │                                                           │
 │ # Check logs for errors                                    │
 │ docker logs --tail 50 <service-name> 2>&1 | grep -iE 'error|fail|panic' │
 │                                                           │
 │ # Verify metrics returning to baseline                     │
 │ # Check Grafana dashboard for the service                  │
 │                                                           │
 │ # Verify no volume/data issues                             │
 │ docker exec <service-name> ls -la /data/   # if applicable │
 └─────────────────────────────────────────────────────────────┘
```

### 2.3 Full-Stack Container Rollback (Multiple Services)

```
 When multiple containers were deployed together (full compose stack):

 ┌─────────────────────────────────────────────────────────────┐
 │ cd /root/infrastructure/aiops/<service>                     │
 │                                                           │
 │ # Option 1: Rollback the compose file (if no DB migrations) │
 │ cp docker-compose.yml.bak-$(ls -t *.bak-* | head -1) \    │
 │    docker-compose.yml                                      │
 │ docker compose down                                       │
 │ docker compose up -d                                      │
 │                                                           │
 │ # Option 2: Rollback specific services only (faster)      │
 │ docker compose up -d --no-deps <svc1> <svc2>              │
 │ # Uses the image tags in the restored compose file        │
 └─────────────────────────────────────────────────────────────┘
```

---

## 3. PM2 Application Rollback

### 3.1 Pre-Deployment Backup

```
 BEFORE PM2 DEPLOYMENT:
 ──────────────────────

 1. Save current PM2 state:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 save                                                  │
    │ pm2 list > /tmp/pm2-pre-deploy-$(date +%Y%m%d-%H%M%S).txt │
    └─────────────────────────────────────────────────────────────┘

 2. Copy current application code:
    ┌─────────────────────────────────────────────────────────────┐
    │ # For each PM2 app                                         │
    │ APP_DIR=$(pm2 show <app-name> | grep 'exec cwd' | awk '{print $NF}') │
    │ cp -r "$APP_DIR" "$APP_DIR.bak-$(date +%Y%m%d-%H%M%S)"     │
    └─────────────────────────────────────────────────────────────┘

 3. Record current Git commit:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd "$APP_DIR" && git rev-parse HEAD > /tmp/pm2-commit-pre-deploy.txt │
    └─────────────────────────────────────────────────────────────┘
```

### 3.2 Rollback Procedure

```
 STEP 1: STOP THE FAILED APPLICATION (5 seconds)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ pm2 stop <app-name>                                        │
 │ # Verify stopped: pm2 status | grep <app-name>              │
 └─────────────────────────────────────────────────────────────┘

 STEP 2: REVERT CODE TO PREVIOUS VERSION (30 seconds)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ cd "$APP_DIR"                                              │
 │                                                           │
 │ # Option A: Git revert (if using Git)                      │
 │ OLD_COMMIT=$(cat /tmp/pm2-commit-pre-deploy.txt)           │
 │ git reset --hard "$OLD_COMMIT"                             │
 │                                                           │
 │ # Option B: Restore from backup (safer, no Git dependency) │
 │ rm -rf "$APP_DIR"/*                                       │
 │ cp -r "$APP_DIR.bak-YYYYMMDD-HHMMSS"/* "$APP_DIR"/         │
 └─────────────────────────────────────────────────────────────┘

 STEP 3: RESTART THE APPLICATION (30 seconds)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ pm2 restart <app-name>                                     │
 │                                                           │
 │ # Watch logs for startup errors                           │
 │ pm2 logs <app-name> --lines 50 --nostream                 │
 └─────────────────────────────────────────────────────────────┘

 STEP 4: KEEP-OLD-VERSION PATTERN (Recommended for PM2)
 ─────────────────────────────────────────────────────────────────────
 ⚠ BEST PRACTICE: Never overwrite the running version.
                     Deploy alongside and switch.

 ┌─────────────────────────────────────────────────────────────┐
 │ # Instead of in-place replacement, use versioned directories│
 │ #                                                           │
 │ # Directory structure:                                     │
 │ # /opt/pm2-apps/                                           │
 │ #   ├── frgcrm-api/                                        │
 │ #   │   ├── v1.2.3/     ← current (running)                │
 │ #   │   ├── v1.2.4/     ← new (deploy adjacent)            │
 │ #   │   └── current -> v1.2.3/  (symlink)                  │
 │ #                                                           │
 │ # Deploy new version:                                     │
 │ rsync -av ./dist/ /opt/pm2-apps/frgcrm-api/v1.2.4/        │
 │                                                           │
 │ # Switch symlink and restart:                              │
 │ ln -sfn /opt/pm2-apps/frgcrm-api/v1.2.4 \                 │
 │        /opt/pm2-apps/frgcrm-api/current                    │
 │ pm2 restart frgcrm-api                                    │
 │                                                           │
 │ # Rollback: switch symlink back and restart               │
 │ ln -sfn /opt/pm2-apps/frgcrm-api/v1.2.3 \                 │
 │        /opt/pm2-apps/frgcrm-api/current                    │
 │ pm2 restart frgcrm-api                                    │
 └─────────────────────────────────────────────────────────────┘

 STEP 5: VALIDATE PM2 ROLLBACK (2 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Check PM2 status                                         │
 │ pm2 status                                                 │
 │                                                           │
 │ # Check app logs for errors                                │
 │ pm2 logs <app-name> --lines 20 --nostream                 │
 │                                                           │
 │ # Hit health endpoint                                      │
 │ curl -f http://localhost:<port>/health                     │
 │                                                           │
 │ # Check restart count (should not be climbing)            │
 │ pm2 show <app-name> | grep restarts                        │
 └─────────────────────────────────────────────────────────────┘
```

---

## 4. Database Migration Rollback

### 4.1 WARNING — The Most Dangerous Rollback

```
 ╔═══════════════════════════════════════════════════════════════╗
 ║  DATABASE MIGRATION ROLLBACK IS THE MOST DANGEROUS TYPE     ║
 ║  OF ROLLBACK. IT CAN CAUSE PERMANENT DATA LOSS.             ║
 ║                                                             ║
 ║  EVERY migration must have a TESTED down migration BEFORE   ║
 ║  the up migration is run in production. No exceptions.      ║
 ║                                                             ║
 ║  If a down migration has NOT been tested, DO NOT RUN IT.    ║
 ║  Restore from backup instead (Section 4.3).                 ║
 ╚═══════════════════════════════════════════════════════════════╝
```

### 4.2 Migration Types and Rollback Strategies

```
Migration Type             Rollback Method            Risk Level
─────────────────────────  ────────────────────────  ──────────
Add column                 DROP COLUMN               LOW (no data loss beyond new col)
Add table                  DROP TABLE                LOW (no existing data affected)
Add index                  DROP INDEX                LOW (no data change)
Rename column              Rename back + verify      MEDIUM (app may reference old name)
Change column type         Restore from backup       HIGH (data truncation possible)
Remove column              Restore from backup       HIGH (data permanently deleted)
Split/merge tables         Restore from backup       HIGH (complex data transformation)
Add NOT NULL constraint    Remove constraint         MEDIUM (data may violate old logic)
Add foreign key            DROP CONSTRAINT           LOW (no data change)
Data migration script      Restore from backup       CRITICAL (data irreversibly changed)
Delete data                Restore from backup       CRITICAL (data permanently gone)
```

### 4.3 Rollback Procedure

```
 STEP 1: ASSESS THE MIGRATION (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. Identify which migration(s) ran:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 5;" │
    └─────────────────────────────────────────────────────────────┘

 2. Read the migration file to understand what it changed:
    ┌─────────────────────────────────────────────────────────────┐
    │ cat /path/to/migrations/V1234__migration_name.sql          │
    └─────────────────────────────────────────────────────────────┘

 3. Classify the migration type (from table above).
    Determine risk level.

 4. Decision: Is the down migration tested and safe?
    ├ YES → Proceed to Step 2a (run down migration)
    └ NO  → Proceed to Step 2b (restore from backup)

 STEP 2a: RUN DOWN MIGRATION (tested, safe) (5 min)
 ─────────────────────────────────────────────────────────────────────
 ⚠ PRECHECK: Application MUST be stopped before running down migration.

 1. Stop all applications that use this database:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 stop all                                              │
    │ docker stop $(docker ps --filter "name=api" -q)            │
    │ docker stop $(docker ps --filter "name=worker" -q)         │
    └─────────────────────────────────────────────────────────────┘

 2. Run the down migration:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Flyway undo (if using Flyway)                            │
    │ flyway -url=jdbc:postgresql://localhost:5432/wheeler \      │
    │   -user=postgres -password=${PG_PASSWORD} \                │
    │   undo                                                    │
    │                                                           │
    │ # OR manually: psql -U postgres -d wheeler \               │
    │   -f /path/to/migrations/V1234__migration_name.down.sql   │
    │                                                           │
    │ # OR restore schema_migrations table to previous state:   │
    │ DELETE FROM schema_migrations WHERE version = '1234';     │
    └─────────────────────────────────────────────────────────────┘

 3. Verify the down migration succeeded:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check schema is as expected                             │
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "\dt"  # List tables                                 │
    │                                                           │
    │ # Check no orphaned data                                  │
    │ # Check application-level smoke test queries              │
    └─────────────────────────────────────────────────────────────┘

 4. Rollback application code to match down-migrated schema.
    See Section 2 or 3 for container/PM2 rollback.

 5. Restart applications.

 STEP 2b: RESTORE FROM BACKUP (down migration unsafe) (15-20 min)
 ─────────────────────────────────────────────────────────────────────
 ⚠ THIS WILL CAUSE DATA LOSS FOR ANY DATA WRITTEN AFTER THE MIGRATION.
   The RPO gap will be the time between migration and restore.

 1. Stop all applications (same as Step 2a, step 1).

 2. Identify the latest backup from BEFORE the migration:
    ┌─────────────────────────────────────────────────────────────┐
    │ ls -lt /opt/backups/databases/<db_name>/                   │
    │ # Pick the newest backup dated before the migration time   │
    └─────────────────────────────────────────────────────────────┘

 3. Restore from backup:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Drop and recreate database (clean restore)               │
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "DROP DATABASE IF EXISTS wheeler;"                   │
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "CREATE DATABASE wheeler;"                           │
    │                                                           │
    │ # Restore                                                  │
    │ gpg --decrypt /opt/backups/databases/wheeler-20260523-0300.dump.gpg | \│
    │   docker exec -i postgres-aio-main pg_restore \          │
    │   -U postgres -d wheeler                                 │
    └─────────────────────────────────────────────────────────────┘

 4. Verify data integrity:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Count rows in critical tables                            │
    │ # Verify sequences are correct                             │
    │ # Run application smoke tests                              │
    └─────────────────────────────────────────────────────────────┘

 5. Restart applications with the old code (the version that
    matches this database schema).

 6. DOCUMENT THE DATA LOSS WINDOW:
    What data was written between migration time and restore time?
    This MUST be reported and, if possible, replayed from logs.

 STEP 3: POST-ROLLBACK VALIDATION (5 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Verify database accepts connections                       │
 │ docker exec postgres-aio-main pg_isready                   │
 │                                                           │
 │ # Verify application can query                             │
 │ curl -f http://localhost:8007/health                       │
 │                                                           │
 │ # Verify row counts match expectations                     │
 │ # Check for constraint violations                          │
 │ # Verify foreign keys are intact                           │
 └─────────────────────────────────────────────────────────────┘
```

---

## 5. Configuration Rollback

### 5.1 Traefik Configuration Rollback

```
 PRE-DEPLOYMENT:
 ──────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Backup current config                                     │
 │ docker cp traefik:/etc/traefik/traefik.yml \               │
 │   /root/infrastructure/backups/traefik/traefik.yml.bak-$(date +%Y%m%d-%H%M%S) │
 │ docker cp traefik:/etc/traefik/dynamic/ \                  │
 │   /root/infrastructure/backups/traefik/dynamic.bak-$(date +%Y%m%d-%H%M%S) │
 └─────────────────────────────────────────────────────────────┘

 ROLLBACK:
 ────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Restore config from backup                               │
 │ docker cp /root/infrastructure/backups/traefik/traefik.yml.bak-2026* \│
 │   traefik:/etc/traefik/traefik.yml                        │
 │                                                           │
 │ docker restart traefik                                    │
 │                                                           │
 │ # Verify Traefik is healthy                                │
 │ curl -f http://localhost:8080/api/rawdata                 │
 │ docker logs traefik --tail 20                             │
 └─────────────────────────────────────────────────────────────┘
```

### 5.2 Environment Variable Rollback

```
 PRE-DEPLOYMENT:
 ──────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Save current env vars for a service                      │
 │ docker inspect <service-name> | jq '.[0].Config.Env' \     │
 │   > /tmp/env-<service>-pre-deploy.json                     │
 │                                                           │
 │ # OR for PM2:                                             │
 │ pm2 env <app-id> > /tmp/pm2-env-pre-deploy.txt            │
 └─────────────────────────────────────────────────────────────┘

 ROLLBACK (Docker):
 ─────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Edit docker-compose.yml to restore environment variables  │
 │ # Then restart:                                            │
 │ docker compose up -d --force-recreate <service-name>       │
 └─────────────────────────────────────────────────────────────┘

 ROLLBACK (PM2):
 ───────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Restore env vars and restart                             │
 │ pm2 restart <app-name> --update-env                         │
 │ # PM2 uses the env from ecosystem.config.js                │
 │ # If you changed ecosystem.config.js, restore it first     │
 └─────────────────────────────────────────────────────────────┘
```

---

## 6. DNS Rollback

### 6.1 DNS Rollback Considerations

```
 ⚠ DNS changes have propagation delays. Plan accordingly.

 TTL Considerations:
 ──────────────────
  ├ TTL 300s (5 min): Standard. Full rollback takes ~5-10 min.
  ├ TTL 120s (2 min): Fast rollback. Use during maintenance.
  └ TTL 60s (1 min): Fastest. Only during critical changes.

 Propagation Reality:
  ├ Most resolvers respect TTL. Some don't.
  ├ Expect 5-10% of traffic to take up to TTL * 2 to switch.
  └ Mobile carriers are notorious for ignoring low TTLs.
```

### 6.2 DNS Rollback Procedure

```
 ROLLBACK:
 ────────
 1. Change DNS records back to previous values:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Using Cloudflare API                                     │
    │ curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \│
    │   -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \      │
    │   -H "Content-Type: application/json" \                   │
    │   --data '{                                               │
    │     "type": "A",                                        │
    │     "name": "wheeler.ai",                                │
    │     "content": "187.77.148.88",                          │
    │     "ttl": 120,                                         │
    │     "proxied": true                                     │
    │   }'                                                     │
    └─────────────────────────────────────────────────────────────┘

 2. Verify propagation:
    ┌─────────────────────────────────────────────────────────────┐
    │ watch -n 10 'dig +short wheeler.ai @1.1.1.1'              │
    │ # Wait until it shows the correct (old) IP                │
    └─────────────────────────────────────────────────────────────┘

 3. Once propagated, restore TTL to 300s:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Update TTL back to 300                                  │
    └─────────────────────────────────────────────────────────────┘

 4. Flush Traefik DNS cache (if cached stale resolution):
    ┌─────────────────────────────────────────────────────────────┐
    │ docker restart traefik                                    │
    └─────────────────────────────────────────────────────────────┘
```

---

## 7. Full-System Rollback

### 7.1 When Everything Goes Wrong

```
 SCENARIO: A deployment has cascaded through multiple services.
           Nothing works. Error rates are catastrophic.
           Multiple services are down. Root cause is unclear.

 DECISION: Full-system rollback to last known-good state.

 THIS IS THE NUCLEAR OPTION. Use only when:
 ──────────────────────────────────────────────
 [ ] Multiple services are affected
 [ ] Root cause cannot be identified within 5 minutes
 [ ] Attempted targeted rollbacks have failed
 [ ] Data integrity is at risk
 [ ] Revenue-impacting outage is ongoing
```

### 7.2 Full-System Rollback Procedure

```
 ESTIMATED DURATION: 15-30 minutes (with prepared backups)
 DOWNTIME: Complete (all services offline during restore)

 STEP 1: STOP EVERYTHING (2 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Stop ALL PM2 apps                                        │
 │ pm2 stop all                                              │
 │                                                           │
 │ # Stop ALL Docker containers on affected servers          │
 │ docker stop $(docker ps -q)                                │
 │                                                           │
 │ # Verify nothing is running                               │
 │ docker ps                                                 │
 │ pm2 status                                                │
 └─────────────────────────────────────────────────────────────┘

 STEP 2: IDENTIFY LAST KNOWN-GOOD STATE (2 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Check deployment log to find last successful deployment  │
 │ cat /root/infrastructure/deployment-log.txt | tail -20     │
 │                                                           │
 │ # Identify the Git commit or backup timestamp              │
 │ LAST_GOOD_COMMIT="abc123def456"                           │
 │ LAST_GOOD_BACKUP="2026-05-22-0300"                        │
 └─────────────────────────────────────────────────────────────┘

 STEP 3: RESTORE DATABASES FROM LAST GOOD BACKUP (10 min)
 ─────────────────────────────────────────────────────────────────────
 ⚠ WARNING: This restores the database to the exact state at backup
            time. Any data written after the backup WILL BE LOST.

 ┌─────────────────────────────────────────────────────────────┐
 │ # For each database:                                       │
 │ for db in wheeler prediction_radar ravynai; do            │
 │   # Drop and recreate                                     │
 │   docker exec postgres-aio-main psql -U postgres \        │
 │     -c "DROP DATABASE IF EXISTS $db;"                    │
 │   docker exec postgres-aio-main psql -U postgres \        │
 │     -c "CREATE DATABASE $db;"                            │
 │                                                           │
 │   # Restore from backup                                  │
 │   gpg --decrypt /opt/backups/databases/$db-$LAST_GOOD_BACKUP.dump.gpg | \│
 │     docker exec -i postgres-aio-main pg_restore \        │
 │     -U postgres -d $db                                   │
 │   echo "Restored: $db"                                   │
 │ done                                                      │
 └─────────────────────────────────────────────────────────────┘

 STEP 4: RESTORE DOCKER CONFIGURATIONS (5 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Restore all Docker Compose files from Git                 │
 │ cd /root/infrastructure                                    │
 │ git checkout "$LAST_GOOD_COMMIT" -- \                       │
 │   enterprise/ aiops/ edge/ coredb/                         │
 └─────────────────────────────────────────────────────────────┘

 STEP 5: START SERVICES IN DEPENDENCY ORDER (5 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Follow the exact startup order from the deployment playbook│
 │                                                           │
 │ # Tier 0: Infrastructure                                  │
 │ cd /root/infrastructure/aiops/monitoring && docker compose up -d │
 │ cd /root/infrastructure/aiops/data && docker compose up -d │
 │                                                           │
 │ # Tier 1: Databases                                       │
 │ cd /root/infrastructure/aiops/prediction-radar && docker compose up -d postgres redis │
 │ cd /root/infrastructure/aiops/ravynai && docker compose up -d postgres redis │
 │ cd /root/infrastructure/aiops/analytics && docker compose up -d clickhouse │
 │                                                           │
 │ # Tier 2: Applications                                    │
 │ cd /root/infrastructure/aiops/prediction-radar && docker compose up -d api worker scheduler web │
 │ cd /root/infrastructure/aiops/ravynai && docker compose up -d api worker │
 │ cd /root/infrastructure/aiops/analytics && docker compose up -d superset │
 │ cd /root/infrastructure/aiops/ai-agents && docker compose up -d │
 │ cd /root/infrastructure/aiops/trading && docker compose up -d │
 │ cd /root/infrastructure/aiops/automation && docker compose up -d │
 │ cd /root/infrastructure/aiops/messaging && docker compose up -d │
 │ cd /root/infrastructure/aiops/osint && docker compose up -d │
 │                                                           │
 │ # Tier 3: Management                                      │
 │ cd /root/infrastructure/aiops/management && docker compose up -d │
 │                                                           │
 │ # Tier 4: Traefik (last)                                  │
 │ cd /root/infrastructure/aiops/traefik && docker compose up -d │
 └─────────────────────────────────────────────────────────────┘

 STEP 6: RESTORE PM2 APPLICATIONS (3 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Restore PM2 code from Git                                │
 │ cd /root/infrastructure/pm2-apps                           │
 │ git checkout "$LAST_GOOD_COMMIT"                            │
 │                                                           │
 │ # Start all PM2 apps                                      │
 │ pm2 start ecosystem.config.js                             │
 │ pm2 save                                                  │
 └─────────────────────────────────────────────────────────────┘

 STEP 7: FULL VALIDATION (5 min)
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ bash /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh │
 │                                                           │
 │ # Must pass 100% of health checks before declaring success │
 └─────────────────────────────────────────────────────────────┘
```

---

## 8. Rollback Decision Matrix

```
Symptom                         Fix Forward?  Rollback?  Time Limit
──────────────────────────────  ────────────  ─────────  ──────────
Database migration failed        NEVER          YES         Immediate
(up migration errored)

Application crash loop           YES (if <5m)   YES        5 min
(clear error in logs)

Memory leak detected             NO             YES        Immediate
(ramp > 5% memory/min)

HTTP 5xx rate spike              NO             YES        Immediate
(> 5% for 2 min)

Latency degradation              YES (if <10m)  YES        10 min
(P95 > 3x baseline)

Wrong data returned              NO             YES        Immediate
(data integrity issue)

SSL certificate error            NO             YES        Immediate
(browser warnings)

Cosmetic UI issue                YES            NO         Next business day
(button color, layout)

Non-critical feature broken      YES            NO         Next business day

Performance regression           YES (if <30m)  YES        30 min
(P95 +50% but not breaking)

Dependency update (minor)        YES            NO         Next release
Dependency update (major)        NO             YES        Immediate
(breaking changes)
```

---

## 9. Rollback Validation Checklist

```
 AFTER EVERY ROLLBACK, VERIFY:
 ──────────────────────────────

 [ ] SERVICE HEALTH
     [ ] Docker container shows "healthy" status
     [ ] PM2 process shows "online" status
     [ ] Health endpoint returns HTTP 200
     [ ] Service logs contain no ERROR or FATAL entries

 [ ] FUNCTIONALITY
     [ ] Core API endpoints return expected responses
     [ ] Database queries succeed (smoke test)
     [ ] Redis cache responds to PING
     [ ] Authentication/authorization works (login test)

 [ ] DATA INTEGRITY
     [ ] Row counts match expected (compare pre/post)
     [ ] No constraint violations in application logs
     [ ] Foreign keys intact
     [ ] Sequences not reset

 [ ] MONITORING
     [ ] Prometheus scraping targets healthy
     [ ] Grafana dashboards loading
     [ ] No new alerts firing (check Alertmanager)
     [ ] Uptime Kuma checks passing

 [ ] CROSS-SERVICE
     [ ] Traefik routing correct (check routes)
     [ ] Tailscale mesh fully connected
     [ ] Inter-service API calls succeeding
     [ ] Message queues processing (NATS/RabbitMQ)

 [ ] EXTERNAL
     [ ] Public endpoints accessible from outside
     [ ] SSL certificates valid
     [ ] DNS resolving correctly
     [ ] Cloudflare proxy working

 ALL ITEMS MUST PASS before declaring rollback successful.
 If any item fails, escalate: the rollback may have been incomplete.
```

---

## 10. Communication Template

### 10.1 Rollback Announcement

```
 TEMPLATE — Slack #infra-notices:
 ─────────────────────────────────

 ROLLBACK IN PROGRESS

 Service(s): <service names>
 Reason: <brief reason, e.g., "HTTP 5xx rate at 8% after v2.1.0 deploy">
 Started: <time>
 Estimated Duration: <X minutes>
 Impact: <what users will experience>
 Rollback Target: <previous version, e.g., v2.0.9>

 Will update when rollback is complete.

 SLACK TEMPLATE — Rollback Complete:
 ────────────────────────────────────

 ROLLBACK COMPLETE

 Service(s): <service names> rolled back to <version>
 Duration: <X minutes>
 Status: <SUCCESS / PARTIAL / FAILED>
 User Impact: <data loss? downtime? none?>
 Next Steps: <post-mortem? re-deploy fix?>

 @channel if user impact was significant.
```

### 10.2 User-Facing Status Page Update

```
 TEMPLATE — Status Page:
 ────────────────────────

 Title: Service Degradation — Rollback in Progress
 Status: Investigating → Identified → Monitoring → Resolved (update as you go)

 Investigating:
   We are investigating reports of <symptom> affecting <service>.

 Identified:
   The issue has been identified as a <cause> in the latest deployment.
   We are rolling back to the previous stable version.

 Monitoring:
   Rollback is complete. We are monitoring to ensure services are stable.

 Resolved:
   Services have been fully restored. <Brief explanation if appropriate.>
   Incident duration: <X minutes>.
```

---

## 11. Post-Rollback Analysis Template

```
═══════════════════════════════════════════════════════════════════
              WHEELER ENTERPRISE — ROLLBACK POST-MORTEM
═══════════════════════════════════════════════════════════════════

Rollback ID:         RB-YYYY-NNN
Deployment Rolled Back: DEP-YYYY-NNN
Date/Time:           YYYY-MM-DD HH:MM UTC
Services Rolled Back: [list]
Version Rolled TO:   <old version>
Version Rolled FROM: <new version that failed>
Author:              [Name]

── 1. WHAT HAPPENED ──────────────────────────────────────────────
[2-3 sentences: What was being deployed, what went wrong,
 how it was detected]

── 2. ROLLBACK TIMELINE ──────────────────────────────────────────
[UTC]  [Event]
14:00  Deployment of v1.2.4 started
14:05  Deployment completed
14:08  Grafana alert: HTTP 5xx rate > 5%
14:09  Engineer confirmed errors in logs
14:10  Rollback decision made
14:11  v1.2.3 restored, service restarting
14:13  Service healthy, healthchecks passing
14:15  Rollback declared complete

── 3. ROLLBACK PERFORMANCE ──────────────────────────────────────
Time to detect:          <X minutes>
Time to decide:          <X minutes>
Time to execute:         <X minutes>
Total rollback duration: <X minutes>
Data loss:               <Yes/No — scope if yes>
RTO met?                 <Yes/No — RTO was X, actual was Y>

── 4. ROOT CAUSE ────────────────────────────────────────────────
[Why did the deployment fail? Technical root cause]

── 5. WHAT WORKED ───────────────────────────────────────────────
  + Rollback procedure was clear and complete
  + Backup was available and recent (RPO: <X hours>)
  + Monitoring detected the issue within <X minutes>

── 6. WHAT NEEDS IMPROVEMENT ────────────────────────────────────
  - <Issue with the deployment itself>
  - <Issue with the rollback process>
  - <Issue with detection/monitoring>

── 7. PREVENTION ────────────────────────────────────────────────
 [ID]  [Action]                              [Owner]    [Due Date]
 P-1   Add integration test for <scenario>    @dev      2026-06-01
 P-2   Add canary deployment for <service>    @sre      2026-06-15
 P-3   Improve health check to catch <case>   @sre      2026-06-15

══ ═══════════════════════════════════════════════════════════════
```

---

## Document Control

| Version | Date       | Author   | Changes                   |
|---------|------------|----------|---------------------------|
| 1.0.0   | 2026-05-23 | SRE Team | Initial rollback playbook |

**Next Review:** 2026-08-23
