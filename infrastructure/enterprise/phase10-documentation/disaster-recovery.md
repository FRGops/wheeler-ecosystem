# Wheeler Enterprise — Disaster Recovery Runbook

**Version:** 1.0.0 | **Last Updated:** 2026-05-23 | **Owner:** SRE Team
**Classification:** Critical — Operational

---

## 1. Disaster Classification

### 1.1 Severity Levels

```
P1 — CRITICAL: Complete service outage, revenue impact, data loss imminent
    Response: Immediate (any hour, any day) — all hands on deck
    Examples:
    ├ AIOPS server completely offline or unreachable
    ├ COREDB database corruption detected (data integrity compromise)
    ├ DNS outage taking all *.wheeler.ai down globally
    ├ Ransomware detected on any server
    └ Data breach detected (unauthorized access to production data)

P2 — HIGH: Partial outage, degraded service, no data loss
    Response: Within 15 minutes, business hours extended to 24/7
    Examples:
    ├ EDGE server down (all public-facing services unreachable)
    ├ Single critical service failure (LiteLLM proxy down, all AI calls fail)
    ├ PostgreSQL primary instance down
    ├ Tailscale mesh partition (AIOPS isolated from EDGE)
    └ SSL certificate expiry on wildcard domain

P3 — MEDIUM: Non-critical service down, monitoring gap, capacity warning
    Response: Within 1 hour, business hours
    Examples:
    ├ Single non-critical service down (Spiderfoot, n8n)
    ├ Monitoring system partial failure (Prometheus down, Grafana up)
    ├ Disk usage > 85% on any server
    ├ Backup failure (one missed cycle, retry possible)
    └ PM2 service restart loop detected

P4 — LOW: Cosmetic, non-urgent, maintenance-related
    Response: Within 4 hours, business hours
    Examples:
    ├ Log rotation failure (disk not yet critical)
    ├ Minor SSL cert expiring in 30+ days
    ├ Unattended-upgrades install failure (non-security package)
    └ Dashboard rendering issue (no data loss)
```

### 1.2 Escalation Path

```
Alert Fires
    │
    ├── P1: Engineer on-call → SRE Lead (5 min) → CTO (15 min) → CEO (30 min)
    ├── P2: Engineer on-call → SRE Lead (15 min) → CTO (1 hour)
    ├── P3: Engineer on-call → SRE Lead (next business day)
    └── P4: Engineer on-call → Ticket queue (within SLA)
```

---

## 2. RTO and RPO by Service Tier

```
Service Tier         Services Included                  RTO        RPO         Max Data Loss
───────────────────  ─────────────────────────────────  ────────   ────────    ────────────
TIER 0 (Critical)    LiteLLM Proxy                      < 15 min   < 5 min     Near zero
                     Traefik (EDGE + AIOPS)
                     PostgreSQL (AIOPS + COREDB)
                     Redis (AIOPS + COREDB)
                     Tailscale Mesh
                     UFW/Firewall

TIER 1 (High)        Prediction Radar                    < 1 hour   < 1 hour    Up to 1 hour
                     RavynAI
                     AI Agent Runtimes
                     PM2 Services (all 7 apps)
                     ClickHouse
                     Superset
                     Prometheus + Alertmanager

TIER 2 (Medium)      Grafana                             < 4 hours  < 4 hours   Up to 4 hours
                     Loki
                     Uptime Kuma
                     Netdata
                     Healthchecks
                     ChangeDetection
                     NATS/RabbitMQ

TIER 3 (Low)         Spiderfoot                          < 24 hours < 24 hours  Up to 24 hours
                     Browser Automation
                     Portainer/Dockge
                     n8n (light)
                     Docuseal
```

---

## 3. Scenario: EDGE Server Total Loss

### 3.1 Impact Assessment

```
What breaks:
  ├ ALL public-facing services unreachable (wheeler.ai and all subdomains)
  ├ LiteLLM proxy gone — all AI agent calls fail
  ├ FRGops, Chatwoot, n8n, Docuseal unavailable
  ├ Webhook receiver stops processing
  ├ Traefik public edge routing gone
  └ All user traffic blocked at entry point

What still works:
  ├ AIOPS internal services continue running
  ├ COREDB databases accessible via Tailscale from AIOPS
  ├ Monitoring continues collecting (Prometheus on AIOPS)
  ├ Backups continue running on AIOPS and COREDB
  └ Internal admin access via Tailscale to AIOPS
```

### 3.2 Recovery Procedure

**Estimated recovery time: 30-45 minutes**

