# Wheeler Brain OS — Governance Engine

## 1. Overview

The Governance Engine is the enforcement layer that ensures every resource in the Wheeler ecosystem complies with defined policies. It operates on a continuous **Detect → Report → Remediate → Verify** loop, treating policy violations as bugs that must be fixed, not exceptions to be documented.

### Governance Philosophy

```
NOT: "Container X doesn't have a healthcheck — we know, it's documented"
BUT:  "Container X doesn't have a healthcheck — fix it or provide a machine-readable exemption"

Every policy is either:
  ✅ COMPLIANT — no action needed
  ⚠ EXEMPT — documented, justified, reviewed periodically
  ❌ VIOLATING — queued for remediation
```

---

## 2. Policy Domains

### 2.1 Container Security Policy

```yaml
policy: container_security
scope: all Docker containers on all servers
rules:
  - name: cap_drop_all
    description: "Every container must drop ALL capabilities"
    check: docker inspect --format='{{.HostConfig.CapDrop}}' <container>
    expected: ["ALL"]
    exemptions:
      - crowdsec: "requires NET_ADMIN, NET_RAW (host network mode)"
      - fail2ban: "requires NET_ADMIN, NET_RAW (host network mode)"
    severity: critical

  - name: localhost_bind
    description: "All port binds must be 127.0.0.1 or Tailscale IP, never 0.0.0.0"
    check: docker inspect --format='{{range $p,$c := .NetworkSettings.Ports}}{{$p}}→{{(index $c 0).HostIp}}{{"\n"}}{{end}}' <container>
    expected: "127.0.0.1 or 100.x.x.x, not 0.0.0.0"
    exemptions:
      - sshd (port 22): "system sshd, not Docker"
      - nginx (port 443): "system nginx, not Docker"
    severity: critical

  - name: resource_limits
    description: "Every container must have mem_limit and cpus set"
    check: docker inspect --format='Mem={{.HostConfig.Memory}} CPU={{.HostConfig.NanoCpus}}' <container>
    expected: "Mem > 0 and CPU > 0"
    exemptions: []  # No exemptions — every container gets limits
    severity: high

  - name: healthcheck_defined
    description: "Every container must have a healthcheck"
    check: docker inspect --format='{{.Config.Healthcheck.Test}}' <container>
    expected: "non-null"
    exemptions:
      - crowdsec: "no shell in container (distroless)"
      - fincept: "interactive terminal, no health endpoint"
      - db-backup-1: "one-shot job, runs on schedule"
    severity: high

  - name: pinned_image
    description: "No :latest tags in production"
    check: docker inspect --format='{{.Config.Image}}' <container> | grep -c ':latest'
    expected: "0"
    exemptions: []  # All containers should pin
    severity: medium

  - name: non_root_user
    description: "Container should not run as root unless required"
    check: docker inspect --format='{{.Config.User}}' <container>
    expected: "not empty and not root"
    exemptions:
      - nginx containers: "master process requires root (drops priv for workers)"
      - s6-overlay images: "s6 supervisor needs root (drops priv via PUID/PGID)"
      - monitoring agents: "node_exporter, promtail need host access"
      - security tools: "crowdsec, fail2ban need network stack access"
    severity: low
```

### 2.2 Network Security Policy

```yaml
policy: network_security
scope: all servers
rules:
  - name: ufw_active
    description: "UFW must be active on all servers"
    check: ufw status
    expected: "Status: active"
    severity: critical

  - name: tailscale_only_db
    description: "COREDB must only accept connections from Tailscale interface"
    check: ufw status | grep -E "5432|6379"
    expected: "ALLOW on tailscale0 only"
    severity: critical

  - name: no_public_admin
    description: "Admin dashboards must be behind nginx basic auth"
    check: grep -l "auth_basic" /etc/nginx/sites-enabled/*
    expected: "All admin paths protected"
    severity: high

  - name: rate_limiting
    description: "All external endpoints must have rate limiting"
    check: grep "limit_req" /etc/nginx/sites-enabled/*
    expected: "limit_req zone defined"
    severity: medium
```

### 2.3 Secret Management Policy

```yaml
policy: secret_management
scope: all .env files and compose configurations
rules:
  - name: no_hardcoded_secrets
    description: "No passwords, keys, or tokens in docker-compose.yml files"
    check: grep -rE "(PASSWORD|SECRET|KEY|TOKEN)=" --include="docker-compose.yml" /opt/
    expected: "0 matches (all in .env files)"
    severity: critical

  - name: env_file_restricted
    description: ".env files must be chmod 600"
    check: find /opt -name ".env" -not -perm 600
    expected: "0 files"
    severity: critical

  - name: rotation_schedule
    description: "Internal secrets rotated every 90 days"
    check: compare last_rotation_date vs current date
    expected: "< 90 days"
    severity: high

  - name: unique_per_system
    description: "No shared passwords across systems"
    check: compare password hashes across .env files
    expected: "All unique"
    severity: high
```

### 2.4 PM2 Process Policy

