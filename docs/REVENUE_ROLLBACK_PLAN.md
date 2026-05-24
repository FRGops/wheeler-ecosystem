# Wheeler Ecosystem — Revenue Rollback Plan

> **Classification**: PRODUCTION-SAFE — INTERNAL ONLY
> **Effective date**: 2026-05-23
> **Owners**: Platform Engineering / On-Call SRE
> **Infrastructure**: 3-server (EDGE / AIOPS / COREDB) + Tailscale mesh
>
> **WARNING**: This document describes procedures that directly affect
> revenue-generating services.  Unauthorized or careless execution WILL cause
> downtime and/or data loss.  Every rollback MUST be logged and communicated
> to stakeholders per the templates below.

---

## Table of Contents

1. [Rollback Philosophy & Constraints](#1-rollback-philosophy--constraints)
2. [Pre-Rollback Checklist](#2-pre-rollback-checklist)
3. [Service-by-Service Rollback Procedures](#3-service-by-service-rollback-procedures)
4. [Rollback Decision Tree](#4-rollback-decision-tree)
5. [Timing Estimates](#5-timing-estimates)
6. [Communication Templates](#6-communication-templates)
7. [Post-Rollback Verification](#7-post-rollback-verification)
8. [Rollback Log Template](#8-rollback-log-template)

---

## 1. Rollback Philosophy & Constraints

### 1.1 Core Principle

> **Roll back fast, debug later.** Revenue services must be restored within the
> shortest possible window.  A partial but functional rollback is better than
> waiting for a perfect one.

### 1.2 Rules

| Rule | Explanation |
|------|-------------|
| **Backup before touching** | Every rollback action must be preceded by a snapshot of the state it will change. |
| **One stage at a time** | Never batch multiple unrelated changes.  A→B→C→D→E in strict order. |
| **Verify after each stage** | Pre-check → Action → Post-verify.  Do NOT proceed if a stage fails post-verify. |
| **Never roll back databases** | Schema migrations and data changes are forward-only unless a tested DR procedure exists. |
| **Log everything** | Timestamps, commands run, output, operator identity. |
| **Communicate** | Notify stakeholders BEFORE starting and AFTER completing (see Section 6). |

### 1.3 Constraints

- **AIOPS is the control plane**: all rollback commands originate from AIOPS (5.78.140.118).  EDGE and COREDB are reached via SSH.
- **Tailscale is the backchannel**: if Tailscale is down, EDGE rollback requires direct Hostinger console access.
- **PM2 dump files are ephemeral**: the `pm2 save` snapshot reflects state at the moment it was taken.  Long-running sessions may diverge.
- **Docker containers may have volumes on COREDB**: restoring container images alone is insufficient if volume data changed.
- **DNS TTLs apply**: if rollback involves DNS changes, propagation may add 5-60 minutes depending on domain TTL.

---

## 2. Pre-Rollback Checklist

Complete this checklist BEFORE initiating any rollback stage.

### 2.1 Operator Readiness

- [ ] I have read this document in full.
- [ ] I have the rollback script: `/root/scripts/revenue-rollback-checklist.sh`
- [ ] I have root access to AIOPS (5.78.140.118).
- [ ] I have SSH access to EDGE (187.77.148.88) or Hostinger console.
- [ ] I have SSH access to COREDB (5.78.210.123) or Hetzner console.
- [ ] My SSH keys are loaded and agent is running (`ssh-add -l`).
- [ ] I have a stable internet connection (not mobile VPN).
- [ ] I have a second terminal open as a fallback in case I break my session.

### 2.2 Environment Verification

- [ ] Tailscale mesh is up: `tailscale status` on AIOPS shows EDGE at 100.98.x.x.
- [ ] PM2 daemon is running: `pm2 ping` returns `pong`.
- [ ] Docker daemon is running: `docker info` succeeds.
- [ ] I can reach the internet: `curl -s https://1.1.1.1` succeeds.
- [ ] I know which domains are currently routing where (check `/root/docs/DOMAIN_ROUTING_MAP.md`).

### 2.3 Backup Verification

- [ ] Automated backup completed (the rollback script does this on first run).
- [ ] Backup directory exists: `ls /root/rollback-backup-*`
- [ ] PM2 process list saved: `cat /root/rollback-backup-*/pm2-jlist.json | jq .[].name`
- [ ] Docker state saved: `cat /root/rollback-backup-*/docker-ps.txt`
- [ ] Environment files saved: `ls -la /root/rollback-backup-*/root/.env`

### 2.4 Stakeholder Communication (pre-rollback)

- [ ] Notification sent to #platform-alerts (or equivalent channel).
- [ ] Notification sent to revenue team stakeholders.
- [ ] Maintenance window confirmed (if applicable).
- [ ] Escalation contact identified and available.

---

## 3. Service-by-Service Rollback Procedures

### 3.1 Traefik / Nginx Upstream Restore (Stage A)

**Scope**: Restore reverse proxy configuration so public traffic routes to the
pre-cutover upstreams.  This is the HIGHEST PRIORITY rollback because it
directly controls what end users see.

**Pre-check**:
```bash
# On AIOPS
ssh root@187.77.148.88 "ls -la /etc/traefik/dynamic/ && cat /etc/nginx/upstreams.d/*.conf"
```

**Rollback action**:
1. On AIOPS, locate the most recent Traefik config backup under `/root/rollback-backup-*/traefik/`.
2. SCP the backup to EDGE:
   ```bash
   scp -r /root/rollback-backup-*/traefik/* root@187.77.148.88:/etc/traefik/dynamic/
   ```
3. On EDGE, validate config and reload:
   ```bash
   ssh root@187.77.148.88 "traefik healthcheck && nginx -t && nginx -s reload"
   ```
4. If Traefik runs in Docker on EDGE:
   ```bash
   ssh root@187.77.148.88 "docker restart traefik"
   ```

**Post-verify**:
```bash
for domain in fundsrecoverygroup.com predictionradar.app surplusai.io; do
    curl -s -o /dev/null -w "${domain}: %{http_code}\n" "https://${domain}"
done
```
Expected: HTTP 200 or 301/302 for all domains.

**Manual override**: If SCP fails, log into EDGE directly and copy from the
Hostinger file manager or a local backup on EDGE at `/root/backups/`.

---

### 3.2 PM2 App Restore (Stage B)

**Scope**: Restart and restore PM2-managed Node.js/Python applications.

**Per-app procedures**:

#### frgcrm-api
```bash
# Pre-check
pm2 describe frgcrm-api
curl -s http://localhost:$(pm2 jlist | jq -r '.[]|select(.name=="frgcrm-api")|.pm2_env.env.PORT // "3001"')/health

# Rollback
pm2 restart frgcrm-api --update-env
# If errored, kill and re-spawn from last dump:
pm2 delete frgcrm-api
pm2 resurrect

# Post-verify
pm2 describe frgcrm-api | grep -E "status|restarts"
curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/health
```

#### frgcrm-agent-svc
```bash
pm2 restart frgcrm-agent-svc --update-env
# Post-verify: check logs for agent loop start
pm2 logs frgcrm-agent-svc --lines 5 --nostream
```

#### frgcrm-mirror-test
```bash
pm2 restart frgcrm-mirror-test --update-env
```

#### insforge-agent-svc
```bash
pm2 restart insforge-agent-svc --update-env
```

#### surplusai-scraper-agent-svc
```bash
pm2 restart surplusai-scraper-agent-svc --update-env
```

#### voice-agent-svc
```bash
pm2 restart voice-agent-svc --update-env
```

**Post-verify (all apps)**:
```bash
pm2 list
# All revenue apps should show status=online, restarts=0
```

---

### 3.3 Docker Container Restore

**Scope**: Restore Docker containers on AIOPS to pre-cutover images/tags.

**Note**: Docker containers managed by `docker-compose` should use compose
rollback; standalone containers use image tag pinning.

#### Container-by-container procedure:

```bash
# Pre-check
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Rollback (example for a container that was upgraded to a broken tag)
docker stop <container-name>
docker rm <container-name>
docker run -d --name <container-name> \
  --restart unless-stopped \
  <original-image-tag>

# OR, for docker-compose services:
cd /opt/<service>
docker-compose down
# Restore old docker-compose.yml from backup
cp /root/rollback-backup-*/opt/<service>/docker-compose.yml .
docker-compose up -d
```

#### Revenue-critical Docker containers

| Container | Restore Priority | Notes |
|-----------|-----------------|-------|
| prediction-radar | CRITICAL | Full-stack app. Restore entire compose stack. |
| ravynai | HIGH | Agent service. Restart and check logs. |
| docuseal | MEDIUM | Document signing. Verify API responds. |
| superset | MEDIUM | Analytics. Verify dashboard loads. |
| grafana | LOW | Dashboards. Non-revenue directly. |
| prometheus | LOW | Metrics. Non-revenue directly. |
| netdata | LOW | Monitoring. Non-revenue directly. |
| uptime-kuma | LOW | Monitoring. Non-revenue directly. |
| portainer | LOW | Management UI. Non-revenue directly. |

**Post-verify**:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# All critical containers should show "Up"
```

---

### 3.4 Environment Variable Restore (Stage D)

**Scope**: Restore `.env` files for all revenue applications.

**Location mapping**:

| Application | .env Path |
|-------------|-----------|
| frgcrm-api | `/opt/frgcrm/.env` |
| frgcrm-agent-svc | `/opt/frgcrm/.env` (shared) |
| surplusai-scraper | `/opt/surplusai/.env` |
| insforge-agent-svc | `/opt/insforge/.env` |
| System-wide environment | `/etc/environment` |
| Root shell profile | `/root/.env` |

**Rollback procedure**:
```bash
# For each file:
cp /root/rollback-backup-XXXX/<original-path> <original-path>

# After restore, reload environment:
set -a; source /etc/environment; set +a

# Restart affected PM2 apps so they pick up new env:
pm2 restart frgcrm-api --update-env
pm2 restart surplusai-scraper-agent-svc --update-env
pm2 restart insforge-agent-svc --update-env
```

**WARNING**: Environment files may contain API keys, database passwords, and
service tokens.  NEVER expose these in logs or chat.  The rollback script
copies them directly without printing contents.

---

### 3.5 Database Connection Restore

**Scope**: Ensure all revenue apps can reach their databases on COREDB.

**Pre-check**:
```bash
# From AIOPS, test database connectivity:
# PostgreSQL (standard port 5432)
psql -h 5.78.210.123 -U <db-user> -d <db-name> -c "SELECT 1;"

# Redis (standard port 6379)
redis-cli -h 5.78.210.123 PING

# MinIO (standard port 9000)
curl -s http://5.78.210.123:9000/minio/health/live
```

**Rollback if connection fails**:
1. Check Tailscale connectivity: `tailscale ping 100.121.x.x` (COREDB's TS IP)
2. Check COREDB firewall: `ssh root@5.78.210.123 "ufw status"`
3. Check database services on COREDB: `ssh root@5.78.210.123 "systemctl status postgresql redis-server"`
4. If needed, restart database services:
   ```bash
   ssh root@5.78.210.123 "systemctl restart postgresql redis-server"
   ```

---

## 4. Rollback Decision Tree

```
                      ┌─────────────────────────┐
                      │  ISSUE DETECTED          │
                      │  (alert, monitor, user)   │
                      └─────────┬───────────────┘
                                │
                    ┌───────────▼───────────┐
                    │ Is revenue impacted?   │
                    │ (leads lost, payments  │
                    │  failing, site down)   │
                    └──────┬───────┬────────┘
                           │NO     │YES
                           ▼       ▼
                 ┌─────────────┐  ┌────────────────────────┐
                 │ Fix forward  │  │ Is root cause known    │
                 │ (normal      │  │ AND fix time < 30 min? │
                 │  workflow)   │  └───────┬───────┬────────┘
                 └─────────────┘          │YES    │NO
                                          ▼       ▼
                               ┌──────────────┐  ┌────────────────┐
                               │ Fix forward   │  │ INITIATE        │
                               │ within window │  │ ROLLBACK        │
                               └──────────────┘  └───────┬────────┘
                                                         │
                                            ┌────────────▼───────────┐
                                            │ Which tier is broken?   │
                                            └──┬────────┬────────┬───┘
                                               │        │        │
                                          TIER 1   TIER 2   TIER 3
                                          (proxy)  (app)    (data)
                                               │        │        │
                                          Stage A  Stage B   ESCALATE
                                                   + D,E    to DBA
```

### Tier definitions

| Tier | What | Rollback Stage | Max Acceptable Downtime |
|------|------|---------------|--------------------------|
| Tier 1 — Proxy/LB | Traefik, Nginx upstreams | A | 5 minutes |
| Tier 2 — Application | PM2 apps, Docker containers | B, D, E | 15 minutes |
| Tier 3 — Data | PostgreSQL, Redis, MinIO | Escalate to DBA | 30 minutes (with DR) |

---

## 5. Timing Estimates

| Stage | Action | Best Case | Typical | Worst Case |
|-------|--------|-----------|---------|------------|
| BAK | Backup current state | 30 sec | 1 min | 3 min |
| PRE | System pre-checks | 15 sec | 30 sec | 2 min |
| A | Traefik/Nginx restore | 1 min | 3 min | 10 min (manual EDGE access) |
| B | PM2 app restart | 30 sec | 2 min | 5 min (resurrect + debug) |
| C | Domain verification | 20 sec | 1 min | 5 min (DNS propagation) |
| D | Env file restore + restart | 30 sec | 2 min | 5 min |
| E | CRM / lead capture verify | 30 sec | 2 min | 5 min |
| **F** | **Full rollback (A→E)** | **3 min** | **10 min** | **30 min** |

> **Note**: Times assume Tailscale mesh is healthy and SSH keys are loaded.
> Add 5-10 minutes if you need to retrieve 2FA codes or VPN in.

---

## 6. Communication Templates

### 6.1 Pre-Rollback Notification

```
Subject: [ACTION REQUIRED] Revenue rollback initiated — Wheeler ecosystem

Team,

A revenue-impacting issue has been detected:
  - Issue: <BRIEF DESCRIPTION>
  - Affected services: <LIST>
  - Detected at: <TIMESTAMP>

I am initiating a CONTROLLED ROLLBACK of the Wheeler ecosystem services.

  - Rollback plan: /root/docs/REVENUE_ROLLBACK_PLAN.md
  - Rollback script: /root/scripts/revenue-rollback-checklist.sh
  - Expected downtime: <TIMING ESTIMATE>
  - Rollback stages to execute: <A/B/C/D/E/F>

Updates will follow on this channel.  Do NOT deploy, restart, or modify any
service until the all-clear is given.

— <OPERATOR NAME>, on-call
```

### 6.2 Stage-Complete Update

```
Subject: [UPDATE] Revenue rollback Stage <X> complete — Wheeler ecosystem

Stage <X> (<DESCRIPTION>) completed:
  - Started: <TIMESTAMP>
  - Completed: <TIMESTAMP>
  - Duration: <DURATION>
  - Result: SUCCESS / FAILURE / PARTIAL
  - Verification: <BRIEF SUMMARY>

<If SUCCESS:> Proceeding to Stage <next>.
<If FAILURE:> Halting rollback.  Investigation underway.  Next update in <TIME>.

— <OPERATOR NAME>
```

### 6.3 Rollback-Complete Notification

```
Subject: [RESOLVED] Revenue rollback complete — Wheeler ecosystem restored

Team,

The Wheeler ecosystem revenue rollback is COMPLETE.

  - Rollback started: <TIMESTAMP>
  - Rollback completed: <TIMESTAMP>
  - Total downtime: <DURATION>
  - Stages executed: <LIST>
  - Rollback log: /root/rollback-<TIMESTAMP>.log
  - Backup preserved at: /root/rollback-backup-<TIMESTAMP>/

Verification summary:
  - fundsrecoverygroup.com: HTTP <CODE> (OK/CHECK)
  - predictionradar.app: HTTP <CODE> (OK/CHECK)
  - surplusai.io: HTTP <CODE> (OK/CHECK)
  - frgops.fundsrecoverygroup.tech: HTTP <CODE> (OK/CHECK)
  - wheeler.frgop.io: HTTP <CODE> (OK/CHECK)

All revenue services are operational.  Normal deployment freeze is lifted.

Post-rollback actions required: <LIST OR "None">

— <OPERATOR NAME>
```

---

## 7. Post-Rollback Verification Checklist

After EVERY rollback (partial or full), verify the following:

### 7.1 Public Endpoints

- [ ] `https://fundsrecoverygroup.com/` returns HTTP 200
- [ ] `https://fundsrecoverygroup.com/contact` loads the lead form
- [ ] `https://fundsrecoverygroup.com/api/health` returns healthy status
- [ ] `https://predictionradar.app/` returns HTTP 200
- [ ] `https://predictionradar.app/api/health` returns healthy status
- [ ] `https://surplusai.io/` returns HTTP 200
- [ ] `https://frgops.fundsrecoverygroup.tech/` returns HTTP 200
- [ ] `https://wheeler.frgop.io/` returns HTTP 200

### 7.2 PM2 Applications

- [ ] `frgcrm-api` — status: online, restarts: 0
- [ ] `frgcrm-agent-svc` — status: online
- [ ] `frgcrm-mirror-test` — status: online
- [ ] `insforge-agent-svc` — status: online
- [ ] `surplusai-scraper-agent-svc` — status: online
- [ ] `voice-agent-svc` — status: online

### 7.3 Docker Containers (critical subset)

- [ ] `prediction-radar` — running, ports bound
- [ ] `ravynai` — running
- [ ] `docuseal` — running

### 7.4 Database Connectivity (from AIOPS)

- [ ] PostgreSQL reachable on COREDB
- [ ] Redis reachable on COREDB
- [ ] MinIO health endpoint responds

### 7.5 Monitoring

- [ ] Uptime Kuma shows all monitors green
- [ ] Grafana dashboards loading
- [ ] Prometheus scraping targets healthy
- [ ] Netdata collecting metrics

### 7.6 Security

- [ ] No `.env` files exposed in log output
- [ ] No secrets in rollback log
- [ ] Rollback backup directory has correct permissions (700)

---

## 8. Rollback Log Template

Record the following for every rollback event:

```text
================================================================================
ROLLBACK EVENT LOG
================================================================================
Date:                  ____________________
Operator:              ____________________
Trigger:               ( ) Alert  ( ) User report  ( ) Scheduled  ( ) Other: __
Issue description:     ________________________________________________________
Affected services:     ________________________________________________________

ROLLBACK DETAILS
-----------------
Stages executed:        A B C D E F  (circle all that apply)
Start time:            ____________________
End time:              ____________________
Total downtime:        ____________________
Automated script used: ( ) Yes  ( ) No — manual

STAGE RESULTS
--------------
[ ] Stage A (Traefik/Nginx)    — Result: SUCCESS / FAILURE / N/A
[ ] Stage B (PM2 apps)         — Result: SUCCESS / FAILURE / N/A
[ ] Stage C (Domain verify)    — Result: SUCCESS / FAILURE / N/A
[ ] Stage D (Env files)        — Result: SUCCESS / FAILURE / N/A
[ ] Stage E (CRM/Lead capture) — Result: SUCCESS / FAILURE / N/A

UNEXPECTED ISSUES
------------------
________________________________________________________
________________________________________________________

POST-ROLLBACK VERIFICATION
----------------------------
[ ] All public domains respond correctly
[ ] All PM2 apps online
[ ] All critical Docker containers running
[ ] Database connectivity confirmed
[ ] Monitoring dashboards green
[ ] Stakeholders notified

ARTIFACTS
----------
Rollback log:          /root/rollback-________________.log
Backup directory:      /root/rollback-backup-________________/
Follow-up actions:     ________________________________________________________

OPERATOR SIGNATURE:    ____________________  Date: ____________________
================================================================================
```

---

## Appendix A: Quick Reference Card

```
╔══════════════════════════════════════════════════════════════════╗
║  WHEELER REVENUE ROLLBACK — QUICK REFERENCE                     ║
╠══════════════════════════════════════════════════════════════════╣
║  Script:   /root/scripts/revenue-rollback-checklist.sh           ║
║  Plan:     /root/docs/REVENUE_ROLLBACK_PLAN.md                   ║
║  Log:      /root/rollback-YYYYMMDD-HHMMSS.log                   ║
║  Backup:   /root/rollback-backup-YYYYMMDD-HHMMSS/               ║
╠══════════════════════════════════════════════════════════════════╣
║  AIOPS:    5.78.140.118  (control plane — YOU ARE HERE)        ║
║  EDGE:     187.77.148.88 (Traefik, public websites)             ║
║  COREDB:   5.78.210.123  (PostgreSQL, Redis, MinIO)             ║
╠══════════════════════════════════════════════════════════════════╣
║  Stage A:  Traefik/Nginx upstreams    → 1-3 min                  ║
║  Stage B:  PM2 app restart            → 1-2 min                  ║
║  Stage C:  Domain verification        → 1 min                    ║
║  Stage D:  Env file restore           → 1-2 min                  ║
║  Stage E:  CRM/lead capture verify    → 1-2 min                  ║
║  Stage F:  FULL ROLLBACK              → 3-10 min                 ║
╠══════════════════════════════════════════════════════════════════╣
║  Revenue domains:                                                ║
║    fundsrecoverygroup.com                                       ║
║    predictionradar.app                                          ║
║    surplusai.io                                                 ║
║    frgops.fundsrecoverygroup.tech                               ║
║    wheeler.frgop.io                                             ║
╚══════════════════════════════════════════════════════════════════╝
```

---

> **END OF DOCUMENT** — Review annually or after any significant infrastructure change.
