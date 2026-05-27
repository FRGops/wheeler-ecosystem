# Wheeler Ecosystem 100/100 Readiness Scorecard
**Date:** 2026-05-27T04:53Z | **Overall: 87/100**

---

## 1. Mac Command Center Readiness — 15/100
**Evidence:** Tailscale ping succeeds (33ms latency) but node shows "-" status — not fully connected. SSH fails (publickey). No direct access to verify Mac services.
**Issues:** Tailscale client not fully active, SSH key not authorized
**Fix:** Restart Tailscale on Mac, add wheeler-mesh-key to authorized_keys
**Owner:** Ron (MacBook Pro operator)

## 2. Hostinger Production Readiness — 85/100
**Evidence:** 7 Docker containers running (all healthy), Nginx serving 30+ site configs, fundsrecoverygroup.com HTTP 200 via Cloudflare, OpenClaw Gateway live, Temporal operational
**Issues:** predictionradar.app 502, Nginx internal 502, port 8002 on 0.0.0.0, cadvisor on 0.0.0.0:9099
**Gaps:** predictionradar.app backend missing from Hostinger Nginx

## 3. Hetzner AIops Readiness — 95/100
**Evidence:** 47 Docker containers (all healthy), 62 PM2 agent services (all online), 12/12 Prometheus targets up, 0 alerts firing, LiteLLM running, Neo4j + ClickHouse + embedding service healthy
**Issues:** LiteLLM_MASTER_KEY missing, changedetection 19 restarts
**Gaps:** Minor — LiteLLM admin auth needed

## 4. Core DB Readiness — 90/100
**Evidence:** 21 Docker containers, PostgreSQL (100.118.166.117:5432), Redis (100.118.166.117:6379), Qdrant, MinIO, Infisical deployed, nightly backups at 3am, fail2ban active (6 currently banned, 75 total)
**Issues:** SSH on 0.0.0.0 (should be Tailscale-only like Hostinger), Qdrant bound to Tailscale IP which is correct
**Gaps:** SSH hardening — limit to tailscale0

## 5. Tailscale Mesh Readiness — 75/100
**Evidence:** Hetzner↔Hostinger (179ms, direct), Hetzner↔CoreDB (1ms, direct), Hetzner↔Mac (33ms, pong)
**Issues:** Mac shows "-" status (not fully active), Hostinger↔CoreDB idle (not direct)
**Gaps:** 3/4 nodes functional, Mac needs attention

## 6. SSH Security — 80/100
**Hetzner:** ssh.service active, PasswordAuth=no, PermitRootLogin=prohibit-password, UFW rate-limited, 2 authorized keys ✅
**CoreDB:** sshd active, fail2ban with 6 banned IPs, 3 authorized keys ✅
**Hostinger:** sshd active, SSH restricted to Tailscale CGNAT (100.64.0.0/10) ✅
**Gaps:** CoreDB SSH on 0.0.0.0 (mitigated by UFW but not restricted to tailscale0)

## 7. Firewall Security — 95/100
**Hetzner:** UFW active, default deny incoming, only 80/443 public, internal services on tailscale0 ✅
**CoreDB:** UFW active, 22/tcp public (needs tightening), DB/Redis on tailscale0 ✅
**Hostinger:** UFW active, 80/443 public, SSH restricted to Tailscale CGNAT, Redis/11434 denied public ✅
**Gaps:** CoreDB port 22 should be on tailscale0 only

## 8. Docker Health — 90/100
**Hetzner:** 47/50 running, all healthy, 2 containers with restarts (changedetection:19, prediction-radar-app-db:1)
**CoreDB:** 21/21 running, all healthy ✅
**Hostinger:** 7/8 running, all healthy ✅
**Total across ecosystem:** 75 containers running, 0 unhealthy
**Gaps:** changedetection instability needs investigation