```yaml
policy: pm2_governance
scope: all PM2 processes on AIOPS
rules:
  - name: all_online
    description: "All PM2 processes should be online unless documented"
    check: pm2 jlist | jq '.[] | select(.pm2_env.status != "online")'
    expected: "0 (except backup-verification: documented stopped)"
    severity: high

  - name: restart_threshold
    description: "No process should restart >3 times in 5 minutes"
    check: pm2 jlist | jq '.[] | select(.pm2_env.restart_time > 3)'
    expected: "0"
    severity: critical

  - name: memory_baseline
    description: "No process should exceed 2x its 7-day average memory"
    check: compare current memory vs pm2_monit_7day_avg
    expected: "< 2x baseline"
    severity: warning

  - name: env_consistency
    description: "All processes loading secrets from .env.shared via wrapper"
    check: pm2 prettylist | grep -c "pm2-env-wrapper.sh"
    expected: "All agent processes use wrapper"
    severity: medium
```

### 2.5 Repository Policy

```yaml
policy: repository_governance
scope: all git repositories
rules:
  - name: has_remote
    description: "Every repo must have a git remote for off-machine backup"
    check: git remote -v
    expected: "at least one remote configured"
    exemptions: []  # Fix the two repos without remotes
    severity: high

  - name: clean_working_tree
    description: "Production repos should have clean working trees"
    check: git status --porcelain
    expected: "0 lines (clean)"
    severity: low
```

### 2.6 Backup Policy

```yaml
policy: backup_governance
scope: all databases
rules:
  - name: automated_backup
    description: "Every production database must have automated backups"
    check: crontab -l | grep backup
    expected: "Backup job for each database"
    current_gap:
      - "No automated backup for COREDB PostgreSQL (wheeler-postgres)"
      - "No automated backup for RavynAI PostgreSQL"
      - "No automated backup for ClickHouse analytics data"
    severity: critical

  - name: backup_verification
    description: "Backups must be verified within 24h of creation"
    check: backup-verify.sh exit code
    expected: "0 (success)"
    current_status: "backup-verification PM2 process is STOPPED"
    severity: high

  - name: off_site_copy
    description: "Backups should exist on a different server from the source"
    check: verify backup location != source server
    expected: "Different server or external storage"
    severity: medium
```

---

## 3. Quality Gates

### 3.1 Gate Definitions

```
GATE: /slay (Full Ecosystem Health Audit)
  Checks: 20 endpoints across both servers
  Pass:   All 20 healthy
  Fail:   Any endpoint unhealthy → triggers remediation

GATE: /secrets-scan
  Checks: No hardcoded credentials in any config file
  Pass:   0 findings
  Fail:   Any finding → critical, must fix immediately

GATE: /docker-health
  Checks: All containers running, healthy, with limits
  Pass:   58/58 containers with mem_limit + cpus, 55/58 with healthchecks
  Fail:   Any container missing limits or unhealthy

GATE: /private-network
  Checks: No 0.0.0.0 binds, UFW active, Tailscale-only on COREDB
  Pass:   0 wildcard binds, UFW active
  Fail:   Any 0.0.0.0 bind → critical

GATE: /pm2-health
  Checks: All PM2 processes online (except documented exceptions)
  Pass:   17/18 online (backup-verification documented stopped)
  Fail:   Any unexpected stopped/errored process

GATE: /production-readiness (pre-deployment)
  Checks: All 7 deployment gates
  Pass:   7/7
  Fail:   Any gate → deployment blocked

GATE: /db-lockdown
  Checks: Database access restricted, passwords rotated, no insecure defaults
  Pass:   All databases with unique passwords, UFW restricted
  Fail:   Any finding
```

### 3.2 Gate Execution Flow

```
1. TRIGGER: Manual (/slay) or Automated (cron: wheeler-enterprise every 5 min)

2. CHECK: Run all applicable checks for this gate
   - Each check is a discrete, idempotent operation
   - Checks run in parallel where possible

3. EVALUATE: Compare results against pass/fail criteria
   - All critical checks pass = GATE OPEN
   - Any critical check fails = GATE CLOSED
   - Warning checks fail = GATE OPEN with advisories

4. REPORT: Output structured results
   - Pass: summary only
   - Fail: specific violations, severity, recommended remediation

5. REMEDIATE: If in autonomous mode, queue fixes
   - Auto-fix for well-understood issues (restart, resource adjust)
   - Manual approval required for destructive changes
```

---

## 4. Enforcement Mechanisms

### 4.1 Active Enforcement (Cron-driven)

```
EVERY 5 MINUTES (wheeler-lockdown-watchdog.sh):
  - Verify all 127.0.0.1 port binds still in place
  - Verify UFW rules haven't changed
  - Verify no new containers appeared without limits
  → If violation: attempt auto-fix, alert if unable

EVERY 2 MINUTES (autoheal.sh --once):
  - Check for stopped containers → restart
  - Check for unhealthy containers → investigate, restart if stale
  → If violation: restart, alert on 3rd consecutive failure

HOURLY (enforce-roles.sh):
  - Verify all containers have correct cap_drop/cap_add
  - Verify all .env files have 600 permissions
  → If violation: log, queue for manual review (destructive to change)

HOURLY (self-heal.sh):
  - Full health check across all services
  - Cross-reference with ecosystem graph
  → If violation: follow self-healing playbook

DAILY 2AM (backup-all.sh):
  - Run all backup jobs
  → If failure: alert immediately

DAILY 4AM (backup-verify.sh):
  - Verify yesterday's backups are valid
  → If failure: alert, mark backup system as degraded
```