```
 STEP 1: VERIFY LOSS (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Confirm EDGE server is truly gone:
    ┌─────────────────────────────────────────────────────────────┐
    │ ssh edge                                                │
    │ tailscale status   # (from AIOPS — check if EDGE is visible)│
    │ ping 187.77.148.88    # (from your workstation)            │
    │ ping 100.98.163.17     # (Tailscale IP from AIOPS)           │
    └─────────────────────────────────────────────────────────────┘

 2. If Hostinger console shows server status, check there first.
    It may be a networking issue, not total loss.

 3. Decision: If server is truly gone and cannot be recovered from
    Hostinger snapshots, proceed to Step 2.


 STEP 2: PROVISION NEW EDGE SERVER (10-15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Log into Hostinger control panel
 2. Provision new VPS with same plan (or nearest equivalent)
    - Minimum: 4 vCPU, 8 GB RAM, 100 GB NVMe
    - OS: Ubuntu 24.04 LTS
 3. Note new public IP (it WILL be different from 187.77.148.88)
 4. Initial SSH as root (password from Hostinger panel)
 5. Set up SSH key immediately (before anything else):
    ┌─────────────────────────────────────────────────────────────┐
    │ mkdir -p ~/.ssh                                          │
    │ echo "<YOUR_PUBLIC_KEY>" >> ~/.ssh/authorized_keys        │
    │ chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys       │
    │ passwd -l root  # Disable root password login             │
    └─────────────────────────────────────────────────────────────┘


 STEP 3: RESTORE SERVER CONFIGURATION (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. From your workstation, clone/push infrastructure repo to new server:
    ┌─────────────────────────────────────────────────────────────┐
    │ scp -r /root/infrastructure/ root@<NEW_IP>:/root/          │
    └─────────────────────────────────────────────────────────────┘

 2. Run server hardening:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/enterprise/phase1-server-hardening  │
    │ bash apply-server-hardening.sh edge                       │
    │ # This applies:                                            │
    │ #   - 00-sysctl-hardening.conf                             │
    │ #   - 01-fail2ban-jail.local                               │
    │ #   - 02-ufw-policies.sh (edge role)                        │
    │ #   - 03-ssh-hardening.sh                                     │
    │ #   - 04-docker-daemon.json                                   │
    │ #   - 06-limits.conf                                          │
    │ #   - 07-journald.conf                                     │
    │ #   - 08-logrotate-wheeler.conf                            │
    └─────────────────────────────────────────────────────────────┘

 3. Install Docker and Tailscale:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -fsSL https://get.docker.com | bash                 │
    │ curl -fsSL https://tailscale.com/install.sh | bash        │
    │ tailscale up --auth-key=<TAILSCALE_AUTH_KEY> --hostname=edge │
    │ systemctl enable --now docker tailscaled                 │
    └─────────────────────────────────────────────────────────────┘

 4. Install PM2 (for edge-specific Node.js if any):
    ┌─────────────────────────────────────────────────────────────┐
    │ npm install -g pm2                                       │
    │ pm2 startup                                              │
    └─────────────────────────────────────────────────────────────┘


 STEP 4: RESTORE DOCKER SERVICES (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Restore configuration files from backup:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Restore Traefik config from latest backup               │
    │ rsync -avz root@<AIOPS_TAILSCALE_IP>:/opt/backups/edge-config/ \│
    │   /root/infrastructure/edge/                              │
    └─────────────────────────────────────────────────────────────┘

 2. Create required Docker networks:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker network create traefik-public --subnet 172.20.0.0/24 │
    │ docker network create frgops --subnet 172.30.0.0/24       │
    │ docker network create ai-proxy --subnet 172.31.0.0/24      │
    │ docker network create automation --subnet 172.32.0.0/24    │
    │ docker network create storage --subnet 172.33.0.0/24       │
    │ docker network create webhooks --subnet 172.34.0.0/24      │
    └─────────────────────────────────────────────────────────────┘

 3. Start Traefik first:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/edge/traefik                      │
    │ docker compose up -d                                      │
    │ docker logs traefik --follow  # Watch for errors, then Ctrl+C│
    └─────────────────────────────────────────────────────────────┘

 4. Start remaining services:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/edge/ && \                          │
    │ for dir in frgops chatwoot n8n docuseal litellm minio webhooks; do │
    │   (cd "$dir" && docker compose up -d)                     │
    │ done                                                      │
    └─────────────────────────────────────────────────────────────┘

 5. Verify all containers:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker ps --format 'table {{.Names}}\t{{.Status}}'         │
    └─────────────────────────────────────────────────────────────┘


 STEP 5: RESTORE DNS (5 min — DO THIS LAST)
 ─────────────────────────────────────────────────────────────────────
 ⚠ WARNING: DNS changes propagate slowly. Ensure services are
            verified working BEFORE changing DNS.

 1. Log into Cloudflare dashboard
 2. Update the A record for wheeler.ai and *.wheeler.ai
    FROM: 187.77.148.88
    TO:   <NEW_EDGE_PUBLIC_IP>
 3. Set TTL to 120 (2 minutes) initially for fast cutover
 4. Wait for propagation (typically 2-5 minutes with low TTL)
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check propagation from multiple locations               │
    │ dig +short wheeler.ai @1.1.1.1                           │
    │ dig +short wheeler.ai @8.8.8.8                           │
    └─────────────────────────────────────────────────────────────┘
 5. Once verified, raise TTL back to 300 (5 minutes)

 STEP 6: VALIDATE (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Run comprehensive health check:
    ┌─────────────────────────────────────────────────────────────┐
    │ bash /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh │
    └─────────────────────────────────────────────────────────────┘
 2. Test critical endpoints from external connection:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -I https://wheeler.ai                                │
    │ curl -I https://litellm.wheeler.ai/health                 │
    │ curl -I https://frgops.wheeler.ai/api/health               │
    └─────────────────────────────────────────────────────────────┘
 3. Verify Tailscale mesh: `tailscale status`
 4. Check Traefik routing: `curl http://localhost:8080/api/rawdata`
 5. Test LiteLLM: `curl https://litellm.wheeler.ai/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"`

 POST-RECOVERY TASKS:
 ────────────────────
 [ ] Document new EDGE IP in all playbooks
 [ ] Update /root/infrastructure/ARCHITECTURE.md with new IP
 [ ] Update UFW rules on AIOPS if IP-based (should be Tailscale-based, verify)
 [ ] Verify backups targeting new EDGE
 [ ] Create Hostinger snapshot of new EDGE server
 [ ] File post-mortem within 24 hours
```

---

## 4. Scenario: AIOPS Server Total Loss

### 4.1 Impact Assessment

```
What breaks (CRITICAL — this is the worst-case server to lose):
  ├ ALL AI services offline (Prediction Radar, RavynAI, AI Agents)
  ├ ALL monitoring offline (Prometheus, Grafana, Loki, Alertmanager)
  ├ ALL PM2 services gone (7 apps)
  ├ Trading engine and realtime feeds stop
  ├ ClickHouse analytics offline
  ├ Superset dashboards gone
  ├ Healthchecks service gone
  ├ ChangeDetection gone
  ├ NATS/RabbitMQ messaging offline
  ├ All AIOPS PostgreSQL and Redis instances gone
  └ No alerting (Alertmanager was on AIOPS)

What still works (limited):
  ├ EDGE server up — public-facing reverse proxy running
  ├ EDGE-hosted apps still available (FRGops, Chatwoot, n8n, Docuseal)
  ├ LiteLLM proxy on EDGE may still route (if configured with direct provider keys)
  ├ COREDB databases intact and accessible
  └ Tailscale mesh partially functional (EDGE ↔ COREDB path remains)
