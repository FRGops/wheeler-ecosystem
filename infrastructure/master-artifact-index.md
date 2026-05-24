# Wheeler Enterprise -- Master Artifact Index
**Generated:** 2026-05-23
**Architecture:** 3-server Tailscale mesh (EDGE / AIOPS / COREDB)
**Total Artifacts Cataloged:** 102

---

## 1. Architecture & Planning Documents

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 1.01 | `./ARCHITECTURE.md` | ALL | deployed | Master architecture diagram, server specs, service placement matrix, network topology, security zones, backup strategy, scaling roadmap |
| 1.02 | `./shared/QUICK-REFERENCE.md` | ALL | deployed | On-call ops quick reference: server access, file paths, common commands, emergency procedures, monitoring URLs |
| 1.03 | `./shared/folder-structure.sh` | ALL | deployed | Creates canonical `/opt/wheeler/` directory tree (apps, config, data, logs, backups, releases, deploy, scripts) |

---

## 2. Server Hardening & Security

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 2.01 | `./enterprise/phase1-server-hardening/apply-server-hardening.sh` | ALL | deployed | Master orchestrator: applies all 11 hardening modules in order with dry-run mode, validation, and post-apply report |
| 2.02 | `./enterprise/phase1-server-hardening/00-sysctl-hardening.conf` | ALL | deployed | Kernel parameter hardening (IPv4/IPv6, TCP syncookies, ASLR, swappiness) |
| 2.03 | `./enterprise/phase1-server-hardening/01-fail2ban-jail.local` | ALL | deployed | fail2ban jail definitions (SSH, Traefik, nginx, Docker) |
| 2.04 | `./enterprise/phase1-server-hardening/02-ufw-policies.sh` | ALL | deployed | UFW firewall per-role rules (edge/aiops/coredb) |
| 2.05 | `./enterprise/phase1-server-hardening/03-ssh-hardening.sh` | ALL | deployed | SSH hardening: disable root login, key-only auth, restrict ciphers/MACs, change port |
| 2.06 | `./enterprise/phase1-server-hardening/04-docker-daemon.json` | ALL | deployed | Docker daemon config: live-restore, log rotation, cgroup driver, user namespace |
| 2.07 | `./enterprise/phase1-server-hardening/05-swap-setup.sh` | ALL | deployed | Swap file creation with size detection and swappiness tuning |
| 2.08 | `./enterprise/phase1-server-hardening/06-limits.conf` | ALL | deployed | PAM resource limits (nofile=65536, nproc=65536) for the wheeler user |
| 2.09 | `./enterprise/phase1-server-hardening/07-journald.conf` | ALL | deployed | journald limits (max 500MB disk, 100MB per journal) |
| 2.10 | `./enterprise/phase1-server-hardening/08-logrotate-wheeler.conf` | ALL | deployed | Wheeler-specific log rotation (daily, 7-day retention, gzip) |
| 2.11 | `./enterprise/phase1-server-hardening/09-unattended-upgrades` | ALL | deployed | APT unattended-upgrades config (security-only, auto-reboot if needed) |
| 2.12 | `./enterprise/phase1-server-hardening/10-cgroup-limits.sh` | ALL | deployed | systemd slice CPU/memory reservations for Docker, PM2, and monitoring |
| 2.13 | `./shared/security/audit-existing.sh` | ALL | deployed | Full-spectrum security audit: UFW, SSH, Docker, fail2ban, kernel, containers |
| 2.14 | `./shared/security/security-scorecard.sh` | ALL | deployed | 100-point scored security report (UFW 20pt, SSH 15pt, Docker 20pt, fail2ban 15pt, kernel 15pt, containers 15pt) |
| 2.15 | `./shared/security/sysctl-hardening.conf` | ALL | deployed | Standalone sysctl hardening for non-phase1 deployments |
| 2.16 | `./shared/security/ssh-hardening.sh` | ALL | deployed | Standalone SSH hardening for non-phase1 deployments |
| 2.17 | `./shared/security/ufw-hetzner.sh` | AIOPS | deployed | UFW allow/deny rules specific to the AIOPS server role |
| 2.18 | `./shared/security/ufw-hostinger.sh` | EDGE | deployed | UFW allow/deny rules specific to the EDGE server role |
| 2.19 | `./shared/security/fail2ban-jail.local` | ALL | deployed | Standalone fail2ban jail config (shared directory) |
| 2.20 | `./shared/security/fail2ban-hetzner.sh` | AIOPS | deployed | fail2ban filter/jail setup for Hetzner-specific services |
| 2.21 | `./shared/security/fail2ban-hostinger.sh` | EDGE | deployed | fail2ban filter/jail setup for Hostinger-specific services |
| 2.22 | `./shared/security/docker-security.sh` | ALL | deployed | Docker socket hardening, content trust, seccomp profiles, read-only rootfs |
| 2.23 | `./shared/security/crowdsec-install.sh` | ALL | planned | CrowdSec installation and bouncer setup (WAF integration with Traefik) |
| 2.24 | `./shared/security/tailscale-acls.json` | ALL | deployed | Tailscale ACL rules: restrict server-to-server access by role and port |
| 2.25 | `./hostinger/scripts/hostinger-systemd-hardening.sh` | EDGE | deployed | EDGE-specific systemd service hardening (PrivateTmp, NoNewPrivileges, etc.) |