### 4.2 Passive Enforcement (Policy-as-Code)

```
EVERY DEPLOYMENT (deploy-safety gate):
  - Compose file must pass policy validation before docker compose up
  - PM2 config must pass policy validation before pm2 start

EVERY CONTAINER START (docker event hook):
  - Container inspect → validate against policy
  - If non-compliant: block start, report violation
  - (Future: implement as Docker authorization plugin)
```

---

## 5. Exemption Management

### 5.1 Exemption Format

```yaml
exemptions:
  - container: crowdsec
    rule: cap_drop_all
    reason: "Host network mode requires NET_ADMIN and NET_RAW for packet inspection"
    requested_by: "security hardening 2026-05-24"
    expires: "2026-08-24"  # 90-day review
    alternatives_considered:
      - "Run without host network → breaks traffic inspection"
      - "Use alternative WAF → no equivalent functionality in Docker"
    risk_accepted: "Without cap_drop ALL, container has broader kernel access"
    compensating_controls:
      - "network_mode: host limits blast radius to one container"
      - "Non-privileged ports only"
```

### 5.2 Exemption Lifecycle

```
CREATE:  Operator documents exemption with reason + expiration
REVIEW:  Every 90 days, all exemptions re-evaluated
         "Is there now a way to comply? New image? New approach?"
EXPIRE:  If no action by expiration → violation, queued for remediation
REVOKE:  If fix implemented, remove exemption, container returns to compliant
```

---

## 6. Compliance Reporting

### 6.1 Current Compliance Scorecard

```
WHEELER ECOSYSTEM COMPLIANCE — 2026-05-24
─────────────────────────────────────────

CONTAINER SECURITY:
  ✅ cap_drop ALL:           58/58 (100%)
  ✅ 127.0.0.1 binds:       58/58 (100%)
  ✅ mem_limit + cpus:      58/58 (100%)
  ✅ healthchecks defined:   55/58 (95%) — 3 documented exemptions
  ⚠ non-root user:          44/58 (76%) — 14 documented exemptions
  ⚠ pinned images:          47/58 (81%) — 11 :latest on COREDB

NETWORK SECURITY:
  ✅ UFW active AIOPS:       Yes (26 rules)
  ❌ UFW active COREDB:      No (0 rules) — CRITICAL
  ✅ nginx basic auth:       All admin paths protected
  ✅ rate limiting:          All external endpoints
  ✅ Tailscale mesh:         All inter-server traffic encrypted

SECRET MANAGEMENT:
  ✅ no hardcoded secrets:   0 findings
  ✅ .env files chmod 600:   All verified
  ✅ internal DB passwords:  5/5 rotated (2026-05-24)
  ✅ internal tokens:        12/12 rotated (2026-05-24)
  ⚠ external API keys:      60+ pending rotation (dashboard access needed)

PM2 GOVERNANCE:
  ✅ processes online:       17/18 (backup-verification documented stopped)
  ✅ restart threshold:      0 processes exceeded
  ✅ memory baseline:        All within 2x range

REPOSITORY GOVERNANCE:
  ❌ no git remote:          wheeler-ecosystem, wheeler-revenue-automation
  ⚠ mismatched remote:      frgcrm frontend → frgops-audits.git

BACKUP GOVERNANCE:
  ❌ COREDB PostgreSQL:      No automated backup
  ❌ RavynAI PostgreSQL:     No automated backup
  ❌ ClickHouse:             No automated backup
  ❌ backup verification:    PM2 process stopped

OVERALL SCORE: 89% (42/47 checks passing, 5 failures)
```

### 6.2 Compliance Trend Dashboard

```
Weekly compliance score tracked over time:

Week 20 (May 11):  72% (pre-hardening)
Week 21 (May 18):  85% (container hardening done)
Week 22 (May 24):  89% (secret rotation done)
Week 23 target:    93% (fix COREDB UFW + backup gaps)
Week 24 target:    96% (pin COREDB images + git remotes)
Week 25 target:    98% (external key rotation + backup verification)
```

---

## 7. Integration with Other Brain OS Components

```
Governance Engine feeds:
  → AI Decision Layer: Violations become prioritized recommendations
  → Control Plane: Policies enforced at deploy time
  → Observability Fusion: Compliance metrics on unified dashboard
  → CEO Console: Compliance scorecard and trend
  → Self-Healing: Auto-remediation for well-understood violations

Governance Engine consumes:
  → Ecosystem Graph: Current state for policy evaluation
  → Observability Fusion: Metrics that trigger policy re-evaluation
  → Control Plane: Deployment events that trigger re-validation
```

---

*End of Governance Engine Design*
