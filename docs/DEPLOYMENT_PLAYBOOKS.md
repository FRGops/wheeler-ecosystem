# Wheeler Deployment & Release Engineering -- Operational Playbooks

**Version:** 2.0.0
**Last Updated:** 2026-05-23
**Owner:** Platform Engineering / Release Engineering
**Scope:** All Wheeler services across EDGE (Hostinger / 187.77.148.88), AIOPS (Hetzner / 5.78.140.118), and COREDB (Hetzner / 5.78.210.123)
**Classification:** PRODUCTION-SAFE -- INTERNAL ONLY
**Supersedes:** v1.0 (DEPLOYMENT_PLAYBOOKS.md dated 2026-05-23)

---

## Table of Contents

1. [Playbook Usage Guide](#playbook-usage-guide)
2. [Playbook 1: Frontend Deploy](#playbook-1-frontend-deploy)
3. [Playbook 2: API Deploy](#playbook-2-api-deploy)
4. [Playbook 3: AI Worker Deploy](#playbook-3-ai-worker-deploy)
5. [Playbook 4: DB Migration Deploy](#playbook-4-db-migration-deploy)
6. [Playbook 5: Emergency Rollback](#playbook-5-emergency-rollback)
7. [Playbook 6: Hotfix Deploy](#playbook-6-hotfix-deploy)
8. [Playbook 7: Canary Release](#playbook-7-canary-release)
9. [Playbook 8: Failed Deploy Recovery](#playbook-8-failed-deploy-recovery)
10. [Appendix A: Command Quick Reference](#appendix-a-command-quick-reference)
11. [Appendix B: Deployment Log Template](#appendix-b-deployment-log-template)
12. [Appendix C: Incident Communication Templates](#appendix-c-incident-communication-templates)
13. [Appendix D: Troubleshooting Common Scenarios](#appendix-d-troubleshooting-common-scenarios)

---

## Playbook Usage Guide

### Who Should Use These Playbooks

| Role | Playbooks Authorized | Notes |
|------|---------------------|-------|
| Release Engineer | All 8 | Full deployment authority |
| On-Call SRE | 3, 5, 6, 8 | Rollback, hotfix, recovery |
| Senior Developer | 1, 2, 3, 4 | Deploy with SRE approval |
| Junior Developer | 6 only | Hotfix with code review |
| Contractor | None | Read-only access |

### How to Read Each Playbook

Every playbook follows a strict, consistent format:

- **Pre-conditions**: What must be true before you begin. Do not skip verification.
- **Duration estimate**: Wall-clock time the procedure takes under normal conditions.
- **Who can execute**: Required role and access level.
- **Step-by-step instructions**: Numbered steps with exact commands. Commands prefixed with `$` are executed on the control node (AIOPS unless specified). Commands prefixed with `EDGE$` or `COREDB$` indicate SSH target.
- **Expected output**: What success looks like at each step. If you see anything different, stop and consult Troubleshooting.
- **Rollback steps**: How to undo each step in reverse order. Prefer the automated rollback path.
- **Troubleshooting**: Common failure modes observed in production, with known fixes.

### Safety Rules (Read Before Any Deployment)

1. **Never deploy without a verified backup.** The pre-deploy-backup step is mandatory, not optional.
2. **Never deploy during P0 incident.** Fix the incident first, then deploy.
3. **Never skip health checks.** If a health check fails, investigate before proceeding.
4. **Never deploy alone at night.** At least one other person must be reachable.
5. **Always log the deployment.** Use the template in Appendix B before and after every deploy.
6. **Always announce maintenance windows.** Use #deployments Slack channel.
7. **Always have the rollback Playbook open.** If you cannot roll back within 5 minutes, you should not be deploying.

### Deployment Severity Classification

| Severity | Definition | Playbook | Approval Required |
|----------|-----------|----------|-------------------|
| **Routine** | Planned feature deploy, tested on staging | 1, 2, 3 | Release Engineer |
| **Maintenance** | DB migration, config change | 4 | Release Engineer + DBA |
| **Urgent** | Critical bug fix, security patch | 6 | On-Call SRE + Tech Lead |
| **Canary** | Gradual rollout of risky change | 7 | Release Engineer + SRE |
| **Emergency** | Production is down or degraded | 5, 8 | Any authorized operator |

### Server Reference

| Alias | Host | Provider | Role | Key Services |
|-------|------|----------|------|-------------|
| EDGE | 187.77.148.88 | Hostinger | Public ingress, static hosting | Traefik, Nginx, FRGCRM Frontend, LiteLLM Proxy, Chatwoot, n8n, Webhook Receiver |
| AIOPS | 5.78.140.118 | Hetzner | Application compute, AI workloads | FRGCRM API, SurplusAI API, RavynAI API, Wheeler Brain, OpenClaw, PM2 process manager, Prediction Radar containers |
| COREDB | 5.78.210.123 | Hetzner | Shared state, persistence | PostgreSQL 16, Redis 7, MinIO, pgvector, automated backups |

---

## Playbook 1: Frontend Deploy

### Pre-conditions

- [ ] CI build is green on the target commit SHA (verified in GitHub Actions)
- [ ] You have SSH access to the EDGE node (187.77.148.88) via Tailscale or direct
- [ ] You have sudo access on EDGE (or the user running Traefik/Nginx)
- [ ] The frontend service has a valid `.env` file at `/opt/wheeler/env/{service}/production/.env`
- [ ] preflight-check.sh exists at `/opt/wheeler/scripts/preflight-check.sh` on EDGE
- [ ] pre-deploy-backup.sh exists at `/opt/wheeler/scripts/pre-deploy-backup.sh` on EDGE
- [ ] No active P0/P1 incident on the frontend service
- [ ] #deployments channel has been notified

### Duration Estimate

| Phase | Time |
|-------|------|
| Pre-flight + backup | 2-4 minutes |
| Build artifact pull / image pull | 3-10 minutes (depends on artifact size) |
| Config update (if needed) | 1-2 minutes |
| Routing reload | 30 seconds |
| Health check + smoke test | 2-3 minutes |
| Monitoring period | 5 minutes |
| **Total (best case)** | **~12 minutes** |
| **Total (with Docker image pull)** | **~20 minutes** |

### Who Can Execute

- Release Engineer (primary)
- On-Call SRE (authorized)
- Senior Developer (with Release Engineer approval)

---

### Step-by-Step Instructions

#### Step 1: Verify CI Build Passed

```
$ gh run list --repo wheeler-org/<service> --branch main --limit 5 --json status,headSha,conclusion
```

Verify the commit SHA matches the version you intend to deploy and the conclusion is `success`.

**Expected output:** JSON showing `"conclusion": "success"` for the target SHA.

---

#### Step 2: SSH to EDGE Node

```
$ ssh -i ~/.ssh/wheeler_deploy_edge deployer@187.77.148.88
```

Verify connectivity and that you are on the correct host:

```
EDGE$ hostname
EDGE$ uptime
```

**Expected output:** Hostname responds with EDGE hostname. Uptime shows > 1 day (if the server has been stable).

---

#### Step 3: Run Preflight Check for the Frontend Service

```
EDGE$ /opt/wheeler/scripts/preflight-check.sh frontend <service-name> production
```

This script verifies:

- Required directories exist and are writable
- Traefik/Nginx configuration syntax is valid
- SSL certificates are present and not expiring within 7 days
- Environment file passes validation (no missing required vars, no syntax errors)
- Ports needed by the service are available
- Disk space is at least 20% free on the target partition
- System load is below warning threshold
- Network connectivity to AIOPS via Tailscale

**Expected output:**

```
PASS  [1/9] Directory check: /opt/wheeler/services/<service>/production exists and writable
PASS  [2/9] Config syntax: nginx -t succeeded
PASS  [3/9] SSL check: certificates valid, earliest expiry in 45 days
PASS  [4/9] Environment validation: all required vars present
PASS  [5/9] Port check: port 3000 available
PASS  [6/9] Disk space: 42% free on /
PASS  [7/9] System load: 1.2 (below threshold 4.0)
PASS  [8/9] Connectivity: can reach AIOPS (5.78.140.118) via Tailscale
PASS  [9/9] Tailscale mesh: EDGE can reach COREDB (5.78.210.123)
ALL CHECKS PASSED -- ready to deploy
```

If any check fails, fix the issue before proceeding. Common failures:

- **SSL expiring within 7 days:** Renew with certbot: `EDGE$ certbot renew --force-renewal -d <domain>`
- **Environment validation failure:** Missing or malformed env vars. Compare against `.env.example`.
- **Port conflict:** Another process is using the target port. Identify with `lsof -i :<port>`.
- **Connectivity failure:** Check Tailscale status: `EDGE$ tailscale status`

---

#### Step 4: Run Pre-Deploy Backup

```
EDGE$ /opt/wheeler/scripts/pre-deploy-backup.sh frontend <service-name> production
```

This creates:

- Snapshot of the current service directory: `/opt/wheeler/backups/frontend/<service-name>/production/<timestamp>/`
- Copy of the current `.env` file
- Copy of current Traefik/Nginx config (label or file)
- Metadata JSON with deploy timestamp, service version, operator identity

**Expected output:**

```
Backup started at 2026-05-23T14:05:00Z
  [OK] Service directory copied to /opt/wheeler/backups/frontend/<service>/production/20260523-140500/
  [OK] Environment file backed up
  [OK] Routing config backed up
  [OK] Metadata written to backup-metadata.json
Backup complete: 45MB in 1.2s
```

Ensure the backup directory exists and contains data:

```
EDGE$ ls -la /opt/wheeler/backups/frontend/<service>/production/<timestamp>/
EDGE$ du -sh /opt/wheeler/backups/frontend/<service>/production/<timestamp>/
```

**Troubleshooting:** If backup fails due to disk space, free space by removing backups older than 30 days:

```
EDGE$ find /opt/wheeler/backups/ -type d -mtime +30 -exec rm -rf {} \;
```

---

#### Step 5: Pull New Build Artifacts / Docker Image

**For static frontends (Nginx-served):**

```
EDGE$ cd /opt/wheeler/services/<service>/production
EDGE$ /opt/wheeler/scripts/deploy-service.sh pull <service> production
```

This fetches the build tarball from the artifact store (MinIO, S3, or GitHub Releases), extracts it into the target directory, and updates the version symlink.

**Expected output:**

```
Pulling build artifact: wheeler-apps/<service>/releases/v4.0.2.tar.gz
  Download: [####################] 100%  (12.3 MB in 3.1s)
  Extract: /opt/wheeler/services/<service>/releases/v4.0.2/
  Symlink: production -> releases/v4.0.2/
Artifact deployed: version v4.0.2
```

**For Docker-based frontends (Traefik-routed containers):**

```
EDGE$ cd /opt/wheeler/compose/<service>/
EDGE$ docker compose pull <service>
EDGE$ docker compose up -d --no-deps <service>
```

**Expected output:**

```
[+] Pulling 2/2
  <service> Pulled
  <service> sha256:abc123... Done
[+] Running 2/2
  Container <service>-1  Started
```

Verify the new container is running:

```
EDGE$ docker ps --filter "name=<service>" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
```

---

#### Step 6: Update Nginx/Traefik Config If Route Changed

**Check if config update is needed:**

```
EDGE$ diff /opt/wheeler/services/<service>/production/routing.yaml /opt/wheeler/routing/<service>.yaml
```

If the routing config has changed (new routes, updated middleware, different backends), apply it:

**For Traefik:**

```
EDGE$ cp /opt/wheeler/services/<service>/production/routing.yaml /opt/wheeler/routing/<service>.yaml
```

**For Nginx:**

```
EDGE$ cp /opt/wheeler/services/<service>/production/nginx-site.conf /etc/nginx/sites-available/<service>.conf
```

If no routes changed, skip to Step 7.

---

#### Step 7: Reload Routing

**For Nginx:**

```
EDGE$ nginx -t
EDGE$ nginx -s reload
```

**Expected output:**

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**For Traefik (file provider):**

```
EDGE$ traefik config validate --configfile=/etc/traefik/traefik.yaml
```

**Expected output:** `Configuration OK`

Traefik auto-reloads file providers; no explicit reload command is needed if the provider is configured with `watch: true`. If using a Docker provider with labels, verify labels are applied:

```
EDGE$ docker inspect <container-name> | jq '.[0].Config.Labels'
```

**Troubleshooting:**

- **nginx -t fails:** Check the error line number. Common causes: missing semicolon, duplicate server_name, include path not found.
- **Traefik validation fails:** Check the YAML indentation. Traefik is strict about indentation levels.
- **Nginx reload hangs:** Check if any worker is stuck: `ps aux | grep nginx`. Force kill stuck worker: `kill -9 <pid>` then reload.

---

#### Step 8: Run Post-Deploy Health Check

```
EDGE$ /opt/wheeler/scripts/post-deploy-healthcheck.sh frontend <service-name> production
```

This script:

- Curls the local health endpoint (if the service exposes one)
- Verifies the HTTP status code is 2xx
- Checks that the response body contains expected fields
- Validates SSL certificate chain on the public endpoint
- Checks that static assets are being served (for Nginx-served frontends)

**Expected output:**

```
PASS  [1/5] Local health endpoint: HTTP 200
PASS  [2/5] Health response valid: {"status":"ok","version":"v4.0.2"}
PASS  [3/5] Public URL accessible: https://<domain>.app -> HTTP 200
PASS  [4/5] SSL certificate valid: CN=<domain>.app, Expiry=2026-08-15
PASS  [5/5] Static assets served: /_next/static -> 200
ALL HEALTH CHECKS PASSED
```

If health check fails:

1. Check the service logs immediately: `docker logs <container> --tail 50` or `tail -f /var/log/nginx/<service>.error.log`
2. Verify the service is actually running: `docker ps | grep <service>` or `systemctl status nginx`
3. If the issue is environmental (wrong env vars), restore the old .env from backup
4. If the issue persists beyond 2 minutes, execute the rollback steps below

---

#### Step 9: Smoke Test Public URLs

Run a series of curl commands from both local and external perspectives:

```
# Local smoke tests
EDGE$ curl -s -o /dev/null -w "%{http_code}" http://localhost:<port>/

# Public URL smoke tests (from EDGE)
EDGE$ curl -s -o /dev/null -w "%{http_code}" https://<domain>/
EDGE$ curl -s -o /dev/null -w "%{http_code}" https://<domain>/api/health
EDGE$ curl -s https://<domain>/ | grep -o '<expected-content-marker>' | head -1
```

**From AIOPS (verifying cross-node connectivity):**

```
$ curl -s -o /dev/null -w "%{http_code}" https://<domain>/
```

**Expected output:** All curls return HTTP 200. The grep finds the expected content marker.

**Common smoke test checks by service:**

| Service | URL | Expected Content Check |
|---------|-----|----------------------|
| FRGCRM Frontend | `https://frgops.fundsrecoverygroup.tech/` | `<div id="root">` exists |
| Wheeler Hub | `https://wheeler.frgop.io/` | `<title>Wheeler</title>` exists |
| Chatwoot | `https://chatwoot.wheeler.ai/` | Login page renders |
| n8n | `https://n8n.wheeler.ai/` | n8n UI loads |
| Grafana | `https://grafana.wheeler.ai/` | Grafana login renders |
| SurplusAI Frontend | `https://surplusai.app/` | Main page renders |
| Uptime Kuma | `https://uptime.wheeler.ai/` | Dashboard loads |

If any smoke test fails, check the service logs. If the issue is not immediately diagnosable (within 2 minutes), roll back.

---

#### Step 10: Verify SSL

```
EDGE$ openssl s_client -connect <domain>:443 -servername <domain> </dev/null 2>/dev/null | openssl x509 -noout -dates -subject -issuer
```

**Expected output:**

```
subject=CN = <domain>.app
issuer=C = US, O = Let's Encrypt, CN = R11
notBefore=May 20 00:00:00 2026 GMT
notAfter=Aug 18 23:59:59 2026 GMT
```

Verify:

- The certificate is NOT expired (notAfter is in the future)
- The CN or SAN matches the domain
- The issuer is expected (Let's Encrypt for most Wheeler services)
- The certificate is valid for at least 30 more days

Also verify HTTPS headers:

```
EDGE$ curl -sI https://<domain>/ | grep -iE 'strict-transport-security|x-frame|x-content|content-security'
```

**Expected output:**

```
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-frame-options: DENY
x-content-type-options: nosniff
```

**Troubleshooting:** If SSL fails:

- Certificate not found: Run certbot renewal check: `certbot renew --dry-run`
- Certificate expired: `certbot renew --force-renewal`
- Certificate for wrong domain: Verify the Traefik/Nginx config references the correct certificate path

---

#### Step 11: Monitor Logs for 5 Minutes

```
# Nginx logs
EDGE$ tail -f /var/log/nginx/<service>.access.log /var/log/nginx/<service>.error.log

# Traefik logs (Docker)
EDGE$ docker logs -f traefik --tail 20

# Application logs (if Docker-based)
EDGE$ docker logs -f <container-name> --tail 20
```

During the 5-minute window, watch for:

- **ERROR or FATAL log entries** (any occurrence = stop and investigate)
- **HTTP 5xx status codes** in access logs (more than 5 in 5 minutes = investigate)
- **Connection refused or timeout** in error logs
- **Rate of 4xx errors** (a small increase is normal; a sudden spike may indicate a config issue)
- **Memory or CPU warnings** in Traefik/Nginx logs
- **SSL handshake failures**

If during the 5-minute window you observe:

- **> 10 errors:** Execute rollback immediately
- **5-10 errors:** Pause, investigate, decide if issue is transient or persistent
- **1-4 errors:** Note in deployment log, continue monitoring
- **0 errors:** Proceed to Step 12

---

#### Step 12: Mark Deployment Complete in Deployment Log

Update the deployment log:

```
EDGE$ /opt/wheeler/scripts/deploy-log.sh record \
  --service "<service-name>" \
  --version "<version>" \
  --type "frontend" \
  --server "EDGE" \
  --operator "$(whoami)" \
  --status "success"
```

**Expected output:**

```
Deployment recorded: #1842 -- <service> v<version> on EDGE by <operator> at <timestamp>
```

Post to #deployments channel:

```
Deployment complete:
  Service: <service-name> (Frontend)
  Version: v4.0.1 -> v4.0.2
  Server: EDGE (187.77.148.88)
  Duration: 14m 32s
  Status: HEALTHY
  Smoke tests: PASSED (6/6)
  SSL: VALID
```

---

### Rollback Steps

Execute these steps in order. Each step should complete in under 1 minute.

**Step R1: Stop traffic to new version**

```
# For Nginx:
EDGE$ cp /opt/wheeler/backups/frontend/<service>/production/<timestamp>/nginx-site.conf /etc/nginx/sites-available/<service>.conf
EDGE$ nginx -t && nginx -s reload

# For Traefik/Docker:
EDGE$ docker compose -f /opt/wheeler/compose/<service>/docker-compose.yml stop <service>
```

**Step R2: Restore previous version**

```
EDGE$ /opt/wheeler/scripts/rollback-engine/rollback.sh frontend <service> production
```

This script:
1. Locates the most recent backup in `/opt/wheeler/backups/frontend/<service>/production/`
2. Restores the previous version to the production directory
3. Restores the previous environment file
4. Restores the previous routing config

**Step R3: Restart service with previous version**

```
# For Nginx-served static:
EDGE$ /opt/wheeler/scripts/deploy-service.sh activate <service> production <previous-version>

# For Docker:
EDGE$ cd /opt/wheeler/compose/<service>/
EDGE$ docker compose up -d <service>
```

**Step R4: Verify rollback**

```
EDGE$ /opt/wheeler/scripts/verify-deployment.sh frontend <service> production
```

**Expected output:** All checks pass with the previous version.

**Step R5: Restore public traffic**

```
EDGE$ nginx -s reload  # if Nginx
# Traefik auto-detects the restored container
```

**Step R6: Verify public accessibility**

```
EDGE$ curl -s -o /dev/null -w "%{http_code}" https://<domain>/
```

**Expected output:** `200`

**Step R7: Notify team**

Post to #deployments:

```
ROLLBACK EXECUTED:
  Service: <service> (Frontend)
  Rolled from: v4.0.2 -> v4.0.1
  Reason: [describe reason]
  Duration: [rollback time]
  Status: HEALTHY (restored)
  Post-mortem ticket: [link]
```

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Nginx test fails after config change | Syntax error in config | Check exact line in error message. Common: missing `;`, duplicate server_name. |
| Traefik not routing to new container | Labels mismatch | Compare `docker inspect <container>` labels against Traefik expected labels. |
| 502 Bad Gateway after deploy | Backend container not ready | Wait 10 seconds, retry. Check container logs for startup errors. |
| SSL certificate invalid | Cert expired or wrong domain | Run `certbot renew --force-renewal` for the affected domain. |
| Frontend loads but API calls fail | CORS or API URL mismatch | Check `.env` for correct API base URL. Verify the API is reachable from EDGE. |
| Static assets 404 | Build artifact incomplete or wrong path | Verify the extracted artifact has the expected directory structure. Re-pull. |
| Docker pull fails | Registry unreachable or auth expired | `docker login` to re-authenticate. Check network connectivity to registry. |
| Port conflict during deploy | Old process still holding port | `lsof -i :<port>` to identify. Kill stale process before deploy. |
| preflight-check.sh fails with "connectivity" error | Tailscale tunnel down | `tailscale status` on EDGE. Restart tailscale if needed: `systemctl restart tailscaled`. |
| Deployment log script not found | Scripts not deployed to this server | SCP the scripts from AIOPS: `scp -r aiops:/opt/wheeler/scripts/ edge:/opt/wheeler/scripts/`. |
| Build tarball checksum mismatch | Network corruption during transfer | Re-download the artifact. Verify checksum against the build pipeline output. |

---

## Playbook 2: API Deploy

### Pre-conditions

- [ ] All tests passing in CI for the target commit SHA
- [ ] You have SSH access to the AIOPS node (5.78.140.118)
- [ ] You have sudo access on AIOPS
- [ ] The API service has a valid `.env` file at `/opt/wheeler/env/{service}/production/.env`
- [ ] preflight-check.sh, pre-deploy-backup.sh, deploy-pm2-service.sh exist on AIOPS
- [ ] PM2 is running and the current service process is healthy (or stopped intentionally)
- [ ] DB migration status is known (check before deploying)
- [ ] #deployments channel has been notified with planned deployment window
- [ ] No active P0/P1 incident on the API service

### Duration Estimate

| Phase | Time |
|-------|------|
| Pre-flight + backup | 2-4 minutes |
| DB migration pre-check | 1-2 minutes (more if migrations need to run first) |
| PM2 deploy | 1-3 minutes |
| Health check | 1-2 minutes |
| Smoke tests | 2-3 minutes |
| Monitoring period | 5 minutes |
| **Total (no migration)** | **~12 minutes** |
| **Total (with migration)** | **~25-40 minutes** (includes Playbook 4) |

### Who Can Execute

- Release Engineer (primary)
- On-Call SRE (authorized)
- Senior Developer (with Release Engineer approval)

---

### Step-by-Step Instructions

#### Step 1: Verify All Tests Pass in CI

```
$ gh run list --repo wheeler-org/<service> --branch main --limit 5 --json status,headSha,conclusion,displayTitle
```

Verify:

- The target commit SHA has a green CI run
- All test suites passed (unit, integration, any API contract tests)
- No skipped tests (check CI logs for "pending" or "skipped" annotations)
- Code coverage has not dropped below the threshold

```
$ gh run view <run-id> --log | grep -E 'Tests:|Coverage:|FAILED'
```

**Expected output:**

```
Tests: 247 passed, 0 failed, 0 skipped
Coverage: 87.3% (threshold: 80%)
```

---

#### Step 2: SSH to AIOPS Node

```
$ ssh -i ~/.ssh/wheeler_deploy deployer@5.78.140.118
```

Verify:

```
AIOPS$ hostname
AIOPS$ uptime
AIOPS$ pm2 status
```

**Expected output:** PM2 status shows all expected processes, with the target service in `online` status.

---

#### Step 3: Notify Team in #deployments Channel

Post a deployment start notification:

```
API Deploy Starting:
  Service: <service-name> (API)
  Version: v3.2.1 -> v3.2.2
  Server: AIOPS (5.78.140.118)
  Operator: <your-name>
  Estimated duration: ~15 minutes
  Has migrations: [YES/NO]
  Rollback ready: YES
```

---

#### Step 4: Run Preflight Check for API Service

```
AIOPS$ /opt/wheeler/scripts/preflight-check.sh api <service-name> production
```

This verifies:

- PM2 is running and responsive: `pm2 ping`
- Target service process exists in PM2 ecosystem: `pm2 list | grep <service>`
- Environment file passes validation
- Database connectivity (check DB host and port are reachable)
- Redis connectivity (if applicable)
- Port is available (or currently occupied by the expected process)
- Disk space >= 20%
- System load below threshold
- Node.js / Python version matches service requirements

**Expected output:**

```
PASS  [1/9] PM2 daemon: running (pid 2841)
PASS  [2/9] Service registered: <service> found in PM2 ecosystem
PASS  [3/9] Environment validation: all required vars present
PASS  [4/9] Database connectivity: COREDB:5432 reachable
PASS  [5/9] Redis connectivity: COREDB:6379 reachable
PASS  [6/9] Port check: port <port> in use by expected PID
PASS  [7/9] Disk space: 38% free on /
PASS  [8/9] System load: 2.1 (below threshold 8.0)
PASS  [9/9] Runtime check: Node.js v20.11.0 matches service requirements
ALL CHECKS PASSED -- ready to deploy
```

---

#### Step 5: Run Pre-Deploy Backup (with DB if Migrations Pending)

```
AIOPS$ /opt/wheeler/scripts/pre-deploy-backup.sh api <service-name> production --with-db
```

The `--with-db` flag triggers a database snapshot if migrations are pending. If no migrations are pending, omit `--with-db` (it will take extra time unnecessarily).

**Expected output:**

```
Backup started at 2026-05-23T14:15:00Z
  [OK] Service directory backed up: /opt/wheeler/backups/api/<service>/production/20260523-141500/
  [OK] PM2 ecosystem state captured: pm2 save executed
  [OK] Environment file backed up
  [OK] Code snapshot preserved
  [OK] DB snapshot triggered (see DB backup log)
  [OK] Metadata written
Backup complete: 127MB in 4.7s
```

---

#### Step 6: Check DB Migration Status

```
AIOPS$ cd /opt/wheeler/services/<service>/production
AIOPS$ alembic current
```

**Expected output (no pending migrations):**

```
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
Current revision: a1b2c3d4e5f6 (head)
```

**Expected output (pending migrations):**

```
Current revision: a1b2c3d4e5f6
Head revision: g7h8i9j0k1l2 (head)
Pending migrations: 2
```

If migrations are pending:

1. **DO NOT deploy yet.**
2. Execute Playbook 4 (DB Migration Deploy) first.
3. Return to this playbook at Step 7 once migrations are complete.

---

#### Step 7: If Migrations -- Run DB Migration Deploy Playbook First

This is a gate, not a step. If `alembic current` showed pending migrations:
- Pause this playbook
- Execute Playbook 4: DB Migration Deploy
- Return here at Step 8 after successful migration

If no migrations pending, proceed to Step 8.

---

#### Step 8: Run Deploy via PM2

```
AIOPS$ /opt/wheeler/scripts/deploy-pm2-service.sh <service-name> production
```

This script:

1. Pulls the latest code from the artifact repository or git
2. Installs/updates dependencies: `npm ci --production` or `pip install -r requirements.txt`
3. Builds if needed (TypeScript compilation, etc.)
4. Runs any post-install setup
5. Reloads the PM2 process: `pm2 reload <service-name> --update-env`
6. Waits for the process to report `online`
7. Verifies the process is listening on the expected port

**Expected output:**

```
Deploying <service-name> to production via PM2...
  [1/6] Fetching artifact: v3.2.2
  [2/6] Installing dependencies: npm ci --production (487 packages in 8.2s)
  [3/6] Build: npm run build (completed in 12.4s)
  [4/6] Reloading PM2: pm2 reload <service-name> --update-env
  [5/6] Waiting for process to come online...
  [6/6] Process confirmed online: pid 15234, uptime 2s
  Port check: process listening on :3001
Deploy complete: <service-name> v3.2.2 running
```

Verify PM2 status:

```
AIOPS$ pm2 show <service-name>
```

**Expected output:**

```
 Describing process with id <id> - name <service-name>
 +-------------------+------------------------------------+
 | status            | online                             |
 | restarts          | 0                                  |
 | uptime            | 0m 45s                             |
 | memory            | 124.3 MB                           |
 | port              | 3001                               |
 | version           | 3.2.2                              |
 +-------------------+------------------------------------+
```

**Troubleshooting:**

| Issue | Action |
|-------|--------|
| PM2 reload hangs | Kill the reload: `pm2 reset <service-name>`. Restart manually: `pm2 restart <service-name>`. |
| Process comes online then crashes | Check error logs: `pm2 logs <service-name> --lines 50`. Common: missing env var, DB connection refused. |
| Port not listening | The process may be binding to a different interface (e.g., IPv6 vs IPv4). Check `netstat -tlnp | grep <pid>`. |
| npm ci fails | Check for network issues: `curl -I https://registry.npmjs.org/`. Clear npm cache: `npm cache clean --force`. |

---

#### Step 9: Verify Health Endpoint

```
AIOPS$ curl -s http://localhost:3001/health | jq .
```

**Expected output:**

```json
{
  "status": "ok",
  "version": "3.2.2",
  "uptime": 45.2,
  "checks": {
    "database": "connected",
    "redis": "connected",
    "migrations": "up_to_date"
  },
  "timestamp": "2026-05-23T14:16:30Z"
}
```

Key validations:

- `status` is `"ok"` (not `"degraded"` or `"error"`)
- `version` matches the expected deployment version
- All `checks` report healthy status
- `uptime` is increasing (wait 5 seconds, curl again)
- Response time is under 500ms

If any check reports unhealthy (e.g., `"database": "disconnected"`):

1. Do NOT proceed to smoke tests.
2. Check connectivity: `nc -zv 5.78.210.123 5432`
3. Check DB credentials in `.env`
4. If DB is actually down, this is a COREDB incident -- escalate

---

#### Step 10: Run Smoke Tests Against API Endpoints

Run a series of test curls against critical API paths:

```bash
# Health endpoint (already tested, re-check)
AIOPS$ curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/health

# Core read endpoint (no side effects)
AIOPS$ curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/v1/status

# Authentication endpoint (validate auth flow works)
AIOPS$ curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:3001/api/v1/auth/validate \
  -H "Authorization: Bearer $TEST_API_KEY"

# Rate limiting headers present
AIOPS$ curl -sI http://localhost:3001/api/v1/status | grep -i 'x-ratelimit'
```

**Expected output:** All endpoints return HTTP 2xx (or 401 for auth test without key, which is expected).

**Service-specific smoke tests:**

| Service | Critical Endpoint | Expected |
|---------|------------------|----------|
| FRGCRM API | `GET /api/v1/leads` | 200 with JSON array |
| SurplusAI API | `GET /api/v1/assets` | 200 with JSON array |
| RavynAI API | `POST /api/v1/analyze` | 200 with analysis result |
| FRGCRM Agent Svc | `GET /health` | 200 with dependency checks |
| Prediction Radar API | `GET /health` | 200 with DB/Redis checks |
| Insforge Agent Svc | `GET /health` | 200, agent status report |

For AI-dependent APIs (RavynAI, Wheeler Brain), also verify the AI model proxy is reachable:

```
AIOPS$ curl -s http://localhost:4000/health
# OR from Hostinger:
AIOPS$ curl -s http://litellm.wheeler.ai:4000/health
```

---

#### Step 11: Monitor Error Rates and Latency for 5 Minutes

**Option A: Via Grafana (preferred if available)**

Open the API service dashboard:

```
https://grafana.wheeler.ai/d/<api-service-dashboard>
```

Monitor these panels for 5 minutes:

- **Request rate (RPS):** Should match pre-deploy baseline
- **Error rate (%):** Should be 0% or same as baseline (any increase = investigate)
- **p95 latency:** Should be within 20% of baseline
- **Active connections:** Should be stable
- **Memory usage:** Should not be trending upward (sign of a leak)

**Option B: Via command line (if Grafana is unavailable)**

```
# Watch PM2 metrics
AIOPS$ watch -n 10 'pm2 show <service-name> | grep -E "memory|cpu|restarts"'

# Watch error logs
AIOPS$ pm2 logs <service-name> --lines 0 --err

# Sample health endpoint latency
AIOPS$ for i in {1..30}; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://localhost:3001/health
  sleep 10
done
```

**Decision matrix after 5 minutes:**

| Observation | Action |
|-------------|--------|
| Zero errors, latency stable | Proceed to Step 12 |
| Few transient errors (< 5), latency spike resolved | Proceed, note in deployment log |
| Persistent elevated error rate | Investigate; consider rollback |
| Latency > 2x baseline for > 2 minutes | Investigate; likely rollback |
| Memory increasing monotonically | Rollback (memory leak) |
| Process restarted during monitoring window | Rollback immediately |

---

#### Step 12: If Healthy -- Notify Team Deployment Complete

Post to #deployments:

```
API Deploy Complete:
  Service: <service-name> (API)
  Version: v3.2.1 -> v3.2.2
  Server: AIOPS (5.78.140.118)
  Duration: 13m 45s
  Status: HEALTHY
  Health check: PASSED
  Smoke tests: PASSED (5/5)
  Error rate (5min): 0.0%
  p95 latency: 127ms (baseline: 118ms)
  DB migrations: [NONE / v014 applied successfully]
```

---

#### Step 13: If Unhealthy -- Execute Emergency Rollback

**Decision threshold: Execute rollback if ANY of the following apply:**

- Health endpoint returns non-2xx for > 30 seconds
- Error rate > 5% for > 1 minute
- p95 latency > 3x baseline for > 2 minutes
- Process has restarted more than once in 5 minutes
- A critical endpoint (health, auth, core data) is unreachable
- Database connection failures in logs

If any threshold is met, DO NOT attempt to debug in production:

```
AIOPS$ /root/rollback-engine/rollback.sh api <service-name> production
```

Follow Playbook 5: Emergency Rollback for the full procedure.

---

### Rollback Steps

**Step R1: Check PM2 previous process state**

```
AIOPS$ pm2 list
AIOPS$ ls -la /opt/wheeler/backups/api/<service>/production/
```

Identify the previous version and backup timestamp.

**Step R2: Execute rollback script**

```
AIOPS$ /root/rollback-engine/rollback.sh api <service-name> production
```

This script:
1. Identifies the most recent backup
2. Restores the code from backup
3. Updates the production symlink to the previous version
4. Reloads PM2: `pm2 reload <service-name> --update-env`
5. Verifies the process is online
6. Validates health endpoint

**Step R3: Verify rollback**

```
AIOPS$ curl -s http://localhost:3001/health | jq .
AIOPS$ /opt/wheeler/scripts/verify-deployment.sh api <service-name> production
```

**Step R4: Notify team**

Post to #deployments with rollback details (see Appendix C for template).

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| PM2 reload hangs indefinitely | Process not responding to SIGINT | `pm2 stop <service>` then `pm2 start <service>`. |
| Process starts but immediately crashes | Missing environment variable or corrupted .env | Check PM2 error logs. Compare .env against .env.example. |
| Health check returns 503 | Database or Redis unreachable | Check network: `nc -zv 5.78.210.123 5432`. Check credentials. |
| npm ci fails with EACCES | Permission issue on node_modules | Clear and reinstall: `rm -rf node_modules && npm ci`. |
| Port already in use | Old process not fully stopped | `lsof -i :3001`. Kill old PID if it is a zombie. |
| alembic current errors | DB connection string wrong | Check DATABASE_URL in .env. Verify COREDB is reachable. |
| Health check slow (> 2s) | DB query timeout, connection pool exhausted | Check DB load on COREDB. Check connection pool size in service config. |
| API deploys but Traefik does not route | Service not registered in Traefik config | Check Traefik labels or file provider config. Verify EDGE can reach AIOPS on the service port. |

---

## Playbook 3: AI Worker Deploy

### Pre-conditions

- [ ] Model APIs are reachable and responsive (DeepSeek, OpenRouter, Anthropic)
- [ ] You have SSH access to the AIOPS node (5.78.140.118)
- [ ] You have sudo access on AIOPS
- [ ] The AI worker service has valid env vars including all model API keys
- [ ] LiteLLM Proxy is running and healthy on its host (Hostinger EDGE or AIOPS)
- [ ] preflight-check.sh, pre-deploy-backup.sh, deploy-pm2-service.sh exist on AIOPS
- [ ] PM2 is running and the current AI worker process is healthy or stopped intentionally
- [ ] Circuit breaker configuration is verified (DeepSeek -> OpenRouter failover path)
- [ ] #deployments channel has been notified

### Duration Estimate

| Phase | Time |
|-------|------|
| Pre-flight + backup | 2-4 minutes |
| Model API reachability check | 1-2 minutes |
| PM2 deploy | 1-3 minutes |
| Health check + inference test | 2-3 minutes |
| Streaming test | 1 minute |
| Monitoring period | 5 minutes |
| **Total** | **~15 minutes** |

### Who Can Execute

- Release Engineer (primary)
- On-Call SRE (authorized)
- AI/ML Engineer with deployment training

---

### Step-by-Step Instructions

#### Step 1: Verify Model APIs Are Reachable

AI worker deployments have an additional pre-condition: the upstream model APIs must be healthy. A working AI worker deployed against a degraded model API is a broken AI worker.

```
AIOPS$ /opt/wheeler/scripts/check-model-apis.sh
```

This script tests connectivity to all configured model providers:

```
Testing model API connectivity:
  [1/4] DeepSeek API (api.deepseek.com): 200 OK (82ms)
  [2/4] OpenRouter API (openrouter.ai): 200 OK (145ms)
  [3/4] Anthropic API (api.anthropic.com): 200 OK (210ms)
  [4/4] OpenAI API (api.openai.com): 200 OK (195ms)
All model APIs reachable
```

If any model API is unreachable:

- **Do not block the deploy** if it is not the primary model for this worker.
- **Block the deploy** if it is the primary model AND the failover path is also broken.
- Check model provider status pages: status.deepseek.com, status.openai.com, status.anthropic.com
- If the primary model is degraded, verify the circuit breaker will route to the failover model before proceeding.

---

#### Step 2: SSH to AIOPS Node

```
$ ssh -i ~/.ssh/wheeler_deploy deployer@5.78.140.118
AIOPS$ hostname && uptime
```

---

#### Step 3: Run Preflight Check for AI Worker

```
AIOPS$ /opt/wheeler/scripts/preflight-check.sh ai-worker <service-name> production
```

In addition to standard PM2 checks, this preflight validates:

- All model API keys are present and non-empty
- Circuit breaker library is installed (opossum or equivalent)
- Fallback model is configured (if using DeepSeek, verify OpenRouter key exists)
- Token budget limits are configured
- LiteLLM proxy is reachable
- Streaming response buffer is configured

**Expected output:**

```
PASS  [1/10] PM2 daemon: running (pid 2841)
PASS  [2/10] Service registered: <service> found in PM2 ecosystem
PASS  [3/10] Environment: all required vars present
PASS  [4/10] Model API keys: DeepSeek, OpenRouter, Anthropic configured
PASS  [5/10] Circuit breaker: opossum v8.1.3 installed
PASS  [6/10] Fallback path: DeepSeek -> OpenRouter configured
PASS  [7/10] Token budget: daily limit 1M tokens, current usage 234K (23%)
PASS  [8/10] LiteLLM proxy: http://litellm.wheeler.ai:4000/health -> 200
PASS  [9/10] Streaming config: buffer size 4096, timeout 30s
PASS  [10/10] Disk space: 45% free on /
ALL CHECKS PASSED -- ready to deploy
```

---

#### Step 4: Run Pre-Deploy Backup

```
AIOPS$ /opt/wheeler/scripts/pre-deploy-backup.sh ai-worker <service-name> production
```

**Expected output:**

```
Backup started at 2026-05-23T14:30:00Z
  [OK] AI worker code backed up: /opt/wheeler/backups/ai-worker/<service>/production/20260523-143000/
  [OK] PM2 ecosystem state captured
  [OK] Environment file backed up
  [OK] Model configuration preserved
  [OK] Circuit breaker state captured
  [OK] Metadata written
Backup complete: 87MB in 2.1s
```

---

#### Step 5: Test LiteLLM Health

```
AIOPS$ curl -s http://litellm.wheeler.ai:4000/health | jq .
```

**Expected output:**

```json
{
  "status": "healthy",
  "providers": {
    "deepseek": "connected",
    "openrouter": "connected",
    "anthropic": "connected",
    "openai": "connected"
  },
  "uptime_seconds": 152340,
  "requests_served": 89472
}
```

If LiteLLM is unhealthy, the AI worker will fail when it tries to route inference requests. Do not deploy if LiteLLM is down unless the worker has a direct-to-model fallback path.

---

#### Step 6: Run Deploy via PM2

```
AIOPS$ /opt/wheeler/scripts/deploy-pm2-service.sh <service-name> production
```

**Expected output:**

```
Deploying <service-name> to production via PM2...
  [1/6] Fetching artifact: v1.8.3
  [2/6] Installing dependencies: npm ci --production (523 packages in 9.1s)
  [3/6] Build: npm run build (completed in 15.2s)
  [4/6] Reloading PM2: pm2 reload <service-name> --update-env
  [5/6] Waiting for process to come online...
  [6/6] Process confirmed online: pid 16234, uptime 3s
  Port check: process listening on :4001
Deploy complete: <service-name> v1.8.3 running
```

---

#### Step 7: Verify Worker Health Endpoint

```
AIOPS$ curl -s http://localhost:4001/health | jq .
```

**Expected output:**

```json
{
  "status": "ok",
  "version": "1.8.3",
  "uptime": 12.4,
  "models": {
    "primary": "deepseek-chat",
    "fallback": "openrouter/auto",
    "status": "healthy"
  },
  "circuit_breaker": "closed",
  "token_usage_today": 234567,
  "token_limit_daily": 1000000,
  "active_requests": 0,
  "queue_depth": 0
}
```

Key validations:

- `circuit_breaker` is `"closed"` (not `"open"` or `"half-open"`)
- `models.status` is `"healthy"`
- `active_requests` and `queue_depth` are 0 or low
- `version` matches the expected deployment version

---

#### Step 8: Test Inference

Send a test prompt through the worker to verify end-to-end inference:

```
AIOPS$ curl -s -X POST http://localhost:4001/api/v1/infer \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Say hello in exactly 5 words.",
    "max_tokens": 50,
    "temperature": 0.1
  }' | jq .
```

**Expected output:**

```json
{
  "id": "cmpl-abc123def456",
  "model": "deepseek-chat",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello world, nice to meet."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 8,
    "completion_tokens": 6,
    "total_tokens": 14
  },
  "latency_ms": 420
}
```

Key validations:

- Response contains valid content (not empty, not an error message)
- `model` field shows the expected primary model
- `usage` shows reasonable token counts (not 0, not wildly off)
- `latency_ms` is under 2000ms (acceptable for AI inference)
- No error in the response

If the inference test fails:

1. Check the worker logs: `pm2 logs <service-name> --lines 20`
2. Verify the model API key is valid: test directly against the model provider
3. Check if the circuit breaker opened: look for "CIRCUIT OPEN" in logs
4. If the primary model fails but the fallback model works, the circuit breaker may have tripped. Investigate the primary model issue.

---

#### Step 9: Verify Token Usage Is Normal

```
AIOPS$ curl -s http://localhost:4001/health | jq '.token_usage_today'
```

Compare against the daily token budget. If token usage has spiked (e.g., from 234K to 500K after deploy), this could indicate:

- A loop or retry storm in the new version
- A change to the prompt template that increases token consumption
- A bug that causes repeated inference calls

If token usage is more than 2x the baseline for this time of day, investigate before proceeding.

---

#### Step 10: Verify Streaming Responses Work

Many AI features depend on streaming (SSE) responses. Verify streaming works:

```
AIOPS$ curl -s -N -X POST http://localhost:4001/api/v1/infer/stream \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Count from 1 to 5 with commas.",
    "max_tokens": 30,
    "temperature": 0.1,
    "stream": true
  }' 2>&1 | head -20
```

**Expected output:** Multiple SSE events with `data:` prefixes, each containing a token chunk. The stream should complete with `data: [DONE]`.

If streaming does not work:

- Check SSE headers: `curl -sI -X POST http://localhost:4001/api/v1/infer/stream | grep -i content-type` should show `text/event-stream`
- Check proxy configuration: if Traefik/Nginx sits between the client and worker, ensure it does not buffer streaming responses
- Traefik requires `buffering.maxResponseBodyBytes=0` to disable buffering

---

#### Step 11: Monitor Worker Logs for 5 Minutes

```
AIOPS$ pm2 logs <service-name> --lines 0
```

During the 5-minute window, watch for:

- **Circuit breaker events:** "CIRCUIT OPEN", "CIRCUIT HALF-OPEN", "CIRCUIT CLOSED"
- **Model API errors:** 429 (rate limit), 503 (model overloaded), 401 (invalid key)
- **Token budget warnings:** approaching daily limit
- **Timeout errors:** requests exceeding configured timeout
- **Stream disconnections:** client disconnects during streaming
- **Memory warnings:** heap usage approaching limits

**Circuit breaker special monitoring:**

The AI worker is the only service type where the circuit breaker can open automatically. If you see "CIRCUIT OPEN" in the logs during the monitoring window:

1. **IMMEDIATELY check if the new version caused it:**
   - Did the new version change the prompt template? (may cause different error responses from model)
   - Did the new version change the timeout? (shorter timeout may trigger false circuit opens)
   - Did the new version change the error threshold? (more sensitive breaker)
2. **If the circuit breaker opened due to a model API issue** (not a code issue): Allow it to test half-open as designed.
3. **If the circuit breaker opened due to a code change:** Execute rollback immediately.

---

#### Step 12: Decision Gate

| Condition | Action |
|-----------|--------|
| All checks passed, circuit breaker closed | Mark deployment complete. Notify team. |
| All checks passed, circuit breaker half-open | Note in deployment log. Continue monitoring for 10 more minutes. |
| Circuit breaker open (model issue) | Allow breaker to cycle. Notify team of degraded model status. |
| Circuit breaker open (code issue) | **Rollback immediately.** |
| Inference test failed | Rollback immediately. |
| Streaming test failed | Assess impact (non-streaming endpoints may suffice). Rollback if critical. |

---

### Rollback Steps

AI worker rollback follows the same pattern as API deploy rollback (Playbook 2), with these additions:

**Step R1: Preserve circuit breaker state**

```
AIOPS$ cp /opt/wheeler/services/<service>/production/circuit-state.json /tmp/circuit-state-rollback-$(date +%Y%m%d-%H%M%S).json
```

**Step R2: Execute rollback**

```
AIOPS$ /root/rollback-engine/rollback.sh ai-worker <service-name> production
```

**Step R3: Verify inference works after rollback**

```
AIOPS$ curl -s -X POST http://localhost:4001/api/v1/infer \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Ping.", "max_tokens": 10}' | jq '.choices[0].message.content'
```

**Expected output:** Non-empty, non-error response.

**Step R4: Verify circuit breaker state is closed**

```
AIOPS$ curl -s http://localhost:4001/health | jq '.circuit_breaker'
```

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Circuit breaker opens immediately after deploy | Error threshold too low, or new code generates more errors | Check error rate. If code is correct, adjust breaker threshold. If code has bugs, rollback. |
| Inference returns empty response | Prompt template changed or model API returns 204 | Check raw model API response. Compare prompt template between old and new version. |
| Token usage spikes after deploy | Prompt template now longer, or retry logic changed | Compare prompt length. Check for infinite retries in new code. |
| Streaming broken after deploy | SSE headers stripped by middleware | Check if new version changed response headers. Verify no buffering middleware. |
| Model API returns 429 (rate limit) | Token budget exhausted or rate limit changed | Check daily usage. Pause if approaching limit. Contact model provider if limit unexpectedly low. |
| DeepSeek down but failover does not trigger | Circuit breaker config not applied in new version | Check env vars for failover config. Verify opossum/circuit-breaker is imported and configured. |
| Worker reports "unknown model" | New version references model name that does not exist in LiteLLM | Verify model name in LiteLLM config. Rollback if model not available. |

---

## Playbook 4: DB Migration Deploy

### Pre-conditions

- [ ] Migration scripts have been reviewed and approved by a second engineer
- [ ] Migration has been tested on staging database with production-like data volume
- [ ] You have SSH access to AIOPS AND COREDB nodes
- [ ] You have database superuser or migration-user credentials
- [ ] You know whether the migration is blocking (requires downtime) or non-blocking (online)
- [ ] Maintenance window has been announced to all stakeholders (minimum 1 hour notice)
- [ ] Complete database backup has been taken and verified within the last 24 hours
- [ ] Off-server backup copy location is confirmed and writable
- [ ] Rollback plan is documented (forward-only for schema changes OR alembic downgrade tested on staging)

### Duration Estimate

| Phase | Time |
|-------|------|
| Announce + maintenance mode enable | 2-3 minutes |
| FULL database backup (pg_dump all) | 5-30 minutes (depends on DB size) |
| Copy backup off-server | 2-10 minutes (depends on network speed) |
| Staging migration test | 5-10 minutes |
| Production backup snapshot | 2-3 minutes |
| Migration execution | 1-10 minutes (depends on migration complexity) |
| Schema validation | 2-3 minutes |
| Application health checks | 2-3 minutes |
| Data integrity verification | 3-5 minutes |
| Maintenance mode disable + announce | 2 minutes |
| **Total** | **30-80 minutes** |

### Who Can Execute

- Release Engineer (primary)
- DBA / Data Engineer (required for complex migrations)
- On-Call SRE (for emergency migrations only)

---

### Step-by-Step Instructions

#### Step 1: Announce Migration Window to Team

Post to #deployments and #engineering channels:

```
DB MIGRATION WINDOW STARTING:
  Database: <database-name> (COREDB)
  Migration: <migration-id> -- <brief description>
  Type: [BLOCKING (requires ~X minutes downtime) / NON-BLOCKING (online migration)]
  Risk: [LOW / MEDIUM / HIGH]
  Estimated duration: <duration>
  Operator: <your-name>
  Backup verified: YES (taken at <timestamp>)
  Rollback tested on staging: [YES / NO]
  Maintenance mode: [WILL BE ENABLED / NOT REQUIRED]

Services affected: <list services that depend on this database>
Expected timing: Start <start-time> UTC, End <end-time> UTC
```

---

#### Step 2: Enable Maintenance Mode (If Migration Is Blocking)

Only enable maintenance mode if the migration requires exclusive locks or will cause queries to fail during execution. Non-blocking migrations (adding nullable columns, creating indexes concurrently, etc.) do not require maintenance mode.

**If maintenance mode IS required:**

```
AIOPS$ /opt/wheeler/scripts/maintenance-mode.sh enable --scope <scope> --reason "DB migration <migration-id>" --eta "30 minutes"
```

This script:
1. Sets a maintenance flag in Redis (which all services check via middleware)
2. Updates Traefik to serve a maintenance page for affected routes
3. Notifies Uptime Kuma to suppress alerts for affected services
4. Posts to #deployments confirming maintenance mode active

**Expected output:**

```
Maintenance mode ENABLED:
  Scope: api-gateway, frgcrm-api, surplusai-api
  Reason: DB migration 014_add_vector_index.sql
  ETA: 30 minutes
  Services in maintenance: 3
  Uptime Kuma: alerts suppressed for 30 min
```

**If maintenance mode is NOT required:**

Skip to Step 3. Ensure monitoring dashboards are being watched during the migration for unexpected query failures.

---

#### Step 3: FULL Database Backup (pg_dump All Databases)

From COREDB:

```
COREDB$ pg_dumpall -U postgres -h localhost \
  --clean --if-exists \
  --file=/var/backups/wheeler-full-$(date +%Y%m%d-%H%M%S).sql \
  --verbose
```

**Expected output:**

```
pg_dumpall: dumping database "postgres"...
pg_dumpall: dumping database "frgops-standby"...
pg_dumpall: dumping database "prediction-radar-app-db"...
pg_dumpall: dumping database "aiops-ravynai-postgres"...
pg_dumpall: dumping roles...
pg_dumpall: dumping tablespaces...
pg_dumpall: complete
```

Verify the backup file:

```
COREDB$ ls -lh /var/backups/wheeler-full-*.sql
COREDB$ head -5 /var/backups/wheeler-full-*.sql
```

**Expected output:** The backup file exists, is non-empty (> 1MB), and has valid SQL content.

Also take a targeted backup of only the database being migrated:

```
COREDB$ pg_dump -U postgres -h localhost \
  --dbname=<target-database> \
  --clean --if-exists \
  --file=/var/backups/<database>-pre-migration-$(date +%Y%m%d-%H%M%S).sql \
  --verbose
```

---

#### Step 4: Copy Backup to Off-Server Location

Copy the backup to at least one other location. Preferred destinations (in order):

1. AIOPS: `scp` to `/opt/wheeler/backups/db/`
2. MinIO on COREDB: `mc cp` to a backup bucket
3. Local workstation: `scp` to your machine

```
# Copy to AIOPS
COREDB$ scp /var/backups/wheeler-full-20260523-143000.sql deployer@5.78.140.118:/opt/wheeler/backups/db/

# Copy to MinIO
COREDB$ mc cp /var/backups/wheeler-full-20260523-143000.sql minio/backups/db/

# Verify copy by comparing checksums
COREDB$ md5sum /var/backups/wheeler-full-20260523-143000.sql
AIOPS$ md5sum /opt/wheeler/backups/db/wheeler-full-20260523-143000.sql
```

Both checksums must match.

---

#### Step 5: Run Migration Against Staging Database First

If a staging database exists, run the migration there first as a final validation:

```
AIOPS$ cd /opt/wheeler/services/<service>/staging
AIOPS$ alembic upgrade head
```

Monitor for:

- Any warnings or errors in the migration output
- Unexpectedly long execution time (which would indicate a problem on production-scale data)
- Schema changes that are different from expected

**Expected output:**

```
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade a1b2c3d4e5f6 -> g7h8i9j0k1l2, 014_add_vector_index.sql
INFO  [alembic.runtime.migration] Running upgrade g7h8i9j0k1l2 -> m3n4o5p6q7r8, 015_add_token_usage_table.sql
OK
```

If staging migration fails: DO NOT proceed to production. Fix the migration and re-test.

---

#### Step 6: Validate Staging Migration

```
# Check expected tables/columns exist
AIOPS$ PGPASSWORD=<staging-password> psql -h <staging-db-host> -U <user> -d <database> -c "\dt"
AIOPS$ PGPASSWORD=<staging-password> psql -h <staging-db-host> -U <user> -d <database> -c "\d <new-table>"

# Run application test suite against staging
AIOPS$ cd /opt/wheeler/services/<service>/staging
AIOPS$ npm test  # or pytest, etc.
```

All tests must pass before proceeding to production.

---

#### Step 7: Run Pre-Deploy Backup on Production (with DB)

```
AIOPS$ /opt/wheeler/scripts/pre-deploy-backup.sh db <database-name> production --with-db
```

This takes a final snapshot before migration. Even though Step 3 took a full backup, this provides a point-in-time snapshot immediately before the migration.

---

#### Step 8: Execute Migration

**For alembic-based migrations:**

```
AIOPS$ cd /opt/wheeler/services/<service>/production
AIOPS$ alembic upgrade head
```

**For manual SQL migrations:**

```
AIOPS$ PGPASSWORD=<production-password> psql \
  -h 5.78.210.123 \
  -U <migration-user> \
  -d <database> \
  -f /opt/wheeler/migrations/<database>/<migration-file>.sql \
  --echo-all
```

**If the migration is expected to take > 2 minutes:**

Run it in a screen/tmux session to avoid disconnection:

```
AIOPS$ screen -S migration-<migration-id>
AIOPS$ alembic upgrade head  # or psql command
# Ctrl+A, D to detach
# screen -r migration-<migration-id> to reattach
```

**Expected output:** The migration runs to completion with no errors. Each migration step reports `OK`.

**Critical: Watch for these danger signs during execution:**

- `ERROR:` in output = stop immediately
- Migration taking > 2x expected time = possible lock contention
- `WARNING:` about locks acquired = migration may be blocking despite expectations
- `NOTICE:` about table rewrites = expensive operation, wait for completion

---

#### Step 9: Verify Schema

```
# Verify alembic reports at head
AIOPS$ cd /opt/wheeler/services/<service>/production
AIOPS$ alembic current
# Expected: Current revision: m3n4o5p6q7r8 (head)

# Verify expected tables exist
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> -c "\dt" | grep <expected-table>

# Verify expected columns exist on new/modified tables
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> -c "\d <table-name>"

# Verify indexes were created (if applicable)
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> -c "\di" | grep <expected-index>

# Verify constraints (if applicable)
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> -c "\d <table-name>" | grep -E "Index|Check|Foreign"
```

---

#### Step 10: Run Application Health Checks

For every service that depends on the migrated database, verify its health endpoint:

```
# From AIOPS, check all dependent services
AIOPS$ for service in api-gateway frgcrm-api surplusai-api prediction-radar-api; do
  echo -n "$service: "
  curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/health
  echo
done
```

**Expected output:**

```
api-gateway: 200
frgcrm-api: 200
surplusai-api: 200
prediction-radar-api: 200
```

Also verify health endpoint responses show database dependency as healthy:

```
AIOPS$ curl -s http://localhost:3001/health | jq '.checks.database'
```

**Expected output:** `"connected"`

---

#### Step 11: Verify Data Integrity

Run data integrity checks appropriate to the migration:

```
# Row counts: compare pre and post migration
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> \
  -c "SELECT COUNT(*) FROM <critical-table>;"

# Key relationships: verify foreign key integrity
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> \
  -c "SELECT COUNT(*) FROM <child-table> c LEFT JOIN <parent-table> p ON c.parent_id = p.id WHERE p.id IS NULL;"
```

**Expected output:** Row counts match pre-migration baseline. Foreign key check returns 0 (no orphans).

**For data-mutating migrations (data backfills, column transformations):**

```
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> \
  -c "SELECT COUNT(*) FROM <table> WHERE <new-column> IS NULL AND <condition-that-should-have-been-filled>;"
```

**Expected output:** `0` (all applicable rows were updated).

---

#### Step 12: If Healthy -- Disable Maintenance Mode, Announce Complete

```
AIOPS$ /opt/wheeler/scripts/maintenance-mode.sh disable
```

**Expected output:**

```
Maintenance mode DISABLED:
  All services restored to normal operation
  Uptime Kuma: alerts re-enabled
```

Post to #deployments:

```
DB MIGRATION COMPLETE:
  Database: <database-name> (COREDB)
  Migration: <migration-id>
  Status: SUCCESS
  Duration: 42 minutes (estimate was 40 minutes)
  Downtime: [NONE / 5 minutes maintenance window]
  Schema verified: YES
  Data integrity: VERIFIED
  All dependent services: HEALTHY
  Backup: preserved at /var/backups/wheeler-full-<timestamp>.sql
```

---

#### Step 13: If Unhealthy -- Run alembic downgrade, Verify Restoration

Migration rollbacks are more dangerous than code rollbacks. **Prefer fixing forward if at all possible.**

**For alembic-based rollbacks (only if downgrade path exists and was tested):**

```
AIOPS$ cd /opt/wheeler/services/<service>/production
AIOPS$ alembic downgrade -1  # one revision back
# OR to a specific revision:
AIOPS$ alembic downgrade a1b2c3d4e5f6
```

**For manual SQL rollbacks:**

Execute the reverse SQL script (must have been created and tested before the migration):

```
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres -d <database> \
  -f /opt/wheeler/migrations/<database>/rollback-<migration-id>.sql
```

**After rollback:**

1. Verify schema returned to expected state: repeat Step 9
2. Verify application health: repeat Step 10
3. Verify data integrity: repeat Step 11
4. Verify no data loss: compare row counts to pre-migration baseline

**If rollback fails or data loss is detected:**

```
COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres \
  -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE datname = '<database>' AND pid <> pg_backend_pid();"

COREDB$ PGPASSWORD=<password> psql -h localhost -U postgres \
  -f /var/backups/<database>-pre-migration-*.sql
```

Post to #incidents:

```
DB MIGRATION ROLLED BACK:
  Database: <database-name>
  Migration: <migration-id>
  Reason: <reason>
  Rollback method: [alembic downgrade / SQL rollback script / full restore]
  Status: RESTORED
  Data loss: [NONE / <describe>]
  Next steps: Fix migration, re-test on staging, re-schedule
  Incident ticket: <link>
```

---

#### Step 14: Keep Backup for 7 Days Minimum

```
# Ensure backups are retained for minimum 7 days
COREDB$ chmod 444 /var/backups/wheeler-full-*.sql
COREDB$ chattr +i /var/backups/wheeler-full-*.sql  # make immutable (Linux)
```

Also verify the off-server copy is retained. Document backup locations in the deployment log.

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Alembic reports "Multiple head revisions" | Branch merge created competing heads | Run `alembic merge <rev1> <rev2>` to create a merge point. |
| Migration acquires ACCESS EXCLUSIVE lock and blocks queries | Migration uses `ALTER TABLE` without `CONCURRENTLY` | If non-blocking was intended, cancel and rewrite with CONCURRENTLY. If blocking, wait for it to complete. |
| pg_dump fails with "out of memory" | Database too large for memory | Use `--format=directory --jobs=4` for parallel dump. |
| Migration runs but application reports "relation does not exist" | Migration was applied to wrong database or schema | Check `search_path`. Verify you are connected to the correct database. |
| alembic current shows wrong revision after migration | alembic_version table not updated | Run `alembic stamp head` to manually set the version. |
| Data integrity check shows orphans | Migration did not handle referential integrity | Restore from backup. Fix the migration to add CASCADE or update child records. |
| Maintenance mode will not disable | Redis flag not cleared | Manually clear: `redis-cli -h 5.78.210.123 DEL maintenance_mode`. |

---

## Playbook 5: Emergency Rollback

### Pre-conditions

- [ ] A deployment has been identified as failing or causing a production incident
- [ ] You have SSH access to the affected server(s)
- [ ] You have sudo access or service-manager access (docker group, PM2 control)
- [ ] The deployment log is accessible to identify the most recent deploy
- [ ] You know which service, which server, and what version is failing

No other pre-conditions apply. In an emergency, speed matters more than completeness of information. The principle is: **Roll back first, understand later.**

### Duration Estimate

| Phase | Time |
|-------|------|
| Identify failure + determine scope | 1-2 minutes |
| Stop traffic | 30 seconds |
| Locate backup + execute rollback | 2-5 minutes |
| Verify rollback | 1-2 minutes |
| Restore traffic | 30 seconds |
| Verify public routes | 1 minute |
| Notify team | 1 minute |
| **Total** | **7-12 minutes** |

### Who Can Execute

- **Any authorized operator** (On-Call SRE, Release Engineer, Senior Developer, Tech Lead)
- In a critical production-down scenario, **authorization is retroactive** -- restore service first, get approval after.

---

### Step-by-Step Instructions

#### Step 1: Identify Failed Deployment

```
AIOPS$ /opt/wheeler/scripts/deploy-log.sh last --service <service> --limit 3
```

**Expected output:**

```
+----+---------------------+----------+----------+----------+----------+--------+
| ID | Timestamp           | Service  | Version  | Type     | Server   | Status |
+----+---------------------+----------+----------+----------+----------+--------+
| 47 | 2026-05-23 14:05 UTC| frgcrm-api| v3.2.2  | PM2      | AIOPS    | DEPLOY |
| 46 | 2026-05-23 09:15 UTC| frgcrm-api| v3.2.1  | PM2      | AIOPS    | HEALTHY|
| 45 | 2026-05-22 18:30 UTC| frgcrm-api| v3.2.0  | PM2      | AIOPS    | HEALTHY|
+----+---------------------+----------+----------+----------+----------+--------+
```

Identify the most recent deploy that is NOT in HEALTHY status. Note the version and timestamp.

---

#### Step 2: Determine Scope

Answer these questions:
1. **Which service?** (e.g., frgcrm-api)
2. **Which server?** (e.g., AIOPS 5.78.140.118)
3. **What version?** (e.g., v3.2.2, the failing version)
4. **What is the impact?** (Check dashboards, user reports, alert context)
5. **Is this isolated or cascading?** (Are other services failing because this one is down?)

Check dependent services:

```
AIOPS$ curl -s http://localhost:3001/health | jq '.checks'
AIOPS$ pm2 list | grep -E "errored|stopped|waiting"
```

Determine the scope:

| Scope | Action |
|-------|--------|
| Single service, self-contained | Roll back this service only |
| Service is a dependency for others | Roll back and verify dependents recover |
| Multiple services failed | Start with the root dependency, work outward |
| Database issue | May require full DB restore (see Playbook 4 Step 13) |
| Infra-level (server down) | Engage provider; this is beyond deployment rollback |

---

#### Step 3: Stop Traffic to Failed Service

Stop routing requests to the failing service while you prepare the rollback.

**For Traefik-routed services (EDGE):**

```
EDGE$ docker update --label-add "traefik.enable=false" <container-name>
```

**For Nginx-routed services (EDGE):**

```
EDGE$ mv /etc/nginx/sites-enabled/<service>.conf /etc/nginx/sites-available/<service>.conf.disabled
EDGE$ nginx -t && nginx -s reload
```

**For PM2 services (if directly accessed):**

```
AIOPS$ pm2 stop <service-name>
```

---

#### Step 4: Locate Most Recent Healthy Backup

```
AIOPS$ ls -lt /opt/wheeler/backups/<type>/<service>/production/
# type = frontend | api | ai-worker | db
```

**Expected output:**

```
drwxr-xr-x 5 deployer deployer 4096 May 23 14:15 20260523-141500
drwxr-xr-x 5 deployer deployer 4096 May 23 09:15 20260523-091500  <- last healthy backup
drwxr-xr-x 5 deployer deployer 4096 May 22 18:30 20260522-183000
```

Identify the most recent backup that corresponds to a KNOWN HEALTHY version. Check the backup metadata:

```
AIOPS$ cat /opt/wheeler/backups/<type>/<service>/production/20260523-091500/backup-metadata.json
```

**Expected output:**

```json
{
  "timestamp": "2026-05-23T09:15:00Z",
  "service": "frgcrm-api",
  "version": "v3.2.1",
  "type": "api",
  "server": "AIOPS",
  "status_at_backup": "healthy",
  "operator": "alice",
  "checksum": "sha256:abc123def456..."
}
```

Confirm `status_at_backup` is `"healthy"`.

---

#### Step 5: Execute Rollback

```
AIOPS$ /root/rollback-engine/rollback.sh <service-type> <service-name> production
```

Service-type is one of: `frontend`, `api`, `ai-worker`, `db`.

**Expected output:**

```
ROLLBACK ENGINE v1.0.0
================================
Target: api/frgcrm-api/production
Rolling back from: v3.2.2 (failing) -> v3.2.1 (healthy)

[1/6] Locating backup: 20260523-091500 (v3.2.1, healthy)
[2/6] Restoring code: /opt/wheeler/services/frgcrm-api/production -> v3.2.1
[3/6] Restoring environment: .env restored from backup
[4/6] Restoring configuration: PM2 ecosystem restored
[5/6] Reloading PM2: pm2 reload frgcrm-api --update-env
[6/6] Waiting for process: online (pid 18234)

Rollback complete in 47 seconds.
Health check: curl http://localhost:3001/health -> 200 OK
Version: v3.2.1 confirmed
```

**Manual rollback (if rollback.sh is unavailable):**

```
# 1. Restore code
AIOPS$ rm /opt/wheeler/services/frgcrm-api/production
AIOPS$ ln -s /opt/wheeler/backups/api/frgcrm-api/production/20260523-091500/code \
  /opt/wheeler/services/frgcrm-api/production

# 2. Restore env
AIOPS$ cp /opt/wheeler/backups/api/frgcrm-api/production/20260523-091500/.env \
  /opt/wheeler/env/frgcrm-api/production/.env

# 3. Restart PM2
AIOPS$ pm2 reload frgcrm-api --update-env
```

---

#### Step 6: Verify Rollback

```
AIOPS$ /opt/wheeler/scripts/verify-deployment.sh <service-type> <service-name> production
```

**Expected output:**

```
PASS  [1/5] Process status: online
PASS  [2/5] Health endpoint: HTTP 200
PASS  [3/5] Version check: v3.2.1 (expected v3.2.1)
PASS  [4/5] Dependency check: database connected, redis connected
PASS  [5/5] Port listening: :3001
ALL VERIFICATIONS PASSED -- rollback successful
```

---

#### Step 7: Test Service Functionality with Smoke Tests

Run the same smoke tests from the original deployment playbook. Minimum smoke test:

```
# Health endpoint
AIOPS$ curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/health

# Critical business endpoint
AIOPS$ curl -s http://localhost:3001/api/v1/<critical-endpoint> | jq '.status'
```

Both must return success.

---

#### Step 8: Restore Traffic

Reverse what you did in Step 3:

**For Traefik (EDGE):**

```
EDGE$ docker update --label-add "traefik.enable=true" <container-name>
```

**For Nginx (EDGE):**

```
EDGE$ mv /etc/nginx/sites-available/<service>.conf.disabled /etc/nginx/sites-enabled/<service>.conf
EDGE$ nginx -t && nginx -s reload
```

**For PM2 (if it was stopped):**

```
AIOPS$ pm2 start <service-name>
```

---

#### Step 9: Verify Public Routes

Verify from both inside and outside the network:

```
# From AIOPS (internal network)
AIOPS$ curl -s -o /dev/null -w "%{http_code}" https://<public-domain>/health

# From external (if you have a workstation outside the VPN)
$ curl -s -o /dev/null -w "%{http_code}" https://<public-domain>/health
```

Both must return `200`.

---

#### Step 10: Notify Team

Post to #incidents (if this was a P0/P1) or #deployments:

```
EMERGENCY ROLLBACK COMPLETE:
  Service: frgcrm-api
  Rolled from: v3.2.2 -> v3.2.1
  Reason: Health check failure 30s after deploy (database connection errors in v3.2.2)
  Duration: 8 minutes 23 seconds
  Impact window: ~10 minutes of degraded service
  Current status: HEALTHY (restored on v3.2.1)
  Smoke tests: PASSED (5/5)
  Public routes: VERIFIED

Post-mortem: [link to ticket]
Rollback log: /opt/wheeler/logs/rollbacks/frgcrm-api-20260523-142000.log
```

---

#### Step 11: Create Post-Mortem Ticket

Use the post-mortem template:

```
Title: [POST-MORTEM] Deployment rollback: <service> v<version> on <date>

What was deployed: <service> v<new-version>
What went wrong: <brief description of failure>
Why it went wrong: <root cause if known, or "under investigation">
How it was detected: <alert, health check, user report>
How it was rolled back: <method, duration>
Impact: <duration, affected users, affected features>
Timeline:
  - <time>: Deploy started
  - <time>: Failure detected
  - <time>: Rollback initiated
  - <time>: Service restored
Prevention: <what will prevent this from happening again>
Action items:
  - [ ] Investigate root cause
  - [ ] Fix the issue in development
  - [ ] Add test to catch this failure mode
  - [ ] Update playbook if needed
  - [ ] Re-deploy after fix verified on staging
```

---

#### Step 12: Preserve All Logs from Failed Deploy for Analysis

```
AIOPS$ /opt/wheeler/scripts/preserve-failed-deploy-logs.sh <service-name> v3.2.2
```

This script captures:

- PM2 logs for the failed version
- Application logs from the failure window
- Deployment log entries
- System resource metrics during the failure (CPU, memory, disk)
- Any core dumps or error snapshots

All logs are archived to: `/opt/wheeler/logs/failed-deploys/<service>-<version>-<timestamp>.tar.gz`

This archive is critical for the post-mortem analysis. Do not delete it.

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| rollback.sh not found | Scripts not deployed to this server | Use manual rollback procedure (see Step 5). |
| No backup found | Backups not configured for this service | Use git tag or Docker image history to find the previous version. |
| PM2 reload fails after rollback | Node.js/pip dependencies changed | Install dependencies from the backup: `cd <backup>/code && npm ci --production`. |
| Health check still fails after rollback | The issue is environmental, not version-specific | Check database connectivity, Redis, external APIs. The deploy may not have been the cause. |
| Public route returns 502 after restoring | Traefik/Nginx has not detected the change | Force reload routing. Wait 30 seconds and retry. |
| Multiple services affected | Root cause is in a shared dependency | Roll back the shared dependency first (e.g., LiteLLM, Traefik config, database schema). |
| Server is unreachable | Network or host issue | Use out-of-band access (Hostinger control panel, Hetzner rescue console). |

---

## Playbook 6: Hotfix Deploy

### Pre-conditions

- [ ] A critical bug or security vulnerability has been identified in production
- [ ] The fix has been developed and tested locally
- [ ] You have push access to the repository
- [ ] You have deployment access to the affected server(s)
- [ ] A code reviewer is available (for non-emergency hotfixes, this is mandatory; for true emergencies, post-deploy review is acceptable)
- [ ] The current production tag/version is known

### Duration Estimate

| Phase | Time |
|-------|------|
| Create hotfix branch + apply fix | 5-15 minutes |
| Run full test suite | 5-20 minutes |
| Code review | 10-30 minutes |
| Deploy (accelerated) | 5-15 minutes |
| Monitoring period | 15 minutes |
| Merge back to main | 2-5 minutes |
| Tag release | 2 minutes |
| **Total** | **45-90 minutes** |

### Who Can Execute

- On-Call SRE (primary for emergency hotfixes)
- Senior Developer (with Tech Lead approval)
- Release Engineer (for planned hotfixes)

---

### Step-by-Step Instructions

#### Step 1: Create Hotfix Branch from Production Tag

Identify the current production tag:

```
$ git fetch --tags
$ git tag --list 'production-*' --sort=-v:refname | head -1
```

**Expected output:** `production-v3.2.1`

Create the hotfix branch:

```
$ git checkout -b hotfix/<issue-description> production-v3.2.1
```

Example:

```
$ git checkout -b hotfix/fix-payment-webhook-timeout production-v3.2.1
```

Verify you are on the correct base:

```
$ git log --oneline -3
```

**Expected output:** The latest commit matches the production tag.

---

#### Step 2: Apply Fix and Push

Apply your fix. Keep it minimal -- a hotfix should change only what is necessary to fix the issue. If the fix is larger than ~50 lines, consider whether it should go through the normal deployment pipeline instead.

```
$ git add <changed-files>
$ git commit -m "hotfix: <concise description of fix>

Fixes: <issue or bug reference>
Tested: <how the fix was verified locally>

This is a hotfix for production issue <description>.
"
$ git push origin hotfix/<issue-description>
```

---

#### Step 3: Run FULL Test Suite (Not Just Smoke Tests)

A hotfix does NOT skip tests. Because hotfixes bypass some normal CI gates, you must manually verify the full test suite passes.

```
$ npm test -- --coverage
# OR
$ pytest --cov --cov-report=term
# OR
$ <your-test-runner> --all
```

**Expected output:** All tests pass. Coverage has not decreased.

Also run any integration tests that exercise the area affected by the hotfix:

```
$ npm run test:integration
```

If ANY test fails, fix the issue before deploying. A hotfix that breaks other things is worse than the original bug.

---

#### Step 4: Get Code Review Approval

**For planned hotfixes:** Require full code review before deployment.

```
$ gh pr create --title "hotfix: <description>" --body "## Summary
<describe the fix>

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Tested locally against production-like data
- [ ] No regression in smoke tests

## Rollback Plan
Rollback is via standard rollback for <service>.

## Deployment
After approval, deploy via hotfix pipeline.
" --base main --head hotfix/<issue-description>
```

**For emergency hotfixes (P0 production-down):** Deploy first, get review immediately after. The reviewer must be notified during the deployment.

---

#### Step 5: Deploy Using Accelerated Pipeline

Hotfix deploys follow the same steps as Playbook 1 (Frontend) or Playbook 2 (API), but with an accelerated timeline. Key differences:

- **Pre-flight:** Run preflight-check.sh but skip non-critical checks if they would add > 2 minutes
- **Backup:** pre-deploy-backup.sh is STILL MANDATORY (do not skip even for hotfixes)
- **Smoke tests:** Run the full smoke test suite
- **CI/CD:** If CI is required, use the accelerated hotfix pipeline (skips slow integration tests, runs unit tests + smoke tests only)

```
AIOPS$ /opt/wheeler/scripts/deploy-pm2-service.sh <service-name> production --hotfix
```

---

#### Step 6: Monitor CLOSELY for 15 Minutes

For a hotfix, the monitoring window is 15 minutes (3x the standard 5-minute window for routine deploys). This is because hotfixes have had less bake time and are higher risk.

**Monitor these metrics continuously:**

- Error rate (should be 0% or baseline)
- p95 latency (should match or improve baseline)
- Resource usage (CPU, memory -- should be stable)
- Business metrics (signups, payments, webhooks -- should be flowing)
- The specific bug that was fixed (verify it no longer occurs)

```
AIOPS$ pm2 logs <service-name> --lines 0
```

**Decision matrix at 15 minutes:**

| Observation | Action |
|-------------|--------|
| All clear, bug is fixed | Proceed to Step 7 |
| Bug is fixed but new minor issue found | Document the issue, proceed to Step 7, fix the new issue in a normal deploy |
| Bug is fixed but error rate elevated | Extend monitoring to 30 minutes. Investigate. |
| Bug is NOT fixed | Rollback immediately. The hotfix did not address the issue. |
| New critical issue introduced | Rollback immediately. |

---

#### Step 7: If Healthy After 15 Min -- Merge Hotfix to Main Branch

```
$ git checkout main
$ git pull origin main
$ git merge hotfix/<issue-description> --no-ff
$ git push origin main
```

The `--no-ff` flag preserves the hotfix branch history, making it clear this was a hotfix merge.

If the PR was created in Step 4:

```
$ gh pr merge <pr-number> --merge --delete-branch
```

---

#### Step 8: Tag New Production Release

```
$ git checkout main
$ git pull origin main
$ git tag -a production-v3.2.2 -m "Hotfix: <description>

Fixes production issue: <issue-reference>
Deployed: <date> by <operator>
Monitoring: Healthy after 15 minutes"
$ git push origin production-v3.2.2
```

Update the deployment log:

```
AIOPS$ /opt/wheeler/scripts/deploy-log.sh record \
  --service "<service-name>" \
  --version "v3.2.2" \
  --type "hotfix" \
  --server "AIOPS" \
  --operator "$(whoami)" \
  --status "success" \
  --hotfix true
```

---

#### Step 9: If Unhealthy -- Rollback Immediately

Follow Playbook 5: Emergency Rollback. For a hotfix, the bar for rollback is even lower than normal because the fix had less testing.

**Post-rollback action:**

```
$ git branch -D hotfix/<issue-description>  # local cleanup
$ git push origin --delete hotfix/<issue-description>  # remote cleanup
```

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Hotfix branch diverged from main | Main has been updated since the production tag | Rebase hotfix on main: `git rebase main hotfix/<issue>`. Resolve conflicts, re-run tests. |
| Hotfix introduced a regression | Fix was too broad or had unintended side effects | Rollback. Narrow the fix to the minimum change needed. |
| Test suite takes > 30 minutes to run | Large project | For true emergencies, run only the test file(s) for the affected module, but document that full tests were skipped. |
| Cannot identify production tag | Tags were not created for previous releases | Use git log to identify the last known-good commit SHA. Create a tag from that SHA before proceeding. |
| Hotfix cannot be deployed (pipeline broken) | CI/CD infrastructure issue | Deploy manually following the manual steps in the relevant playbook. |

---

## Playbook 7: Canary Release

### Pre-conditions

- [ ] The new version has passed all tests on staging
- [ ] You have deployment access to the target server(s)
- [ ] Traefik (EDGE) is configured for weighted routing, or you have an alternative traffic-splitting mechanism
- [ ] Canary configuration file exists at `/opt/wheeler/canary/<service-name>.yaml`
- [ ] Monitoring dashboards are operational and you know how to read them
- [ ] The stable version is healthy and serving production traffic
- [ ] You have at least 30 minutes of uninterrupted time (canary deployment cannot be paused mid-stream)
- [ ] A second engineer is available for the decision gates
- [ ] #deployments channel has been notified of the canary start

### Duration Estimate

| Stage | Traffic % | Duration | Cumulative |
|-------|-----------|----------|------------|
| Deploy canary instances | 0% | 5 min | 5 min |
| Stage 1: 5% traffic | 5% | 10 min | 15 min |
| Stage 2: 25% traffic | 25% | 10 min | 25 min |
| Stage 3: 50% traffic | 50% | 10 min | 35 min |
| Promotion to 100% | 100% | 2 min | 37 min |
| Old instance cleanup | 0% old | 2 min | 39 min |
| **Total** | | | **~40 minutes** |

### Who Can Execute

- Release Engineer (primary)
- On-Call SRE (with Release Engineer approval)
- Senior Developer (with Release Engineer supervision)

---

### Step-by-Step Instructions

#### Step 1: Deploy Canary Instances Alongside Stable

The canary runs as a separate set of processes/containers alongside the existing stable instances. They do not receive traffic yet.

**For PM2 services:**

```
AIOPS$ /opt/wheeler/scripts/deploy-pm2-service.sh <service-name> canary
```

This starts a separate PM2 process named `<service-name>-canary` on a different port. The stable process `<service-name>` continues running unaffected.

**Expected output:**

```
Deploying <service-name> canary instance...
  Process: <service-name>-canary (pid 19234, port 3101)
  Version: v3.3.0-canary
  Status: online
Canary deployed WITHOUT production traffic
```

**For Docker services:**

```
AIOPS$ docker compose -f /opt/wheeler/compose/<service>/docker-compose.canary.yml up -d
```

This starts a separate container with the canary image, on a different port, with the label `traefik.http.services.<service>-canary.loadbalancer.server.port=<canary-port>` but initially `traefik.enable=false` (no traffic).

Verify both stable and canary are running:

```
AIOPS$ pm2 list | grep <service>  # PM2
# OR
AIOPS$ docker ps --filter "name=<service>"  # Docker
```

**Expected output:**

```
| 3  | <service>        | online | 42h    | 0       | 3001   |
| 8  | <service>-canary | online | 15s    | 0       | 3101   |
```

---

#### Step 2: Configure Traefik Weighted Routing (5% Canary, 95% Stable)

**For Traefik file provider -- update the dynamic configuration:**

```yaml
# /opt/wheeler/routing/<service>.yaml
http:
  services:
    <service>-stable:
      loadBalancer:
        servers:
          - url: "http://5.78.140.118:3001"
    <service>-canary:
      loadBalancer:
        servers:
          - url: "http://5.78.140.118:3101"
    <service>-weighted:
      weighted:
        services:
          - name: <service>-stable
            weight: 95
          - name: <service>-canary
            weight: 5
  routers:
    <service>-router:
      rule: "Host(`<public-domain>`)"
      service: <service>-weighted
      priority: 100
```

Apply the configuration:

```
EDGE$ cp /opt/wheeler/canary/<service>-stage1.yaml /opt/wheeler/routing/<service>.yaml
# Traefik auto-reloads file provider changes
```

**Verify the weighted routing is active:**

```
EDGE$ curl -s http://localhost:8080/api/http/services | jq '.[] | select(.name | startswith("<service>")) | {name, weighted}'
```

**Expected output:**

```json
{
  "name": "<service>-weighted@file",
  "weighted": {
    "services": [
      { "name": "<service>-stable", "weight": 95 },
      { "name": "<service>-canary", "weight": 5 }
    ]
  }
}
```

---

#### Step 3: Monitor for 10 Minutes (5% Canary, 95% Stable)

**Monitoring checklist for Stage 1 (5%):**

| Metric | Source | Stable Baseline | Canary Target | Alarm Threshold |
|--------|--------|----------------|---------------|-----------------|
| Error rate (%) | Grafana / Loki | < 0.1% | < 0.1% | > 1% = ABORT |
| p95 latency (ms) | Grafana / prometheus | <baseline> | Within 20% of baseline | > 2x baseline = ABORT |
| CPU usage (%) | PM2 / Docker stats | <baseline> | Within 20% of baseline | > 90% = ABORT |
| Memory usage (MB) | PM2 / Docker stats | <baseline> | Within 20% of baseline | Monotonic increase = ABORT |
| Restarts | PM2 / Docker | 0 | 0 | > 0 = ABORT |
| Business metrics | Custom dashboard | <baseline> | Within 5% of baseline | > 10% drop = INVESTIGATE |

**Commands for manual monitoring:**

```
# Error rate (via logs)
AIOPS$ pm2 logs <service>-canary --lines 0 --err

# Latency (via health endpoint sampling)
AIOPS$ for i in {1..60}; do
  curl -s -o /dev/null -w "%{time_total}\n" http://localhost:3101/health
  sleep 10
done

# Resource usage
AIOPS$ watch -n 5 'pm2 show <service>-canary | grep -E "memory|cpu|restarts"'
```

**Decision gate at Stage 1 (10 minutes):**

| Condition | Action |
|-----------|--------|
| All metrics within thresholds | Proceed to Stage 2 (25%) |
| Minor anomaly (e.g., slightly elevated latency but below threshold) | Extend Stage 1 by 5 minutes, re-evaluate |
| Any critical threshold breached | **ABORT**: Route 100% to stable. Investigate. |
| Canary process crashed or restarted | **ABORT immediately** |

---

#### Step 4: Increase to 25% Traffic

Update Traefik configuration to 75/25 split:

```
EDGE$ cp /opt/wheeler/canary/<service>-stage2.yaml /opt/wheeler/routing/<service>.yaml
```

```yaml
# Stage 2 weights
- name: <service>-stable
  weight: 75
- name: <service>-canary
  weight: 25
```

---

#### Step 5: Monitor for 10 More Minutes (25%)

Same monitoring checklist as Stage 1, but now looking at a larger sample size.

**Additional checks at 25%:**

- **Distribution of errors:** Are errors concentrated in specific endpoints or random? Random errors suggest a runtime issue.
- **Token usage (AI services):** Is the canary using more tokens per request than stable? This could indicate a prompt template change.
- **Database query patterns:** Are canary requests generating different query patterns (check slow query log on COREDB)?
- **Cache hit rate:** Has the cache hit rate changed? New code may generate different cache keys.

**Decision gate at Stage 2 (10 minutes):**

| Condition | Action |
|-----------|--------|
| All metrics within thresholds | Proceed to Stage 3 (50%) |
| Minor anomaly, same as Stage 1 | Investigate while at 25%. Do not increase yet. |
| New anomaly not seen at 5% | **PAUSE**. The issue may be scale-dependent. Investigate. |
| Any critical threshold | **ABORT** |

---

#### Step 6: Increase to 50% Traffic

Update Traefik to 50/50 split:

```
EDGE$ cp /opt/wheeler/canary/<service>-stage3.yaml /opt/wheeler/routing/<service>.yaml
```

```yaml
# Stage 3 weights
- name: <service>-stable
  weight: 50
- name: <service>-canary
  weight: 50
```

---

#### Step 7: Monitor for 10 More Minutes (50%)

At 50%, the canary is handling a statistically significant portion of traffic. This is the final validation before full cutover.

**Additional checks at 50%:**

- **Compare canary vs stable side-by-side:** Every metric should be compared directly. The canary should perform equally or better.
- **Check for resource contention:** With two versions running simultaneously, total resource usage is higher than normal. Verify the server has sufficient headroom.
- **Verify business continuity:** Check that revenue events (signups, payments, webhooks) are flowing through both stable and canary in the expected proportions.

**Decision gate at Stage 3 (10 minutes):**

| Condition | Action |
|-----------|--------|
| All metrics within thresholds | Proceed to promotion (Stage 4: 100%) |
| Metrics acceptable but not as good as stable | Consider whether the improvement justifies the slight regression. If not, ABORT. |
| Any threshold breach | **ABORT** |

---

#### Step 8: Decision Gate -- Promote to 100% or Rollback to 0%

This is the GO / NO-GO decision. At this point, you need a second engineer to co-sign the decision.

**Promotion criteria (ALL must be true):**

- [ ] Error rate at 50% is <= stable error rate
- [ ] p95 latency at 50% is <= 1.2x stable latency
- [ ] No canary process restarts or crashes in any stage
- [ ] Memory usage stable (no growth trend) across all stages
- [ ] Business metrics show expected behavior
- [ ] Second engineer has reviewed the metrics and approves

**DO NOT promote if:**
- Any unexplained anomaly exists, even if below thresholds
- The canary version has not been fully baked (at least 30 minutes total across all stages)
- You are the only person who has reviewed the metrics

**Document the decision:**

```
CANARY DECISION LOG:
  Service: <service-name>
  Date: 2026-05-23
  Canary version: v3.3.0
  Stages completed: 5% (10 min) -> 25% (10 min) -> 50% (10 min)
  Decision: [PROMOTE / ABORT]
  Promoted by: <operator-1>, <operator-2>
  Rationale: <summary of metrics that support the decision>
  Metrics attached: <link to Grafana snapshot>
```

---

#### Step 9: If Promoting -- Traffic Shift to 100% New Version

Update Traefik to route 100% to the canary (which now becomes stable):

```
EDGE$ cp /opt/wheeler/canary/<service>-stage4.yaml /opt/wheeler/routing/<service>.yaml
```

```yaml
# Stage 4: full promotion
- name: <service>-canary
  weight: 100
- name: <service>-stable
  weight: 0
```

**Alternative: Promote the canary to stable directly (preferred for PM2):**

```
AIOPS$ pm2 stop <service>            # stop stable
AIOPS$ pm2 restart <service>-canary --name <service> --port 3001  # rename canary to stable
AIOPS$ pm2 save
```

This avoids prolonged routing complexity.

---

#### Step 10: Remove Old Stable Instances

```
# PM2
AIOPS$ pm2 delete <service>-old  # the old stable was renamed or stopped

# Docker
AIOPS$ docker compose -f /opt/wheeler/compose/<service>/docker-compose.yml down
```

Clean up canary routing configuration:

```
EDGE$ rm /opt/wheeler/routing/<service>-weighted.yaml  # if using separate weighted config
# Restore the direct router configuration
EDGE$ cp /opt/wheeler/canary/<service>-direct.yaml /opt/wheeler/routing/<service>.yaml
```

---

#### Step 11: Tag Release

```
$ git tag -a production-v3.3.0 -m "Canary release: <service> v3.3.0

Promoted via canary deployment:
  Stages: 5% -> 25% -> 50% -> 100%
  Total bake time: 35 minutes
  Canary metrics: all within thresholds
  Promoted by: <operator-1>, <operator-2>"
$ git push origin production-v3.3.0
```

---

#### Step 12: If ANY Stage Fails -- Route 100% Back to Stable, Investigate

```
EDGE$ cp /opt/wheeler/canary/<service>-abort.yaml /opt/wheeler/routing/<service>.yaml
```

```yaml
# Abort routing: 100% to stable, 0% to canary
- name: <service>-stable
  weight: 100
- name: <service>-canary
  weight: 0
```

Stop the canary instances:

```
AIOPS$ pm2 stop <service>-canary     # PM2
# OR
AIOPS$ docker compose -f /opt/wheeler/compose/<service>/docker-compose.canary.yml down  # Docker
```

Post abort notification:

```
CANARY ABORTED:
  Service: <service-name>
  Canary version: v3.3.0 (ABORTED)
  Stage at abort: [5% / 25% / 50%]
  Reason: [describe the metric that failed]
  Action: Routing restored to 100% stable (v3.2.1)
  Impact: [describe any user impact during canary]
  Next: Investigate failure, fix, re-initiate canary when ready
```

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Weighted routing not working (all traffic to stable) | Traefik config not applied or syntax error | Check Traefik dashboard. Validate YAML syntax. Check for label conflicts. |
| Canary and stable on same port conflict | Port not changed in canary config | Verify canary process uses a different port. Check PM2 ecosystem or Docker compose for port mapping. |
| Metrics dashboard does not show canary separately | Canary not labeled correctly | Add canary-specific labels to distinguish canary from stable in Prometheus/Grafana. |
| Canary error rate spike at higher traffic | Scale-dependent bug (e.g., connection pool exhaustion) | ABORT. Fix the scale-dependent issue. Consider load testing before next canary. |
| Memory grows slowly across all stages | Memory leak in new version | ABORT. A slow leak will eventually cause an outage. Fix the leak before next canary. |
| Business metrics drop at 50% | New version affects conversion or user behavior | ABORT. This may be a design issue, not a bug. Review with product team. |
| Second engineer unavailable for decision gate | Staffing gap | Extend canary at current stage until a second reviewer is available. Do NOT promote unilaterally. |

---

## Playbook 8: Failed Deploy Recovery

### Pre-conditions

- [ ] A deployment has failed OR a deployment has caused a production issue
- [ ] The failure has been detected (alert, dashboard, user report, or proactive monitoring)
- [ ] You have SSH access to the affected server(s)
- [ ] You have deployment and rollback access

This playbook is the decision framework for responding to any failed deployment. It routes to the appropriate specific playbook based on severity.

### Duration Estimate

| Severity | Time to Decision | Time to Resolution |
|----------|-----------------|-------------------|
| Critical (P0) | < 1 minute | 7-12 minutes (rollback) |
| Major (P1) | < 5 minutes | 15-60 minutes |
| Minor (P2) | No rush | Next deployment cycle |

### Who Can Execute

- Any authorized operator can triage
- Critical: any operator can rollback (authorization retroactive)
- Major: On-Call SRE or Release Engineer
- Minor: Developer with deployment access

---

### Step-by-Step Instructions

#### Step 1: Detect Failure

Failures are detected through one of these channels:

| Channel | How It Arrives | Response Time Target |
|---------|---------------|---------------------|
| Health check alert | PagerDuty / OpsGenie / Slack alert | < 2 minutes |
| Monitoring dashboard | Grafana alert or anomaly panel | < 5 minutes |
| User report | Support ticket, social media, internal report | < 10 minutes |
| Proactive (post-deploy monitoring) | Observing the 5-minute monitoring window | Immediate |

When you detect or are notified of a failure, immediately:

1. Acknowledge the alert/notification
2. Open the deployment log: `/opt/wheeler/scripts/deploy-log.sh last --limit 5`
3. Check if there was a recent deployment to the affected service
4. Check monitoring dashboards for the affected service

**Correlation check:**

```
AIOPS$ /opt/wheeler/scripts/deploy-log.sh correlate --service <service> --window 30m
```

**Expected output:**

```
Deployments in the last 30 minutes for <service>:
  14:05 UTC: frgcrm-api v3.2.2 -> v3.2.3 (operator: bob)
  13:45 UTC: nginx config update (operator: alice)

Incidents correlated with these deployments:
  14:06 UTC: Health check alert for frgcrm-api
  14:07 UTC: Spike in 500 errors (Grafana anomaly detection)

HIGH LIKELIHOOD: frgcrm-api v3.2.3 deployment caused the incident.
```

---

#### Step 2: Triage Severity

**CRITICAL (P0) -- Execute Emergency Rollback immediately:**

- [ ] Production service is completely down (health check fails, all requests error)
- [ ] Revenue-generating service is down (payments cannot be processed)
- [ ] Data loss or corruption is occurring
- [ ] Security breach is in progress
- [ ] Customer data is being exposed

**Action:** Skip to Step 3 (Critical Path).

**MAJOR (P1) -- Investigate before deciding:**

- [ ] Service is degraded but still serving (elevated error rate, increased latency)
- [ ] Non-critical feature is broken
- [ ] Background processing is stalled but user-facing features work
- [ ] Performance degradation that may escalate

**Action:** Skip to Step 4 (Major Path).

**MINOR (P2) -- Fix forward:**

- [ ] Cosmetic issue (UI glitch, wrong formatting)
- [ ] Non-critical log spam
- [ ] Minor feature regression that has a workaround
- [ ] Issue only affects internal tools

**Action:** Skip to Step 5 (Minor Path).

---

#### Step 3: Critical (P0) Recovery Path

**Step 3a: Stop the Failing Deploy Pipeline**

If a CI/CD pipeline is still running for this deployment:

```
$ gh run cancel <run-id>
```

This prevents the pipeline from making additional changes while you recover.

**Step 3b: Execute Emergency Rollback (Playbook 5)**

Immediately follow Playbook 5: Emergency Rollback. Do not pass go. Do not collect diagnostic data first (you can collect it after).

```
AIOPS$ /root/rollback-engine/rollback.sh <service-type> <service-name> production
```

**Step 3c: Verify Recovery**

```
AIOPS$ /opt/wheeler/scripts/verify-deployment.sh <service-type> <service-name> production
AIOPS$ curl -s -o /dev/null -w "%{http_code}" https://<public-domain>/health
```

Both must return success before you proceed.

**Step 3d: Communicate Status to Stakeholders**

Post to #incidents:

```
P0 INCIDENT -- ROLLBACK COMPLETE:
  Service: <service-name>
  Incident: Service down after deploy v3.2.3
  Resolution: Rolled back to v3.2.2
  Downtime: 8 minutes (14:05-14:13 UTC)
  Current status: HEALTHY
  Impact: All users affected. <N> failed requests during outage.
  
  Next steps:
  - Root cause analysis (link to ticket)
  - Fix in development
  - Post-mortem scheduled for <date>
```

---

#### Step 4: Major (P1) Recovery Path

**Step 4a: Assess the Problem**

Determine the nature of the issue:

```
# Check logs for clues
AIOPS$ pm2 logs <service> --lines 100 --err

# Check recent config changes
AIOPS$ diff /opt/wheeler/backups/<type>/<service>/production/<last-backup>/.env \
  /opt/wheeler/env/<service>/production/.env

# Check dependency health
AIOPS$ for dep in database redis litellm; do
  curl -s http://localhost:<port>/health | jq ".checks.${dep}"
done
```

Classify the issue:

**Config issue** (wrong env var, misconfigured route, invalid setting):

- Fix the config directly on production
- Redeploy with the corrected config
- The fix is typically fast (< 5 minutes)

**Code bug** (logic error, unexpected behavior, regression):

- Rollback to the previous version
- Fix the bug in development
- Re-deploy after fix is verified on staging

**Infrastructure problem** (server resource exhaustion, network issue, dependency failure):

- Do NOT rollback code (it will not fix the underlying issue)
- Engage the infrastructure/SRE team
- Consider failover if available
- Mitigate: scale up resources, restart unhealthy dependency, clear caches

**Step 4b: Decide -- Fix or Rollback?**

| Assessment | Action | Time Budget |
|------------|--------|-------------|
| Config issue, fixable in < 2 minutes | Fix config, redeploy | 5 minutes |
| Config issue, complex fix | Rollback, fix offline | N/A |
| Code bug, clear root cause | Rollback | N/A |
| Code bug, unclear root cause | Rollback, investigate | N/A |
| Infra problem, service degraded | Mitigate without rollback | 15 minutes |
| Infra problem, service failing | Rollback AND mitigate infra | N/A |

**Step 4c: Execute Decision**

Follow the appropriate path from above. If rolling back, use Playbook 5.

**Step 4d: Verify and Communicate**

Follow Steps 3c and 3d from the Critical path.

---

#### Step 5: Minor (P2) Recovery Path

**Step 5a: Document Issue**

Create a ticket with:

- What the issue is
- When it was introduced (which deployment)
- How it was detected
- Screenshots or logs if available
- Severity: Minor (P2) -- fix in next deployment cycle

**Step 5b: Decide -- Fix Now or Fix Later?**

| Consideration | Fix Now | Fix Later |
|---------------|---------|-----------|
| User impact | Users are complaining | Users may not notice |
| Regression risk | Fix is trivial and safe | Fix touches many files |
| Team availability | Developer available now | Team is busy with other priorities |
| Proximity to next deploy | Next deploy is > 3 days away | Next deploy is tomorrow |

**If fixing now:** Create a hotfix branch (but do NOT use the accelerated hotfix pipeline). Go through the normal CI/CD pipeline.

**If fixing later:** Schedule the fix for the next regular deployment cycle.

---

#### Step 6: Post-Recovery Actions

**Step 6a: Create Incident Report**

Use the post-mortem template from Playbook 5, Step 11.

**Step 6b: Update Playbooks If Needed**

If the failure revealed a gap in the playbooks (a scenario not covered, a step that was wrong, a missing troubleshooting entry), update the playbook.

**Step 6c: Schedule Follow-Up Fixes**

- The fix for the issue that caused the failure
- Any tests that would have caught the failure
- Any monitoring gaps that delayed detection

**Step 6d: Hold Blameless Post-Mortem**

Schedule within 48 hours. Invite:

- The operator who executed the deployment
- The developer who wrote the code
- The reviewer who approved the PR (if applicable)
- The SRE or Release Engineer who owns the playbook

Ground rules:
- No blame. Focus on process improvement.
- Produce actionable items with owners and deadlines.

---

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Cannot determine which deployment caused the issue | Multiple deployments in the window | Check deploy-log.sh correlate output. Roll back all correlated deploys in reverse order. |
| Rollback also fails | The backup is corrupted or the issue is environmental | Manual restore from an earlier backup. If environmental, fix the environment issue first. |
| Service recovers then fails again | Root cause not addressed by rollback | Check for external factors: database state changes, configuration changes outside the service, network issues. |
| Multiple services failing simultaneously | Infra-level issue (server overload, network partition, database down) | Do not rollback services individually. Address the root infrastructure issue. |

---

## Appendix A: Command Quick Reference

### Server Access

| Server | SSH Command | Primary User |
|--------|------------|--------------|
| EDGE | `ssh deployer@187.77.148.88` | deployer |
| AIOPS | `ssh deployer@5.78.140.118` | deployer |
| COREDB | `ssh deployer@5.78.210.123` | deployer |

### Deployment Commands

| Command | Purpose |
|---------|---------|
| `/opt/wheeler/scripts/preflight-check.sh <type> <service> production` | Pre-deploy validation |
| `/opt/wheeler/scripts/pre-deploy-backup.sh <type> <service> production [--with-db]` | Pre-deploy backup |
| `/opt/wheeler/scripts/deploy-service.sh pull <service> production` | Pull artifact (frontend) |
| `/opt/wheeler/scripts/deploy-pm2-service.sh <service> production` | Deploy PM2 service |
| `/opt/wheeler/scripts/post-deploy-healthcheck.sh <type> <service> production` | Post-deploy validation |
| `/opt/wheeler/scripts/verify-deployment.sh <type> <service> production` | Verify deployment state |
| `/root/rollback-engine/rollback.sh <type> <service> production` | Rollback service |
| `/opt/wheeler/scripts/deploy-log.sh last --limit 5` | View recent deployments |
| `/opt/wheeler/scripts/deploy-log.sh record ...` | Record deployment |
| `/opt/wheeler/scripts/maintenance-mode.sh [enable\|disable]` | Toggle maintenance mode |
| `/opt/wheeler/scripts/preserve-failed-deploy-logs.sh <service> <version>` | Archive failure logs |

### PM2 Commands

| Command | Purpose |
|---------|---------|
| `pm2 list` | List all PM2 processes |
| `pm2 show <name>` | Show process details |
| `pm2 logs <name> --lines 50` | View recent logs |
| `pm2 logs <name> --lines 0 --err` | Stream error logs |
| `pm2 reload <name> --update-env` | Zero-downtime reload |
| `pm2 restart <name>` | Hard restart |
| `pm2 stop <name>` | Stop process |
| `pm2 start <name>` | Start process |
| `pm2 delete <name>` | Remove from PM2 |
| `pm2 save` | Save current process list |
| `pm2 resurrect` | Restore saved process list |

### Docker Commands

| Command | Purpose |
|---------|---------|
| `docker ps --format "table {{.Names}}\t{{.Status}}"` | List running containers |
| `docker compose pull <service>` | Pull new image |
| `docker compose up -d <service>` | Start/recreate service |
| `docker compose down <service>` | Stop service |
| `docker logs -f <container> --tail 50` | Stream logs |
| `docker stats --no-stream` | Resource usage snapshot |

### Health Check Commands

| Command | Purpose |
|---------|---------|
| `curl -s http://localhost:<port>/health \| jq .` | Check health endpoint |
| `curl -s -o /dev/null -w "%{http_code}" https://<domain>/` | Check HTTP status |
| `openssl s_client -connect <domain>:443 -servername <domain>` | Verify SSL |
| `nc -zv <host> <port>` | Check TCP connectivity |
| `tail -f /var/log/nginx/<service>.error.log` | Watch Nginx errors |

### Database Commands

| Command | Purpose |
|---------|---------|
| `alembic current` | Check migration status |
| `alembic upgrade head` | Run all pending migrations |
| `alembic downgrade -1` | Revert last migration |
| `pg_dumpall -U postgres > backup.sql` | Full database backup |
| `psql -U postgres -c "\dt"` | List tables |
| `psql -U postgres -c "SELECT count(*) FROM <table>"` | Row count |

---

## Appendix B: Deployment Log Template

### Pre-Deploy Entry

```json
{
  "deployment_id": "auto-generated",
  "timestamp": "ISO 8601 timestamp",
  "service": "service-name",
  "version_from": "previous-version",
  "version_to": "new-version",
  "type": "frontend|api|ai-worker|db|hotfix|canary",
  "server": "EDGE|AIOPS|COREDB",
  "operator": "operator-username",
  "preflight_passed": true,
  "backup_verified": true,
  "migrations_pending": false,
  "maintenance_mode": false,
  "planned_duration_minutes": 15
}
```

### Post-Deploy Entry

```json
{
  "deployment_id": "same-as-above",
  "completed_timestamp": "ISO 8601 timestamp",
  "actual_duration_minutes": 14,
  "status": "success|failed|rolled_back",
  "health_check_passed": true,
  "smoke_tests": {
    "total": 6,
    "passed": 6,
    "failed": 0
  },
  "ssl_valid": true,
  "error_rate_5min": 0.0,
  "p95_latency_ms": 127,
  "notes": "any observations or anomalies",
  "rollback_triggered": false
}
```

---

## Appendix C: Incident Communication Templates

### Template 1: Deployment Start

```
DEPLOYMENT STARTING:
  Service: <service> (<type>)
  Version: <old> -> <new>
  Server: <server>
  Operator: <name>
  Duration: ~<estimate>
  Type: [routine|hotfix|canary|emergency]
```

### Template 2: Deployment Complete (Success)

```
DEPLOYMENT COMPLETE:
  Service: <service>
  Version: <new-version>
  Duration: <actual>
  Status: HEALTHY
  Health check: PASSED
  Smoke tests: <passed>/<total>
  Errors (5min): 0
```

### Template 3: Rollback Executed

```
ROLLBACK EXECUTED:
  Service: <service>
  From: <failed-version>
  To: <restored-version>
  Reason: <brief reason>
  Duration: <rollback time>
  Status: HEALTHY (restored)
  Post-mortem: <ticket link>
```

### Template 4: Canary Promoted

```
CANARY PROMOTED:
  Service: <service>
  Version: <new-version>
  Bake time: <total duration>
  Stages: 5% -> 25% -> 50% -> 100%
  Promoted by: <op1>, <op2>
```

### Template 5: Canary Aborted

```
CANARY ABORTED:
  Service: <service>
  Version: <version> (ABORTED)
  Stage: <stage where aborted>
  Reason: <metric that failed>
  Impact: <any user impact>
  Next: <fix plan>
```

### Template 6: DB Migration

```
DB MIGRATION [STARTING|COMPLETE|ROLLED BACK]:
  Database: <name>
  Migration: <id> -- <description>
  Status: <status>
  Duration: <time>
  Downtime: [NONE|<duration>]
```

---

## Appendix D: Troubleshooting Common Scenarios

### Scenario: SSH Connection Refused

```
ssh: connect to host 187.77.148.88 port 22: Connection refused
```

**Causes and fixes:**

1. **Server is down:** Check provider dashboard (Hostinger/Hetzner control panel). Reboot if necessary.
2. **SSH daemon crashed:** Access via provider console. Restart: `systemctl restart sshd`.
3. **Firewall blocks your IP:** Check if your IP changed. Access via provider console to update firewall.
4. **Tailscale tunnel down:** Verify: `tailscale status`. Restart: `systemctl restart tailscaled`.

### Scenario: Disk Full

```
preflight-check.sh: FAIL [6/8] Disk space: 2% free on / (threshold: 20%)
```

**Causes and fixes:**

1. **Log files accumulated:** `find /var/log -type f -name "*.log" -size +100M -exec truncate -s 0 {} \;`
2. **Docker images accumulated:** `docker system prune -a -f`
3. **Old backups not cleaned:** `find /opt/wheeler/backups -type d -mtime +30 -exec rm -rf {} \;`
4. **PM2 logs too large:** `pm2 flush`
5. **Core dumps:** `find / -name "core.*" -mtime +7 -delete`

### Scenario: PM2 Process Will Not Stay Online

```
AIOPS$ pm2 list
| 6  | frgcrm-api  | errored | 0       | 15     |
```

**Diagnostic steps:**

1. `pm2 logs frgcrm-api --lines 50 --err` -- look for the crash reason
2. `cat /opt/wheeler/env/frgcrm-api/production/.env | grep DATABASE_URL` -- check env vars
3. `nc -zv 5.78.210.123 5432` -- check database connectivity
4. `node -e "require('./app.js')"` -- try running the app directly to see the error
5. Check for port conflicts: `lsof -i :8013`
6. Check for missing dependencies: `cd /opt/wheeler/services/frgcrm-api/production && npm ls`

### Scenario: Docker Container Exits Immediately

```
EDGE$ docker ps -a | grep <service>
abc123  <image>  "docker-entrypoint..."  5 seconds ago  Exited (1) 4 seconds ago
```

**Diagnostic steps:**

1. `docker logs abc123 --tail 50` -- view the crash output
2. `docker inspect abc123 | jq '.[0].State.Error'` -- check for Docker-level errors
3. `docker compose config` -- validate the compose file
4. Check volume mounts exist: `docker inspect abc123 | jq '.[0].Mounts'`
5. Check port availability: `lsof -i :<port>`

---

**End of Document**

Document version: 2.0.0 | Last reviewed: 2026-05-23 | Next review: 2026-08-23

This document is maintained by Platform Engineering. Submit changes via PR to `wheeler-org/platform-docs`. All playbooks must be reviewed and re-validated quarterly.