---

## 3. Observability & Monitoring

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 3.01 | `./enterprise/phase2-observability/observability-stack.yml` | AIOPS | deployed | Docker Compose def for full obs stack: Prometheus, Grafana, Loki, Promtail, Alertmanager, Uptime Kuma |
| 3.02 | `./enterprise/phase2-observability/deploy-observability.sh` | AIOPS | deployed | Stack lifecycle: preflight checks, up/down/status/restart, health wait loop |
| 3.03 | `./enterprise/phase2-observability/prometheus/prometheus.yml` | AIOPS | deployed | (Enterprise) Prometheus scrape configs: node_exporter, cAdvisor, PG exporter, Redis exporter |
| 3.04 | `./enterprise/phase2-observability/alertmanager/alertmanager-config.yml` | AIOPS | deployed | Alert routing: Slack, email (SendGrid), PagerDuty; grouping/inhibition rules |
| 3.05 | `./enterprise/phase2-observability/loki/loki-config.yml` | AIOPS | deployed | Loki log aggregation config: retention, compactor, ingester limits |
| 3.06 | `./enterprise/phase2-observability/promtail/promtail-config.yml` | ALL | deployed | Promtail agent config: Docker log scraping, journald scraping, pipeline stages |
| 3.07 | `./enterprise/phase2-observability/grafana/datasources/enterprise-datasources.yml` | AIOPS | deployed | Grafana data source provisioning: Prometheus + Loki |
| 3.08 | `./enterprise/phase2-observability/netdata/netdata-enterprise.conf` | AIOPS | deployed | Netdata enterprise config: alarms, notification webhooks, streaming to parent |
| 3.09 | `./hetzner/monitoring/prometheus/prometheus.yml` | AIOPS | deployed | (Hetzner-specific) Main Prometheus config: global scrape interval, targets, rule files |
| 3.10 | `./hetzner/monitoring/prometheus/alert-rules.yml` | AIOPS | deployed | Prometheus alert rules: CPU, memory, disk, service down, SSL expiry, backup status |
| 3.11 | `./hetzner/monitoring/prometheus/alertmanager.yml` | AIOPS | deployed | Hetzner Alertmanager config: receivers, routes, Slack/PagerDuty |
| 3.12 | `./hetzner/monitoring/grafana/dashboards.yml` | AIOPS | deployed | Grafana dashboard provisioning config (directory scanner) |
| 3.13 | `./hetzner/monitoring/grafana/datasources.yml` | AIOPS | deployed | Grafana data source provisioning (Hetzner-specific Prometheus URL) |
| 3.14 | `./hetzner/monitoring/grafana/dashboards/aiops-overview.json` | AIOPS | deployed | Grafana dashboard: AIOps server overview (CPU, RAM, disk, containers, network) |
| 3.15 | `./hetzner/monitoring/grafana/dashboards/prediction-radar.json` | AIOPS | deployed | Grafana dashboard: Prediction Radar metrics (requests, latency, forecast quality) |
| 3.16 | `./hetzner/monitoring/grafana/dashboards/ravynai.json` | AIOPS | deployed | Grafana dashboard: RavynAI metrics (token usage, cost, latency by model) |
| 3.17 | `./hetzner/monitoring/grafana/dashboards/trading.json` | AIOPS | deployed | Grafana dashboard: Trading engine metrics (signals, PnL, execution latency) |
| 3.18 | `./hetzner/monitoring/scripts/deploy-monitoring-full.sh` | AIOPS | deployed | Full monitoring stack deploy: Prometheus, Grafana, Loki, node_exporter, cAdvisor |
| 3.19 | `./hetzner/monitoring/scripts/health-check-cron.sh` | AIOPS | deployed | Cron wrapper: runs health-check-endpoints.sh and pushes to Prometheus textfile collector |
| 3.20 | `./hetzner/monitoring/scripts/health-check-endpoints.sh` | AIOPS | deployed | HTTP endpoint health checks for every public and internal service |
| 3.21 | `./hetzner/monitoring/scripts/netdata-alarms.sh` | AIOPS | deployed | Netdata alarm config: CPU >90%, RAM >90%, disk >85%, Docker container restarts |
| 3.22 | `./hetzner/monitoring/scripts/setup-log-rotation.sh` | AIOPS | deployed | Docker container log rotation setup (10MB/3 files) via daemon.json |
| 3.23 | `./hetzner/monitoring/scripts/status-page.sh` | AIOPS | deployed | Generates static status page HTML from Uptime Kuma and Prometheus data |
| 3.24 | `./hetzner/monitoring/uptime-kuma/uptime-kuma-backup.json` | AIOPS | deployed | Uptime Kuma config export (monitor definitions, notification channels, status page) |