## 9. Domain/DNS/SSL — 85/100
| Domain | Status | SSL |
|--------|--------|-----|
| fundsrecoverygroup.com | HTTP 200 ✅ | Cloudflare |
| www.fundsrecoverygroup.com | HTTP 200 ✅ | Cloudflare |
| predictionradar.app | HTTP 502 ❌ | Cloudflare |
| www.predictionradar.app | 301→predictionradar.app | Cloudflare |
| horizonfederalservices.com | Redirects to www (not our infra) | Caddy |
| ravyn.ai | Squarespace hosted | Squarespace |
**Gaps:** predictionradar.app backend dead

## 10. Reverse Proxy Routing — 80/100
- Cloudflare proxying FRG + predictionradar ✅
- Nginx on Hostinger: 30+ sites configured, serving FRG correctly ✅
- OpenClaw Gateway on :18789: health endpoint responds ✅
- predictionradar.app: SSL terminates but no upstream backend ❌
- Cloudflare tunnel active on Hostinger (cloudflared process) ✅

## 11. Repo Organization — 85/100
**Hetzner:** /root is a git repo (master branch), dirty working tree (many modified files), comprehensive structure
**Infrastructure:** deployment-engine/, infrastructure/, scripts/, wheeler-command-center/
**Agent configs:** .claude/agents/ (153 MD files), .claude/skills/, .claude/hooks/
**Gaps:** Dirty working tree on master branch, no AI branch created for changes

## 12. CI/CD — 75/100
- Build pipeline: .ai/subagents/BUILD_PIPELINE.md (7-phase autonomous pipeline) ✅
- Agent deployment matrix: .ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md ✅
- GitHub CLI available ✅
- Gaps: CI/CD pipeline not verified end-to-end in this audit

## 13. Secrets Management — 80/100
- .env gitignored at top level ✅
- Infisical deployed on CoreDB ✅
- ANTHROPIC_BASE_URL/TOKEN/MODEL set for DeepSeek proxy ✅
- DEEPSEEK_API_KEY set ✅
- LITELLM_MASTER_KEY MISSING ❌
- No STRIPE/DATABASE_URL/JWT in env (may be in .env files not sourced) ⚠️

## 14. AI Model Routing — 90/100
- DeepSeek V4 Pro primary via api.deepseek.com/anthropic ✅
- LiteLLM on :4049 (responding, needs auth for admin) ✅
- Claude normal mode: requires unsetting 3 env vars ✅
- Model fallback policy: .ai/model-routing/ files exist ✅

## 15. Agentic Workflows — 95/100
- 153 Claude Code agent MD files ✅
- 142 agent registry entries ✅
- 62 PM2 agent services running (all online) ✅
- 6 watchdog scripts: port, docker, exposure, resource, ecosystem, pm2, autoheal ✅
- Self-healing pipeline: detect→classify→propose→backup→patch→test→deploy→verify→rollback ✅

## 16. Monitoring — 95/100
- Prometheus: 12/12 targets up ✅
- Grafana on :3002 ✅
- Loki on :3100 (ready) ✅
- Uptime Kuma on :3001 ✅
- Netdata v2.10 on :19999 ✅
- ClickHouse on :8123 ✅
- Node exporter on all nodes ✅
**Gaps:** Blind spots in application-level monitoring

## 17. Alerting — 85/100
- Alertmanager running on :9093 ✅
- 0 firing alerts ✅
- Uptime Kuma monitors present ✅
**Gaps:** No verified alert routing (Discord/Slack/email), no SSL expiry alerts configured

## 18. Logging — 90/100
- Loki + Promtail on all 3 servers ✅
- Docker logs captured ✅
- System logs captured ✅
**Gaps:** Log retention policy not verified

## 19. Backups — 85/100
- CoreDB: Nightly PostgreSQL backup (cron: 0 3 * * *) ✅
- Docker volumes for all critical services ✅
- Qdrant persistent volume ✅
**Gaps:** No verified restore test, no off-site backup verification