```

### 4.2 Recovery Procedure

**Estimated recovery time: 1-3 hours**

```
 STEP 1: VERIFY LOSS (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Check Hetzner Cloud Console for server status
 2. Attempt Tailscale ping from EDGE: tailscale ping aiops
 3. Attempt SSH via Tailscale IP: ssh root@100.121.230.28
 4. If server exists but is unresponsive, try Hetzner console reset first
 5. Decision: If truly unrecoverable, proceed to rebuild.

 STEP 2: NOTIFY AND ACTIVATE EMERGENCY MEASURES (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Post in #alerts-critical: "P1: AIOPS server total loss. DR plan activated."
 2. Activate PagerDuty on-call escalation
 3. Assess whether to route traffic to fallback or wait

 ⚠ CRITICAL: During AIOPS loss, there will be NO MONITORING and
             NO ALERTING. Must manually watch EDGE and COREDB health.

 STEP 3: PROVISION NEW AIOPS SERVER (10-15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Log into Hetzner Cloud Console
 2. Create new CPX51 instance (or nearest available):
    - 16 vCPU, 32 GB RAM, 360 GB NVMe
    - OS: Ubuntu 24.04 LTS
    - Place in same region as COREDB for low latency
 3. Note new public IP
 4. SSH in as root and set up SSH key

 STEP 4: APPLY FULL SERVER HARDENING (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Push infrastructure repo:
    ┌─────────────────────────────────────────────────────────────┐
    │ scp -r /root/infrastructure/ root@<NEW_AIOPS_IP>:/root/    │
    └─────────────────────────────────────────────────────────────┘

 2. Apply ALL hardening:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/enterprise/phase1-server-hardening  │
    │ bash apply-server-hardening.sh aiops                      │
    └─────────────────────────────────────────────────────────────┘

 3. Install Docker + Tailscale:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -fsSL https://get.docker.com | bash                 │
    │ curl -fsSL https://tailscale.com/install.sh | bash        │
    │ tailscale up --auth-key=<TAILSCALE_AUTH_KEY> --hostname=aiops │
    │ systemctl enable --now docker tailscaled                 │
    └─────────────────────────────────────────────────────────────┘

 4. Install Node.js + PM2:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -fsSL https://deb.nodesource.com/setup_20.x | bash - │
    │ apt install -y nodejs                                     │
    │ npm install -g pm2                                       │
    │ pm2 startup                                              │
    └─────────────────────────────────────────────────────────────┘

 STEP 5: RESTORE FROM BACKUP — ORDERED BY PRIORITY (30-45 min)
 ─────────────────────────────────────────────────────────────────────
 ⚠ ORDER MATTERS: Services depend on each other. Follow this sequence.

 1. FIRST: Restore databases (databases must be up before anything else):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Get latest backup from COREDB or archive server          │
    │ rsync -avz root@<COREDB_TAILSCALE_IP>:/opt/backups/databases/ \│
    │   /opt/backups/databases/                                 │
    │                                                           │
    │ # Decrypt and restore each database                        │
    │ for dump in /opt/backups/databases/*.dump.gpg; do          │
    │   name=$(basename "$dump" .dump.gpg)                      │
    │   gpg --decrypt "$dump" | \                              │
    │     pg_restore -U postgres -h localhost -d "$name" -c     │
    │   echo "Restored: $name"                                  │
    │ done                                                      │
    └─────────────────────────────────────────────────────────────┘

 2. SECOND: Start Docker services in dependency order:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Create networks first                                    │
    │ for net in traefik-public prediction-radar analytics \     │
    │   ravynai ai-agents trading messaging automation \         │
    │   data monitoring management osint; do                    │
    │   docker network create "$net" 2>/dev/null || true        │
    │ done                                                      │
    │                                                           │
    │ # Start services tier by tier                              │
    │ # Tier 0: Infrastructure                                  │
    │ cd /root/infrastructure/aiops/monitoring && docker compose up -d │
    │ cd /root/infrastructure/aiops/data && docker compose up -d │
    │ cd /root/infrastructure/aiops/messaging && docker compose up -d │
    │                                                           │
    │ # Tier 1: Databases                                       │
    │ cd /root/infrastructure/aiops/prediction-radar && docker compose up -d postgres redis │
    │ cd /root/infrastructure/aiops/ravynai && docker compose up -d postgres redis │
    │ cd /root/infrastructure/aiops/analytics && docker compose up -d clickhouse │
    │                                                           │
    │ # Tier 2: Application Services                             │
    │ cd /root/infrastructure/aiops/prediction-radar && docker compose up -d api worker scheduler web │
    │ cd /root/infrastructure/aiops/ravynai && docker compose up -d api worker │
    │ cd /root/infrastructure/aiops/analytics && docker compose up -d superset │
    │ cd /root/infrastructure/aiops/ai-agents && docker compose up -d │
    │ cd /root/infrastructure/aiops/trading && docker compose up -d │
    │ cd /root/infrastructure/aiops/automation && docker compose up -d │
    │                                                           │
    │ # Tier 3: Management                                      │
    │ cd /root/infrastructure/aiops/management && docker compose up -d │
    └─────────────────────────────────────────────────────────────┘

 3. THIRD: Restore PM2 applications:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Restore PM2 ecosystem from backup                        │
    │ rsync -avz root@<COREDB_TAILSCALE_IP>:/opt/backups/pm2/ \  │
    │   /etc/pm2/                                               │
    │                                                           │
    │ # Start all PM2 apps                                      │
    │ cd /root/infrastructure/aiops/pm2                         │
    │ pm2 start ecosystem.config.js                             │
    │ pm2 save                                                  │
    └─────────────────────────────────────────────────────────────┘

 4. FOURTH: Start Traefik last (routes depend on upstream services):
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/aiops/traefik                      │
    │ docker compose up -d                                      │
    │ docker logs traefik --tail 50                             │
    └─────────────────────────────────────────────────────────────┘

 STEP 6: VALIDATE RECOVERY (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Run full healthcheck:
    ┌─────────────────────────────────────────────────────────────┐
    │ bash /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh │
    └─────────────────────────────────────────────────────────────┘

 2. Verify all Docker containers healthy:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker ps --format 'table {{.Names}}\t{{.Status}}'         │
    │ # Count: should be ~22 containers                           │
    └─────────────────────────────────────────────────────────────┘

 3. Verify all PM2 apps online:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 status                                               │
    │ # Should show 7 apps online                                │
    └─────────────────────────────────────────────────────────────┘

 4. Test critical API endpoints:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -I https://ravynai.wheeler.ai/health                │
    │ curl -I https://predictionradar.wheeler.ai/health         │
    │ curl -I https://superset.wheeler.ai/health               │
    │ curl -I https://grafana.wheeler.ai/api/health            │
    └─────────────────────────────────────────────────────────────┘

 5. Verify monitoring is collecting:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {labels: .labels, health: .health}' │
    └─────────────────────────────────────────────────────────────┘

 6. Verify alerting:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl http://localhost:9093/api/v2/status | jq             │
    └─────────────────────────────────────────────────────────────┘

 RECOVERY COMPLETE WHEN:
 ───────────────────────
 [ ] All ~22 Docker containers running and healthy
 [ ] All 7 PM2 apps online
 [ ] All public endpoints return HTTP 200
 [ ] Prometheus scraping all targets
 [ ] Alertmanager firing test alert to Slack
 [ ] Grafana dashboards loading with recent data
 [ ] Uptime Kuma checks passing
 [ ] LiteLLM proxy routing AI requests
 [ ] Tailscale mesh fully connected

 POST-RECOVERY TASKS:
 ────────────────────
 [ ] Create full volume backup immediately (snapshot current state)
 [ ] Run backup verification (restore to temp, validate integrity)
 [ ] Update all documentation with new AIOPS IP
 [ ] Update UFW rules on COREDB if using IP-based rules (switch to Tailscale-only)
 [ ] File detailed post-mortem within 24 hours
 [ ] Schedule DR test within 2 weeks to validate process
```

---

## 5. Scenario: COREDB Server Total Loss

### 5.1 Impact Assessment

```
What breaks (DATA INTEGRITY CONCERN):
  ├ All dedicated databases unreachable
  ├ MinIO object storage gone (shared files, uploads)
  ├ Qdrant vector embeddings gone
  ├ Backup storage target gone (secondary concern)
  ├ FRGops persistence compromised (EDGE has local PG, may be OK)

What still works:
  ├ EDGE server up (public services available)
  ├ AIOPS services running (may degrade without COREDB)
  ├ AIOPS has local PostgreSQL and Redis instances
  ├ Monitoring continues
  └ Tailscale mesh between EDGE and AIOPS functional

⚠ THIS IS THE WORST DATA-LOSS SCENARIO:
  COREDB holds business-critical data. Recovery depends entirely on
  backup integrity. If backups exist and are verified, data loss is
  limited to RPO window (< 24 hours).
```

### 5.2 Recovery Procedure

**Estimated recovery time: 1-2 hours (with verified backups)**

```
 STEP 1: ASSESS DATA LOSS SCOPE (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Check backup server for latest COREDB backups:
    ┌─────────────────────────────────────────────────────────────┐
    │ ssh root@<BACKUP_ARCHIVE_IP>                              │
    │ ls -la /opt/archive/coredb/databases/                      │
    │ # Find latest dated backup                                │
    │ # Verify file sizes (non-zero)                            │
    │ # Verify GPG signatures                                   │
    │ gpg --verify latest-backup.dump.gpg.sig latest-backup.dump.gpg │
    └─────────────────────────────────────────────────────────────┘

 2. Check if AIOPS can serve as temporary database:
    - AIOPS PostgreSQL (5432) already runs
    - May need to increase disk allocation
    - Can accept COREDB data temporarily

 3. Decision tree:
    ├ Backups verified and recent (<24hr) → Proceed to full restore
    ├ Backups exist but not verified → Verify first (see Section 9)
    ├ Backups missing or corrupted → P1 escalation, data recovery service
    └ COREDB recoverable (not total loss) → See Section 6 (database corruption)

 STEP 2: PROVISION NEW COREDB (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Provision new Hetzner CX32 or larger:
    - Minimum: 8 vCPU, 16 GB RAM, 160 GB NVMe
    - OS: Ubuntu 24.04 LTS
 2. Apply COREDB role hardening (MOST RESTRICTIVE):
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/enterprise/phase1-server-hardening  │
    │ bash apply-server-hardening.sh coredb                     │
    │ # This applies UFW with default deny IN + OUT              │
    └─────────────────────────────────────────────────────────────┘
 3. Install Docker + Tailscale:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -fsSL https://get.docker.com | bash                 │
    │ curl -fsSL https://tailscale.com/install.sh | bash        │
    │ tailscale up --auth-key=<TAILSCALE_AUTH_KEY> --hostname=coredb │
    │ systemctl enable --now docker tailscaled                 │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: RESTORE DATABASES (20-30 min)
 ─────────────────────────────────────────────────────────────────────
 1. Create Docker networks and data services:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker network create data --subnet 172.29.0.0/24          │
    │ docker network create storage --subnet 172.33.0.0/24       │
    │ docker network create vectors --subnet 172.38.0.0/24       │
    └─────────────────────────────────────────────────────────────┘

 2. Start PostgreSQL and Redis containers (empty):
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/coredb/data                       │
    │ docker compose up -d                                      │
    │ # Wait for healthy: docker ps --filter name=postgres       │
    └─────────────────────────────────────────────────────────────┘

 3. Download and decrypt backups:
    ┌─────────────────────────────────────────────────────────────┐
    │ rsync -avz root@<BACKUP_ARCHIVE_IP>:/opt/archive/coredb/ \  │
    │   /opt/restore-temp/                                      │
    │                                                           │
    │ for f in /opt/restore-temp/databases/*.dump.gpg; do        │
    │   gpg --decrypt --output "${f%.gpg}" "$f"                 │
    │ done                                                      │
    └─────────────────────────────────────────────────────────────┘

 4. Restore each database:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Core business database                                   │
    │ docker exec -i postgres-coredb pg_restore \               │
    │   -U postgres -d wheeler --clean --if-exists \            │
    │   < /opt/restore-temp/databases/coredb-main.dump           │
    │                                                           │
    │ # Verify row counts                                        │
    │ docker exec postgres-coredb psql -U postgres -d wheeler \ │
    │   -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC;" │
    └─────────────────────────────────────────────────────────────┘

 5. Restore Redis (AOF or RDB):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Copy RDB file                                            │
    │ docker cp /opt/restore-temp/redis/dump.rdb redis-coredb:/data/ │
    │ docker restart redis-coredb                               │
    │ docker exec redis-coredb redis-cli PING   # Verify         │
    └─────────────────────────────────────────────────────────────┘

 6. Start MinIO and Qdrant:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/coredb/storage && docker compose up -d │
    │ cd /root/infrastructure/coredb/vectors && docker compose up -d │
    │ # MinIO data will be empty — restore from volume backup    │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: RECONNECT SERVICES (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Update Tailscale IP references in AIOPS configs (if new IP):
    - Update Docker Compose environment variables
    - Update Traefik upstream configs
    - Update application database connection strings

 2. Restart dependent services on AIOPS:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Restart services that connect to COREDB                  │
    │ for svc in frgcrm-agent-svc insforge-agent-svc; do         │
    │   pm2 restart "$svc"                                      │
    │ done                                                      │
    │                                                           │
    │ docker restart $(docker ps --filter "name=prediction" -q)    │
    │ docker restart $(docker ps --filter "name=ravynai" -q)      │
    └─────────────────────────────────────────────────────────────┘

 3. Verify connectivity from AIOPS:
    ┌─────────────────────────────────────────────────────────────┐
    │ # From AIOPS                                              │
    │ docker exec postgres-aio-main psql -h <COREDB_TAILSCALE_IP> \ │
    │   -U postgres -d wheeler -c "SELECT 1"                    │
    │                                                           │
    │ docker exec redis-aio-main redis-cli -h <COREDB_TAILSCALE_IP> \│
    │   PING                                                     │
    └─────────────────────────────────────────────────────────────┘

 STEP 5: VALIDATE DATA INTEGRITY (15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Row count comparison (if previous baseline exists):
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec postgres-coredb psql -U postgres -d wheeler \  │
    │   -c "SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY relname;" │
    └─────────────────────────────────────────────────────────────┘

 2. Verify critical business data:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check for expected recent records                        │
    │ # Check for nulls in non-nullable business columns         │
    │ # Verify foreign key integrity                             │
    │ # Run application-level smoke tests                        │
    └─────────────────────────────────────────────────────────────┘

 3. Run application smoke tests from EDGE:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl https://frgops.wheeler.ai/api/health                │
    │ curl https://ravynai.wheeler.ai/health                   │
    └─────────────────────────────────────────────────────────────┘

 POST-RECOVERY TASKS:
 ────────────────────
 [ ] Run full database integrity check (pgcheck)
 [ ] Take immediate fresh backup of restored COREDB
 [ ] Update Tailscale ACLs for new COREDB
 [ ] Verify monitoring exporters are scraping COREDB
 [ ] Document data loss window (RPO gap) for post-mortem
 [ ] File post-mortem within 24 hours
 [ ] Review backup strategy — consider hourly WAL shipping
```

---

## 6. Scenario: Database Corruption

### 6.1 Detection

```
Symptoms of database corruption:
  ├ Application errors: "could not read block", "invalid page"
  ├ PostgreSQL log errors: "invalid page in block", "checksum mismatch"
  ├ Query returning inconsistent or wrong results
  ├ pg_dump failing with data corruption errors
  ├ Replication lag increasing without explanation
  └ pg_stat_database showing xact_commit/xact_rollback mismatch
```

### 6.2 Point-in-Time Recovery Procedure

```
 STEP 1: CONFIRM CORRUPTION (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Check PostgreSQL logs:
    tail -f /var/log/postgresql/postgresql-*.log | grep -iE 'corrupt|checksum|invalid'

 2. Run corruption check:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "SELECT * FROM pg_stat_database WHERE datname='wheeler';" │
    └─────────────────────────────────────────────────────────────┘

 3. If corruption confirmed, IMMEDIATELY stop writes:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Put database in read-only mode                           │
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "ALTER SYSTEM SET default_transaction_read_only = on;"│
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "SELECT pg_reload_conf();"                           │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: IDENTIFY CORRUPTION TIME WINDOW (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Determine when corruption started:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check last successful backup time                        │
    │ ls -lt /opt/backups/databases/                            │
    │                                                           │
    │ # Check WAL archive for last good segment                  │
    │ ls -lt /opt/backups/wal/                                  │
    └─────────────────────────────────────────────────────────────┘

 2. Decision:
    ├ Corruption is recent (< 1 hour) → PITR with WAL replay
    └ Corruption is old (> 1 hour) → Full restore from last clean backup

 STEP 3a: PITR RECOVERY (if recent corruption) (15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Stop the corrupted database:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker stop postgres-aio-main                             │
    └─────────────────────────────────────────────────────────────┘

 2. Restore base backup:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Move corrupted data aside (KEEP FOR FORENSICS)          │
    │ mv /var/lib/docker/volumes/postgres_aio_data/_data \      │
    │    /var/lib/docker/volumes/postgres_aio_data/_data_corrupt │
    │                                                           │
    │ # Restore base backup to data directory                   │
    │ mkdir /var/lib/docker/volumes/postgres_aio_data/_data     │
    │ cp -r /opt/backups/base/latest/* \                       │
    │      /var/lib/docker/volumes/postgres_aio_data/_data/     │
    └─────────────────────────────────────────────────────────────┘

 3. Configure recovery.conf for PITR:
    ┌─────────────────────────────────────────────────────────────┐
    │ cat > /var/lib/docker/volumes/postgres_aio_data/_data/recovery.conf <<'EOF' │
    │ restore_command = 'cp /opt/backups/wal/%f %p'             │
    │ recovery_target_time = '2026-05-23 14:30:00 UTC'          │
    │ recovery_target_action = 'promote'                        │
    │ EOF                                                       │
    └─────────────────────────────────────────────────────────────┘

 4. Start PostgreSQL (will enter recovery mode and replay WAL):
    ┌─────────────────────────────────────────────────────────────┐
    │ docker start postgres-aio-main                            │
    │ docker logs postgres-aio-main --follow                    │
    │ # Watch for: "database system is ready to accept connections" │
    └─────────────────────────────────────────────────────────────┘

 5. Verify recovery point:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "SELECT max(created_at) FROM critical_table;"        │
    └─────────────────────────────────────────────────────────────┘

 STEP 3b: FULL RESTORE (if old corruption) (20 min)
 ─────────────────────────────────────────────────────────────────────
 1. Stop corrupted database
 2. Wipe data directory
 3. Restore from latest verified backup:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec -i postgres-aio-main pg_restore \             │
    │   -U postgres -d wheeler --clean --if-exists \            │
    │   < /opt/backups/databases/latest.dump                    │
    └─────────────────────────────────────────────────────────────┘

 4. Re-enable writes:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "ALTER SYSTEM SET default_transaction_read_only = off;"│
    │ docker exec postgres-aio-main psql -U postgres \           │
    │   -c "SELECT pg_reload_conf();"                           │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: VALIDATE AND RECONNECT (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Run data integrity checks:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check all tables are accessible                           │
    │ docker exec postgres-aio-main psql -U postgres -d wheeler \│
    │   -c "SELECT schemaname, tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY schemaname, tablename;" │
    └─────────────────────────────────────────────────────────────┘

 2. Restart dependent applications:
    ┌─────────────────────────────────────────────────────────────┐
    │ pm2 restart all                                          │
    │ docker restart $(docker ps -q --filter "name=api")         │
    └─────────────────────────────────────────────────────────────┘

 POST-RECOVERY TASKS:
 ────────────────────
 [ ] Identify root cause of corruption (disk failure? bug? operator error?)
 [ ] Run pg_checksums to verify data files
 [ ] If disk issue, replace/migrate storage
 [ ] Schedule pg_dump + pg_restore to rebuild tables (eliminates bloat)
 [ ] Increase WAL archiving frequency (hourly → 15 min)
 [ ] Consider enabling data checksums (initdb --data-checksums)
```

---

## 7. Scenario: Ransomware or Security Compromise

### 7.1 Immediate Response (First 15 Minutes)

```
 ⚠ DO NOT POWER OFF THE COMPROMISED SERVER IMMEDIATELY
    (forensic evidence in memory/RAM will be lost)

 STEP 1: ISOLATE — CONTAIN THE BREACH (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. DO NOT SSH into the compromised server from a trusted machine
    (the attacker may have SSH backdoors/keyloggers)

 2. Use Hetzner/Hostinger out-of-band console (VNC) to access the server
    - This bypasses all SSH and network-based compromises

 3. Isolate at network level:
    ┌─────────────────────────────────────────────────────────────┐
    │ # From cloud console, remove all network interfaces        │
    │ # OR add a firewall rule blocking ALL traffic              │
    │ ufw default deny incoming                                 │
    │ ufw default deny outgoing                                 │
    │ ufw deny from any to any                                  │
    │ ufw enable                                               │
    │                                                           │
    │ # Kill Tailscale (prevents lateral movement through mesh) │
    │ systemctl stop tailscaled                                │
    │ ip link delete tailscale0 2>/dev/null || true             │
    └─────────────────────────────────────────────────────────────┘

 4. IF TAILSCALE IS COMPROMISED:
    ┌─────────────────────────────────────────────────────────────┐
    │ # From Tailscale admin console:                            │
    │ # 1. Remove compromised node's auth key                     │
    │ # 2. Expire the node in the machines list                  │
    │ # 3. Rotate all Tailscale auth keys                         │
    │ # 4. Re-authorize all other nodes with new keys            │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: CREATE FORENSIC SNAPSHOT (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. From cloud console, create a snapshot of the compromised VM
    - This preserves the ENTIRE state for later investigation
    - Label: "COMPROMISED-<server>-<date>-FORENSIC"

 2. Capture running state (if accessible via console):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Memory dump                                             │
    │ dd if=/dev/mem of=/tmp/mem-dump-$(date +%s).img bs=1M     │
    │                                                           │
    │ # Running process list                                    │
    │ ps auxf > /tmp/processes-$(date +%s).txt                  │
    │                                                           │
    │ # Network connections                                      │
    │ ss -tulpn > /tmp/connections-$(date +%s).txt              │
    │                                                           │
    │ # Recent auth log                                         │
    │ cp /var/log/auth.log /tmp/auth-log-$(date +%s).log        │
    │                                                           │
    │ # Docker container list                                   │
    │ docker ps -a > /tmp/docker-ps-$(date +%s).txt              │
    │                                                           │
    │ # Copy all forensic data off-server                       │
    │ # (Use cloud console file transfer, NOT SSH)              │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: NOTIFY AND ESCALATE (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Post in #alerts-critical: "P1: Security compromise detected on <server>"
 2. Call SRE Lead immediately
 3. Do NOT discuss details in unencrypted channels
 4. Preserve ALL logs from other servers (attacker may try to cover tracks)
 5. Collect Tailscale audit logs from admin console
 6. Collect Cloudflare access logs
```

### 7.2 Rebuild Procedure

```
 STEP 4: REBUILD FROM KNOWN-GOOD STATE (30-60 min)
 ─────────────────────────────────────────────────────────────────────
 ⚠ DO NOT restore from the compromised server's backups
    (they may contain backdoors or encrypted payloads).
    Use ONLY the off-site backup archive, verified clean.

 1. Destroy the compromised server (after forensic snapshot confirmed):
    ┌─────────────────────────────────────────────────────────────┐
    │ # From cloud console: delete the compromised VM            │
    │ # This ensures no residual access                          │
    └─────────────────────────────────────────────────────────────┘

 2. Provision a completely new server:
    - Different IP (will be automatically assigned)
    - Fresh OS install
    - NEW SSH host keys (DO NOT reuse old ones)

 3. Apply hardening from scratch:
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/enterprise/phase1-server-hardening  │
    │ bash apply-server-hardening.sh <role>                     │
    └─────────────────────────────────────────────────────────────┘

 4. Rotate ALL credentials before restoring any services:
    ┌─────────────────────────────────────────────────────────────┐
    │ # This is critical — attacker may have exfiltrated secrets │
    │                                                           │
    │ [ ] SSH keys — generate new key pair                      │
    │ [ ] Tailscale auth keys — revoke + reissue                │
    │ [ ] Database passwords — rotate all                       │
    │ [ ] Redis passwords — rotate all                          │
    │ [ ] API keys (OpenAI, Anthropic, DeepSeek) — rotate all   │
    │ [ ] LiteLLM master key — rotate                           │
    │ [ ] Grafana admin password — rotate                       │
    │ [ ] Cloudflare API token — rotate                         │
    │ [ ] SendGrid API key — rotate                             │
    │ [ ] Slack webhook URLs — rotate                           │
    │ [ ] All environment variables containing secrets           │
    │ [ ] Docker registry credentials (if any)                  │
    └─────────────────────────────────────────────────────────────┘

 5. Restore from last KNOWN-GOOD backup (verified pre-compromise):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Use backup from date BEFORE compromise detected          │
    │ # Follow the relevant server recovery procedure above     │
    │ # (Section 3, 4, or 5 for EDGE, AIOPS, or COREDB)         │
    └─────────────────────────────────────────────────────────────┘

 STEP 5: POST-INCIDENT (Within 24 Hours)
 ─────────────────────────────────────────────────────────────────────
 [ ] Engage security firm for forensic analysis of snapshot
 [ ] Determine attack vector (how did they get in?)
 [ ] Assess data exfiltration scope (what did they access?)
 [ ] Legal/compliance notification if user data was accessed (GDPR 72hr)
 [ ] Patch the vulnerability that allowed the compromise
 [ ] Review and tighten all security layers
 [ ] Conduct full penetration test before returning to production
 [ ] File detailed incident report
```

---

## 8. Scenario: DNS / SSL Failure

### 8.1 DNS Outage

```
 STEP 1: DIAGNOSE (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. Check if Cloudflare is down: https://www.cloudflarestatus.com
 2. Check DNS resolution:
    ┌─────────────────────────────────────────────────────────────┐
    │ dig +short wheeler.ai @1.1.1.1                           │
    │ dig +short wheeler.ai @8.8.8.8                           │
    │ dig +short wheeler.ai @<CLOUDFLARE_NS>                     │
    └─────────────────────────────────────────────────────────────┘
 3. Check EDGE server directly:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -H "Host: wheeler.ai" http://187.77.148.88/health    │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: RECOVER DNS (5-10 min)
 ─────────────────────────────────────────────────────────────────────
 1. If Cloudflare is down (rare, but possible):
    - There's nothing to do but wait
    - Post status update to users via status page (if on separate DNS)
    - ETA: Cloudflare typically resolves within 30 minutes

 2. If DNS records are corrupted/deleted:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Restore from Cloudflare DNS backup or terraform state    │
    │ # Key records to verify immediately:                       │
    │ #   A wheeler.ai → 187.77.148.88                          │
    │ #   A *.wheeler.ai → 187.77.148.88                        │
    └─────────────────────────────────────────────────────────────┘

 3. Emergency workaround (if Cloudflare is unrecoverable):
    - Manually set DNS at registrar level (bypass Cloudflare)
    - This loses DDoS protection but restores access
    - ONLY as last resort
```

### 8.2 SSL Certificate Expiry / Renewal Failure

```
 STEP 1: DIAGNOSE (2 min)
 ─────────────────────────────────────────────────────────────────────
 1. Check certificate status:
    ┌─────────────────────────────────────────────────────────────┐
    │ echo | openssl s_client -servername wheeler.ai \          │
    │   -connect wheeler.ai:443 2>/dev/null | \                 │
    │   openssl x509 -noout -dates                             │
    └─────────────────────────────────────────────────────────────┘

 2. Check Traefik ACME logs:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker logs traefik 2>&1 | grep -i acme | tail -20        │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: MANUAL RENEWAL (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. SSH to EDGE via Tailscale:
    ┌─────────────────────────────────────────────────────────────┐
    │ ssh root@100.98.163.17                                     │
    └─────────────────────────────────────────────────────────────┘

 2. Force Traefik certificate renewal:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Dry run first                                            │
    │ docker exec traefik traefik cert renew --dry-run          │
    │                                                           │
    │ # Check for errors in output                              │
    │ # Common issues:                                           │
    │ #   - DNS not pointing to EDGE (check Cloudflare)         │
    │ #   - Port 80 not accessible for HTTP challenge           │
    │ #   - Rate limit exceeded (wait 1 hour)                   │
    │ #   - ACME account issues (re-register)                   │
    └─────────────────────────────────────────────────────────────┘

 3. If dry run succeeds, force actual renewal:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker exec traefik traefik cert renew --force            │
    │ docker restart traefik                                    │
    │                                                           │
    │ # Verify new cert is loaded                                │
    │ echo | openssl s_client -servername wheeler.ai \          │
    │   -connect localhost:443 2>/dev/null | \                  │
    │   openssl x509 -noout -dates                             │
    └─────────────────────────────────────────────────────────────┘

 4. Emergency fallback — manual certbot:
    ┌─────────────────────────────────────────────────────────────┐
    │ # If Traefik ACME completely fails                        │
    │ certbot certonly --standalone --non-interactive \         │
    │   --agree-tos --email infra-alerts@wheeler.ai \           │
    │   -d wheeler.ai -d '*.wheeler.ai'                         │
    │                                                           │
    │ # Copy cert to Traefik location                           │
    │ cp /etc/letsencrypt/live/wheeler.ai/fullchain.pem \       │
    │    /var/lib/docker/volumes/traefik_certs/_data/           │
    │ cp /etc/letsencrypt/live/wheeler.ai/privkey.pem \         │
    │    /var/lib/docker/volumes/traefik_certs/_data/           │
    │ docker restart traefik                                    │
    └─────────────────────────────────────────────────────────────┘
```

---

## 9. Scenario: Tailscale Mesh Partition

### 9.1 Impact Assessment

```
If AIOPS is partitioned from EDGE:
  ├ EDGE cannot proxy to AIOPS services
  ├ All AIOPS-hosted apps become unreachable (Prediction Radar, RavynAI, Superset)
  ├ LiteLLM on EDGE may still work (has direct API keys)
  ├ FRGops on EDGE still works (local database)
  ├ Monitoring on AIOPS still collects, but cannot alert
  └ AIOPS ↔ COREDB path also broken (databases unreachable)

If COREDB is partitioned:
  ├ Services fall back to AIOPS-local databases (graceful degradation)
  ├ Vector searches fail (Qdrant unreachable)
  └ Object storage fails (MinIO unreachable)
```

### 9.2 Recovery Procedure

```
 STEP 1: DIAGNOSE PARTITION SCOPE (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. From each server, check Tailscale status:
    ┌─────────────────────────────────────────────────────────────┐
    │ tailscale status                                          │
    │ tailscale ping <other-server-hostname>                     │
    │ tailscale debug netmap                                    │
    └─────────────────────────────────────────────────────────────┘

 2. Check if Tailscale coordination server is reachable:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -I https://login.tailscale.com                       │
    └─────────────────────────────────────────────────────────────┘

 3. Check WireGuard tunnels:
    ┌─────────────────────────────────────────────────────────────┐
    │ wg show tailscale0                                        │
    │ # Look for: latest handshake, transfer, peer endpoints    │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: RECOVER TAILSCALE (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Try soft recovery first:
    ┌─────────────────────────────────────────────────────────────┐
    │ systemctl restart tailscaled                              │
    │ tailscale up --accept-routes --reset                       │
    │ # Wait 30 seconds for reconnection                         │
    │ tailscale status                                          │
    └─────────────────────────────────────────────────────────────┘

 2. If soft recovery fails, hard reset:
    ┌─────────────────────────────────────────────────────────────┐
    │ tailscale logout                                          │
    │ systemctl stop tailscaled                                │
    │ rm -rf /var/lib/tailscale/*                               │
    │ systemctl start tailscaled                               │
    │ tailscale up --auth-key=<TAILSCALE_AUTH_KEY> \             │
    │   --hostname=<server-hostname> --accept-routes            │
    └─────────────────────────────────────────────────────────────┘

 3. Verify mesh re-established:
    ┌─────────────────────────────────────────────────────────────┐
    │ tailscale status                                          │
    │ tailscale ping edge    # Should show direct connection    │
    │ tailscale ping aiops   # Should show direct connection    │
    │ tailscale ping coredb  # Should show direct connection    │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: VALIDATE SERVICE RECOVERY (5 min)
 ─────────────────────────────────────────────────────────────────────
 1. Verify cross-server connectivity:
    ┌─────────────────────────────────────────────────────────────┐
    │ # From EDGE, test AIOPS services                           │
    │ curl http://100.121.230.28:8007/health                    │
    │ curl http://100.121.230.28:9090/-/healthy                  │
    │                                                           │
    │ # From AIOPS, test COREDB                                  │
    │ docker exec postgres-aio-main psql \                      │
    │   -h <COREDB_TAILSCALE_IP> -U postgres -d wheeler -c "SELECT 1" │
    └─────────────────────────────────────────────────────────────┘

 2. Restart any services that may have cached stale connections:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker restart traefik    # Refresh upstream DNS           │
    │ pm2 restart all          # Refresh DB connections          │
    └─────────────────────────────────────────────────────────────┘
```

---

## 10. Backup Verification Procedure

### 10.1 Monthly Verification (Manual)

```
 SCHEDULE: First Sunday of each month, 06:00 UTC
 DURATION: ~45 minutes
 OWNER: On-call SRE

 STEP 1: SELECT BACKUPS TO VERIFY
 ─────────────────────────────────────────────────────────────────────
 1. Pick the most recent daily backup from each database
 2. Select one volume backup to verify (rotate which volume each month)
 3. Note backup dates and sizes:
    ┌─────────────────────────────────────────────────────────────┐
    │ ls -lh /opt/backups/databases/                             │
    │ ls -lh /opt/backups/volumes/                               │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: RESTORE TO TEMP LOCATION
 ─────────────────────────────────────────────────────────────────────
 1. Create a temporary PostgreSQL instance on AIOPS:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker run -d --name pg-verify \                           │
    │   -e POSTGRES_PASSWORD=verify \                           │
    │   -p 15432:5432 \                                          │
    │   postgres:16-alpine                                      │
    │                                                           │
    │ # Wait for healthy                                        │
    │ sleep 10                                                  │
    │ docker exec pg-verify pg_isready                         │
    └─────────────────────────────────────────────────────────────┘

 2. Decrypt and restore backup:
    ┌─────────────────────────────────────────────────────────────┐
    │ gpg --decrypt /opt/backups/databases/prediction_radar.dump.gpg | \│
    │   docker exec -i pg-verify pg_restore \                   │
    │   -U postgres -d postgres --clean --if-exists             │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: VALIDATE INTEGRITY
 ─────────────────────────────────────────────────────────────────────
 1. Verify row counts (compare with production):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Get production row counts                                │
    │ PROD_COUNTS=$(docker exec postgres-prediction-radar \     │
    │   psql -U postgres -d prediction_radar -t -c \            │
    │   "SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;") │
    │                                                           │
    │ # Get restored row counts                                 │
    │ RESTORE_COUNTS=$(docker exec pg-verify \                  │
    │   psql -U postgres -d postgres -t -c \                    │
    │   "SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;") │
    │                                                           │
    │ # Compare                                                 │
    │ diff <(echo "$PROD_COUNTS") <(echo "$RESTORE_COUNTS")     │
    └─────────────────────────────────────────────────────────────┘

 2. Verify critical data:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Check if recent data exists                              │
    │ # Run a few representative queries                         │
    │ # Check foreign key integrity                              │
    └─────────────────────────────────────────────────────────────┘

 3. Verify GPG signatures:
    ┌─────────────────────────────────────────────────────────────┐
    │ gpg --verify /opt/backups/databases/prediction_radar.dump.gpg.sig \│
    │   /opt/backups/databases/prediction_radar.dump.gpg        │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: CLEANUP
 ─────────────────────────────────────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ docker stop pg-verify && docker rm pg-verify               │
 └─────────────────────────────────────────────────────────────┘

 STEP 5: REPORT
 ─────────────────────────────────────────────────────────────────────
 File a verification report with:
 [ ] Backup date verified
 [ ] Row count comparison (production vs restored)
 [ ] GPG signature verification status
 [ ] Any anomalies found
 [ ] Time to restore (for RTO tracking)
```

---

## 11. DR Test Schedule

```
Test Type           Frequency     Scope                           Owner         Duration
──────────────────  ────────────  ──────────────────────────────  ────────────  ────────
Backup verification  Monthly       Restore 1 DB + 1 volume to     On-call SRE   45 min
                                   temp, validate integrity
Partial DR test     Quarterly      Simulate single-server loss,    SRE Team      2 hours
                                   restore to test environment
Full DR test        Annually       Full infrastructure rebuild     SRE Team      4-6 hours
                                   from backups only, full smoke
                                   test from scratch
Tabletop exercise   Biannually     Walk through worst-case         All teams     2 hours
                                   scenarios with stakeholders
Chaos engineering   Monthly       Random container kill,          On-call SRE   30 min
                                   auto-healing validation
```

---

## 12. Emergency Contact Checklist

```
Role                Name              Phone              Email                    Slack
──────────────────  ────────────────  ─────────────────  ───────────────────────  ─────────
SRE Lead            [TO BE FILLED]    [TO BE FILLED]     [TO BE FILLED]           @sre-lead
SRE On-Call         [TO BE FILLED]    [TO BE FILLED]     [TO BE FILLED]           @sre-oncall
CTO                 [TO BE FILLED]    [TO BE FILLED]     [TO BE FILLED]           @cto
Security Lead       [TO BE FILLED]    [TO BE FILLED]     [TO BE FILLED]           @security
DBA                 [TO BE FILLED]    [TO BE FILLED]     [TO BE FILLED]           @dba
AI/ML Lead          [TO BE FILLED]    [TO BE FILLED]     [TO BE FILLED]           @ai-lead

External Contacts:
──────────────────────────────────────────────────────────────────
Hostinger Support:  https://www.hostinger.com/contacts
Hetzner Support:    https://www.hetzner.com/support
                    Phone: +49 9831 5050
Cloudflare Support: https://support.cloudflare.com
Tailscale Support:  https://tailscale.com/contact
SendGrid Support:   https://support.sendgrid.com
Let's Encrypt:      https://letsencrypt.org/contact/  (community)
PagerDuty:          https://<subdomain>.pagerduty.com/incidents
```

---

## 13. Post-Mortem Template

```
═══════════════════════════════════════════════════════════════════
                  WHEELER ENTERPRISE — INCIDENT POST-MORTEM
═══════════════════════════════════════════════════════════════════

Incident ID:        INC-YYYY-NNN
Severity:           P1 / P2 / P3 / P4
Date/Time Start:    YYYY-MM-DD HH:MM UTC
Date/Time Resolved: YYYY-MM-DD HH:MM UTC
Total Duration:     X hours Y minutes
Services Affected:  [list]
Data Loss:          [Yes/No — if yes, scope + RPO gap]
Author:             [Name]
Reviewers:          [Names]

── 1. EXECUTIVE SUMMARY ──────────────────────────────────────────
[2-3 sentences: What happened, impact, root cause in plain language]

── 2. TIMELINE ────────────────────────────────────────────────────
[UTC]  [Event — who did what, what was observed]
14:32  Prometheus alert: HostUnreachable for AIOPS fired
14:33  On-call engineer acknowledged alert
14:35  Engineer confirmed AIOPS unresponsive via Tailscale
14:38  DR plan activated, P1 declared
14:42  Hetzner console accessed — server kernel panic
14:45  Server rebooted via console
14:50  All services self-healed and came back online
14:55  Healthcheck passed, P1 resolved

── 3. ROOT CAUSE ANALYSIS ────────────────────────────────────────
[Technical root cause with evidence]
[Why did it happen?]
[Why wasn't it caught earlier?]

── 4. IMPACT ASSESSMENT ──────────────────────────────────────────
Services affected:
  [list each service and duration of impact]
User impact:
  [number of users affected, what they experienced]
Data impact:
  [any data lost, corrupted, or exposed]
Revenue impact:
  [estimated financial impact if applicable]

── 5. WHAT WENT WELL ─────────────────────────────────────────────
[At least 3 things that worked correctly]
  + Monitoring detected the issue within 30 seconds
  + On-call engineer responded within 2 minutes
  + DR procedure was clear and easy to follow

── 6. WHAT WENT WRONG ────────────────────────────────────────────
[At least 3 things that need improvement]
  - No pre-configured console access (had to reset password)
  - Auto-healing didn't catch this issue (kernel panic)
  - Alert did not include runbook link

── 7. ACTION ITEMS ───────────────────────────────────────────────
[ID]  [Action]                              [Owner]    [Due Date]  [Priority]
A-1   Configure out-of-band console access   @sre      2026-06-01  P1
      on all servers
A-2   Add runbook_url annotation to all      @sre      2026-06-15  P2
      Prometheus alert rules
A-3   Schedule kernel panic recovery test    @sre      2026-07-01  P3

── 8. APPENDIX ────────────────────────────────────────────────────
[Link to Grafana dashboard snapshot]
[Link to relevant logs]
[Link to Slack thread]
[Link to PagerDuty incident]

═══════════════════════════════════════════════════════════════════
```

---

## Document Control

| Version | Date       | Author   | Changes                   |
|---------|------------|----------|---------------------------|
| 1.0.0   | 2026-05-23 | SRE Team | Initial DR runbook        |

**Next Review:** 2026-08-23
**DR Test Due:** 2026-06-23 (monthly backup verification)