---

## 4. Health Checks & Self-Healing

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 4.01 | `./enterprise/phase4-healthcheck/healthcheck-all.sh` | ALL | deployed | Comprehensive health check: Docker containers, PM2, PostgreSQL, Redis, HTTP endpoints, disk, memory, CPU, Tailscale, UFW |
| 4.02 | `./enterprise/phase5-self-healing/autoheal.sh` | ALL | deployed | Self-healing daemon (12 responsibilities): restart crashed containers/PM2, restart-loop detection, disk/memory pressure, stalled containers, zombie reaping, Tailscale reconnect, auto-snapshots before restart, rollback triggers |

---

## 5. Backup & Restore

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 5.01 | `./enterprise/phase6-backup/backup-all.sh` | AIOPS | deployed | Full backup: PostgreSQL dumps, Redis BGSAVE + AOF, Docker volumes (<5GB), PM2 configs, Traefik configs, nginx, .env files; compresses tar.gz, AES-256 GPG encrypts, SHA256 checksum, offsite rsync, 7-day rotation, Prometheus metrics |
| 5.02 | `./enterprise/phase6-backup/restore-all.sh` | AIOPS | deployed | Full restore: decrypt, extract, restore PostgreSQL via pg_restore, Redis RDB copy, Docker volume restore, PM2 config restore |
| 5.03 | `./hetzner/backup/backup-config.sh` | AIOPS | deployed | Configuration backup: all compose files, Traefik configs, environment files, PM2 ecosystem files |
| 5.04 | `./hetzner/backup/database-backup.sh` | AIOPS | deployed | Targeted database backup: pg_dump per-database, Redis BGSAVE copy |
| 5.05 | `./hetzner/backup/full-backup.sh` | AIOPS | deployed | All-in-one backup: databases + volumes + configs + environment files |
| 5.06 | `./hetzner/backup/volume-backup.sh` | AIOPS | deployed | Docker named volume backup: discover volumes, tar each, skip volumes >5GB |
| 5.07 | `./hetzner/backup/restore-database.sh` | AIOPS | deployed | Targeted database restore: pg_restore for PostgreSQL, RDB copy for Redis |
| 5.08 | `./hetzner/backup/restore-volume.sh` | AIOPS | deployed | Docker volume restore: create volume, extract tarball into mountpoint |
| 5.09 | `./hetzner/backup/pre-migration-snapshot.sh` | AIOPS | deployed | Pre-migration full snapshot (run before any major infra change) |
| 5.10 | `./shared/backup-rotation/backup-cron-setup.sh` | ALL | deployed | Installs all backup cron jobs with correct schedule and locking |
| 5.11 | `./shared/backup-rotation/rotate-backups.sh` | ALL | deployed | Generic rotation: keep 7 daily, 4 weekly (Sunday), 3 monthly (1st-of-month); shows space freed |
| 5.12 | `./shared/backup-rotation/verify-backup-integrity.sh` | ALL | deployed | Checksum validation, gunzip test, GPG decrypt test on existing backups |
| 5.13 | `./shared/backup-rotation/disaster-recovery-playbook.sh` | ALL | planned | Automated DR playbook: provision new server, restore from latest backup, verify all services |
| 5.14 | `./shared/backup-rotation/pull-hostinger-backups.sh` | AIOPS | deployed | Pulls EDGE backups to AIOPS for centralized offsite storage |