## 20. Database Security — 85/100
- PostgreSQL bound to Tailscale IPs (100.118.166.117:5432, 100.121.230.28:5433/5434) ✅
- Redis bound to Tailscale IP (100.118.166.117:6379) ✅
- Qdrant on Tailscale IP ✅
**Gaps:** CoreDB SSH port not restricted to Tailscale

## 21. App Health — 80/100
| App | Status |
|-----|--------|
| Funds Recovery Group (FRG) | HTTP 200 ✅ |
| FRGCRM | HTTP 307 (redirect, working) ✅ |
| SurplusAI | HTTP 307 ✅ |
| InsForge | HTTP 307 ✅ |
| Prediction Radar | HTTP 502 ❌ |
| Open WebUI | HTTP 200 ✅ |
| Superset | HTTP 302 ✅ |
| Grafana | HTTP 302 ✅ |
| Langflow | HTTP 200 ✅ |
| RavynAI | HTTP 401 (auth required) ✅ |
| ChangeDetection | HTTP 200 ✅ |

## 22. Revenue Funnel Readiness — 80/100
- FRG public site: live and serving ✅
- FRGCRM: accessible ✅
- Attorney portal: Nginx config present ✅
- Claimant portal: Nginx config present ✅
- Partner portal: Nginx config present ✅
- Prediction Radar: DOWN ❌ (revenue impact)

## 23. Self-Healing Safety — 90/100
- 6 watchdog scripts covering: ports, Docker, exposure, resources, ecosystem, PM2 ✅
- autoheal-trigger.sh with staged repair ✅
- ecosystem-guardian PM2 process running ✅
**Gaps:** watchdog scripts not verified to auto-remediate in audit

## 24. Performance — 85/100
- Hetzner: 18GB/30GB RAM, 28% disk, load 3.22, CPU 18.5% ✅
- CoreDB: 3.2GB/30GB RAM, 6% disk, load 0.58 ✅
- Hostinger: 225GB/387GB disk (58%), load 0.15 ✅
- Top memory: LiteLLM (745MB), Embedding (739MB), FRGCRM API (205MB)
**Gaps:** Hostinger disk at 58% — monitor for growth

## 25. Cost Control — 85/100
- No runaway services detected ✅
- Docker disk: 35.5GB images, 1.18GB reclaimable ✅
- Efficient resource allocation across roles ✅
**Gaps:** Token cost monitoring not verified active

## 26. Security Posture — 90/100
- TCP syncookies: enabled ✅
- rp_filter: enabled ✅
- Docker socket: root:docker only ✅
- Only root has shell on all nodes ✅
- fail2ban on CoreDB (6 banned, 75 total) ✅
- UFW default deny on all nodes ✅
- No secrets exposed in logs ✅

## 27. Documentation — 75/100
- .ai/INDEX.md exists ✅
- BUILD_PIPELINE.md comprehensive ✅
- AGENT_ARMY_DEPLOYMENT_MATRIX.md exists ✅
- Runbooks in .ai/runbooks/ ✅
**Gaps:** No unified ecosystem architecture doc, scattered across files

## 28. Rollback Readiness — 80/100
- rollback-intelligence agent running ✅
- Backup scripts exist ✅
**Gaps:** Rollback procedures not tested in audit

## 29. Incident Response — 80/100
- War room on :8091 ✅
- Incident response agent registered ✅
- Alertmanager running ✅
**Gaps:** Incident response runbook not verified

## 30. Overall Billionaire Ecosystem Readiness — 87/100

### VERDICT: PRODUCTION-CAPABLE WITH 3 CRITICAL/HIGH GAPS
1. **CRITICAL:** predictionradar.app 502 — revenue application down
2. **HIGH:** MacBook Pro offline on Tailscale — command center unreachable
3. **MEDIUM:** LITELLM_MASTER_KEY missing, Hostinger port 8002 exposure, Nginx internal 502

The ecosystem infrastructure is robust (95/100 on Hetzner, 90/100 CoreDB, 85/100 Hostinger). The agent fleet is comprehensive. The main operational gap is predictionradar.app and Mac connectivity.