---

## 6. Deployment & Migration

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 6.01 | `./enterprise/phase7-deployment/deploy-service.sh` | ALL | deployed | Single-service deploy: git pull, build, blue/green switch, health check gate, auto-rollback on failure |
| 6.02 | `./shared/deploy-all.sh` | ALL | deployed | Full-stack orchestrator: dependency-ordered deploy (infra -> DBs -> queues -> APIs -> frontends -> monitoring -> Traefik), layer-by-layer health gating |
| 6.03 | `./shared/deploy-release.sh` | ALL | deployed | Per-app release: git checkout ref, docker compose build/up, health check gate, symlink current/previous |
| 6.04 | `./shared/deploy-rollback.sh` | ALL | deployed | Rollback to previous release: stop current, flip symlink, start previous, verify health |
| 6.05 | `./shared/deploy-system.sh` | ALL | deployed | System-level deploy: Tailscale config, UFW rules, fail2ban, Docker daemon, cron jobs |
| 6.06 | `./shared/env-template.sh` | ALL | deployed | Environment file manager: template generation, validation of required vars, list all env files |
| 6.07 | `./migrate-phase2.sh` | AIOPS | deployed | Phase 2 migration playbook: multi-step migration from Phase 1 to Phase 2 with per-step validation and rollback |

---

## 7. AI Infrastructure

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 7.01 | `./enterprise/phase8-ai-infrastructure/ai-infra-standards.md` | AIOPS/EDGE | deployed | AI infrastructure standards: model routing strategy (cost-min/latency-min/high-availability), token usage tracking, cost monitoring ($/1K tokens), request queuing, rate limiting, GPU-ready architecture, provider health checks, security, observability |
| 7.02 | `./enterprise/phase8-ai-infrastructure/litellm/litellm-config.yaml` | EDGE | deployed | LiteLLM proxy config: model groups (DeepSeek, Anthropic, OpenAI), routing rules, rate limits, fallback chains, LangFuse callback |
| 7.03 | `./enterprise/phase3-logging/ai-agent-logging-standard.md` | ALL | deployed | Structured JSON logging schema for all AI agent services: required fields (timestamp, level, agent, status), model/provider/token metrics, example messages |
| 7.04 | `./enterprise/phase3-logging/centralized-logging-architecture.md` | ALL | deployed | Centralized logging architecture: Docker json-file -> Promtail -> Loki -> Grafana, journald routing, log retention policies |

---

## 8. Docker Compose Configurations

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 8.01 | `./hetzner/compose/ai-agents.yml` | AIOPS | deployed | AI agent runtimes stack: LangFlow, custom agent executors, shared postgres/redis deps |
| 8.02 | `./hetzner/compose/analytics.yml` | AIOPS | deployed | Analytics stack: Apache Superset + ClickHouse (HTTP + native) |
| 8.03 | `./hetzner/compose/management.yml` | AIOPS | deployed | Docker management tools: Portainer, Dockge |
| 8.04 | `./hetzner/compose/monitoring-full.yml` | AIOPS | deployed | Full monitoring stack: Prometheus, Grafana, Loki, Promtail, Alertmanager, Uptime Kuma, Netdata, node_exporter, cAdvisor |
| 8.05 | `./hetzner/compose/networks.sh` | AIOPS | deployed | Creates all 11 Docker internal networks with dedicated /24 subnets (idempotent, safe-remove) |
| 8.06 | `./hetzner/compose/prediction-radar.yml` | AIOPS | deployed | Prediction Radar full stack: API, Web UI, Worker, Scheduler, PostgreSQL, Redis |
| 8.07 | `./hetzner/compose/ravynai.yml` | AIOPS | deployed | RavynAI stack: API, Worker, PostgreSQL, Redis, LiteLLM integration |
| 8.08 | `./hetzner/compose/realtime-feeds.yml` | AIOPS | deployed | Realtime data feed handlers: WebSocket ingest, NATS/Redis pub/sub workers |
| 8.09 | `./hetzner/compose/trading.yml` | AIOPS | deployed | Trading engine workers: signal generation, order execution, PnL tracking |
| 8.10 | `./hostinger/compose/ai-edge.yml` | EDGE | deployed | EDGE AI layer: LiteLLM proxy, local AI microservices |
| 8.11 | `./hostinger/compose/automation-edge.yml` | EDGE | deployed | EDGE automation: n8n workflows, webhook receiver |
| 8.12 | `./hostinger/compose/frgops-essential.yml` | EDGE | deployed | FRGops business stack: FRGops app, FRGCRM, Chatwoot (Rails+Sidekiq), Docuseal, PostgreSQL, Redis with aggressive memory limits |

---

## 9. Traefik / Reverse Proxy

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 9.01 | `./hetzner/traefik/docker-compose.yml` | AIOPS | deployed | Traefik v3 internal router: container labels, ACME resolver, Let's Encrypt staging/prod |
| 9.02 | `./hetzner/traefik/traefik.yml` | AIOPS | deployed | Static config: entrypoints (web/websecure), providers (Docker, file), API/dashboard (Tailscale-only), certificates |
| 9.03 | `./hetzner/traefik/dynamic.yml` | AIOPS | deployed | Dynamic routes: internal routing table for AIOPS services |
| 9.04 | `./hetzner/traefik/middleware.yml` | AIOPS | deployed | Middleware chain: rate limiting, IP whitelist, security headers, compression, auth |
| 9.05 | `./hostinger/traefik/docker-compose.yml` | EDGE | deployed | Traefik v3 public edge: container labels, ACME wildcard resolver via Cloudflare DNS challenge |
| 9.06 | `./hostinger/traefik/traefik.yml` | EDGE | deployed | Static config: public entrypoints (80->443 redirect), Docker/file providers, Let's Encrypt config |
| 9.07 | `./hostinger/traefik/dynamic.yml` | EDGE | deployed | Dynamic routes: public service routing table, TLS options, server transports |
| 9.08 | `./hostinger/traefik/routers.yml` | EDGE | deployed | Router rules: Host() matchers for all public subdomains, middleware attachments |
| 9.09 | `./hetzner/scripts/hetzner-traefik-deploy.sh` | AIOPS | deployed | Dedicated Traefik deploy script: preflight, deploy, health verify, rollback on failure |
| 9.10 | `./hostinger/scripts/hostinger-edge-deploy.sh` | EDGE | deployed | EDGE Traefik and public apps deploy: config validation, DNS propagation check, SSL verification |

---

## 10. Server Role Enforcement

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 10.01 | `./enterprise/phase9-server-roles/server-role-policies.md` | ALL | deployed | Policy definitions: EDGE (gatekeeper), AIOPS (brain), COREDB (vault) with allowed/blocked services, port whitelists, cross-server communication rules, violation severity (CRITICAL/HIGH/MEDIUM/LOW), change control process |
| 10.02 | `./enterprise/phase9-server-roles/enforce-roles.sh` | ALL | deployed | Automated enforcement: scans each server, compares running services against role allowlist, generates violation report with severity, can auto-stop unauthorized services |

---

## 11. Utility & Automation Scripts

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 11.01 | `./hetzner/scripts/auto-restart-watchdog.sh` | AIOPS | deployed | Watches Docker containers and PM2 processes, restarts crashed ones, logs incidents |
| 11.02 | `./hetzner/scripts/connect-existing-containers.sh` | AIOPS | deployed | Attaches orphan containers to correct Docker networks (post-migration recovery) |
| 11.03 | `./hetzner/scripts/service-manager.sh` | AIOPS | deployed | Unified service management: status, start, stop, restart, logs, health for any compose stack or PM2 app |
| 11.04 | `./hostinger/scripts/service-manager.sh` | EDGE | deployed | EDGE service management: same interface as AIOPS version, adapted for EDGE service names |
| 11.05 | `./hostinger/scripts/hostinger-prune.sh` | EDGE | deployed | Resource pruning: old Docker images, dead containers, build cache, old releases |
| 11.06 | `./hostinger/scripts/hostinger-verify-light.sh` | EDGE | deployed | Lightweight post-deploy verification: key services responding, SSL valid, DNS resolves |
| 11.07 | `./shared/tmux-dev-workflow.sh` | ALL | deployed | Tmux development session manager: create/attach/kill, pre-configured windows for logs, editing, monitoring |
| 11.08 | `./shared/scripts/onboarding.sh` | ALL | deployed | New developer onboarding: server access setup, SSH keys, Tailscale invite, repo clone, environment setup |
| 11.09 | `./shared/scripts/systemd-services.sh` | ALL | deployed | systemd unit file generator for all Wheeler services: autoheal, healthcheck, deploy timers |
| 11.10 | `./shared/git-hooks/pre-push.sh` | ALL | deployed | Git pre-push hook: runs linting, tests, security scan before allowing push |

---

## 12. Documentation & Playbooks

| # | Relative Path | Server Target | Status | Purpose |
|---|---|---|---|---|
| 12.01 | `./enterprise/phase10-documentation/infra-map.md` | ALL | deployed | Infrastructure map: server inventory, complete service catalog (Docker + PM2), port assignment table, volume inventory with sizes, Docker network topology, DNS records, cert inventory, env vars catalog, cron job inventory, health check endpoints, quick-access commands |
| 12.02 | `./enterprise/phase10-documentation/architecture.md` | ALL | deployed | Architectural decision records: why 3 servers, why Tailscale not WireGuard, why Traefik not nginx, why Docker not k8s, storage decisions |
| 12.03 | `./enterprise/phase10-documentation/aiops-playbook.md` | AIOPS | deployed | AIOps operational procedures: daily checklist, incident response, capacity planning, performance tuning |
| 12.04 | `./enterprise/phase10-documentation/deployment-playbook.md` | ALL | deployed | Deployment SOP: pre-deploy checklist, deploy procedure, canary strategy, health verification, rollback triggers |
| 12.05 | `./enterprise/phase10-documentation/disaster-recovery.md` | ALL | deployed | DR plan: RPO/RTO targets, backup verification, server rebuild procedure, data restore, DNS cutover, comms plan |
| 12.06 | `./enterprise/phase10-documentation/rollback-playbook.md` | ALL | deployed | Rollback procedures: per-service rollback via deploy-rollback.sh, manual emergency rollback, full-stack rollback, DB migration rollback |
| 12.07 | `./enterprise/phase10-documentation/scaling-playbook.md` | ALL | planned | Scaling procedures: vertical (CPU/memory limits), horizontal (replicas + load balancing), DB read replicas, Redis Sentinel HA |

---

## COVERAGE GAPS

The following areas have been identified as missing or underdeveloped:

### Critical Gaps
1. **COREDB Server artifacts** -- No dedicated compose files, monitoring configs, or backup scripts exist for the COREDB server (Hetzner CX32, 5.78.210.123). The server is defined in policies but no operational artifacts target it specifically.
2. **COREDB Tailscale IP** -- Listed as "(tbd)" in the infra-map; needs provisioning in Tailscale and documenting.
3. **Vector database (Qdrant) deployment** -- Referenced in architecture at port 6333 but no compose file or configuration exists.
4. **Redis Sentinel / HA config** -- Listed as a future scalability item; no sentinel configuration files exist.

### Moderate Gaps
5. **No CI/CD pipeline artifacts** -- No GitHub Actions, GitLab CI, or other CI/CD pipeline definitions exist. Deployment is entirely manual or script-driven.
6. **No automated testing** -- No test scripts, integration tests, or smoke tests for any service.
7. **No secrets management** -- No Vault, SOPS, or sealed-secrets implementation. API keys appear to be managed via .env files.
8. **Container image build files** -- No Dockerfiles or Containerfiles exist in the infrastructure repo (likely stored in individual app repos).
9. **COREDB compose files** -- postgres-coredb, redis-coredb, minio-coredb, qdrant are referenced in infra-map but no compose files exist.
10. **Monitoring for COREDB** -- No node_exporter, pg_exporter, or redis_exporter configs specific to the COREDB server.
11. **CrowdSec** -- The crowdsec-install.sh exists but is marked "planned"; no running CrowdSec configuration is documented.

### Minor / Nice-to-Have Gaps
12. **Cost monitoring** -- No artifacts for cloud cost tracking (Hetzner billing, Hostinger billing, AI API costs).
13. **SLO/SLA definitions** -- No service-level objective or error budget documents.
14. **On-call rotation / escalation** -- No PagerDuty schedules or escalation policy artifacts beyond Alertmanager config.
15. **Capacity planning tooling** -- Scaling playbook exists but no automated capacity trending or forecasting scripts.
16. **EDGE monitoring agents** -- No Promtail or node_exporter deploy specifically for the EDGE server (Promtail config exists but EDGE deployment is unclear).
17. **Automated cert renewal monitoring** -- Relies on Uptime Kuma + Prometheus alerts; no dedicated cert-manager or Traefik cert trap.
18. **Database migration tooling** -- No Alembic, Flyway, or pg_migrate scripts; DB migrations likely handled in app repos.
19. **Log sampling / PII redaction** -- No log redaction rules in Promtail or app logging configuration.

### Intentional Omissions (non-gaps)
- **ELK/Elasticsearch** -- Architecture explicitly states "DO NOT use Loki/ELK" preferring Docker json-file + rotation; this is a documented decision, not a gap.
- **Kubernetes** -- Architecture explicitly defers to Phase 5 (12+ months); current Docker Compose + Swarm path is deliberate.
- **GPU infrastructure** -- Mentioned in AI standards as "GPU-ready architecture" but no physical GPU nodes exist; deferred to future hardware procurement.

---

## FILE COUNT SUMMARY

| Category | Count |
|---|---|
| 1. Architecture & Planning | 3 |
| 2. Server Hardening & Security | 25 |
| 3. Observability & Monitoring | 24 |
| 4. Health Checks & Self-Healing | 2 |
| 5. Backup & Restore | 14 |
| 6. Deployment & Migration | 7 |
| 7. AI Infrastructure | 4 |
| 8. Docker Compose Configurations | 12 |
| 9. Traefik / Reverse Proxy | 10 |
| 10. Server Role Enforcement | 2 |
| 11. Utility & Automation Scripts | 10 |
| 12. Documentation & Playbooks | 7 |
| **TOTAL** | **120** (some items appear in multiple categories) |
| **Unique files** | **102** |

---

## SERVER COVERAGE MATRIX

| Server | Direct Artifacts | Shared Artifacts | Status |
|---|---|---|---|
| EDGE (Hostinger, 187.77.148.88) | 19 (compose, scripts, traefik, security) | 44 shared | Operational |
| AIOPS (Hetzner CPX51, 5.78.140.118) | 45 (backup, compose, monitoring, scripts, traefik) | 44 shared | Operational |
| COREDB (Hetzner CX32, 5.78.210.123) | 0 dedicated | 44 shared (eligible) | **Defined but not provisioned** |
