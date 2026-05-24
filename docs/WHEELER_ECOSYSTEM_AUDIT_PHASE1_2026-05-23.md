# WHEELER ECOSYSTEM — PHASE 1 DISCOVERY + AUDIT
## Generated: 2026-05-23 18:53 UTC
## Auditor: Claude Code (DeepSeek V4 via AI Ops)

=================================================================
## 1. SERVER INVENTORY
=================================================================

### SERVER 1: wheeler-aiops-01 (AI Ops / Control Plane)
| Property | Value |
|----------|-------|
| Provider | Hetzner CPX51 |
| OS | Ubuntu 24.04.4 LTS (Noble) |
| Kernel | 6.8.0-111-generic |
| CPUs | 16 |
| RAM | 30GB (20GB used / 10GB available) |
| Disk | 338GB (63GB used / 262GB free — 20%) |
| Public IP | 5.78.140.118 |
| Tailscale IP | 100.121.230.28 |
| Private Network | **NOT ATTACHED** |
| Uptime | 14 days |
| User | root |

### SERVER 2: wheeler-core-db-01 (Worker/Data/AI Node)
| Property | Value |
|----------|-------|
| Provider | Hetzner CPX51 |
| OS | Ubuntu (7.0.0-15-generic) |
| CPUs | 16 |
| RAM | 30GB (2.2GB used / 28GB available) |
| Disk | 338GB (17GB used / 308GB free — 6%) |
| Public IP | 5.78.210.123 |
| Tailscale IP | 100.118.166.117 |
| Private Network IP | **10.0.0.2** (enp7s0) |
| Uptime | Fresh (containers up 18 min) |

### SERVER 3: srv1476866 (Hostinger Production)
| Property | Value |
|----------|-------|
| Provider | Hostinger |
| OS | Ubuntu (6.8.0-117-generic) |
| CPUs | 8 |
| RAM | 31GB (2.8GB used / 28GB available) |
| Disk | 387GB (241GB used / 147GB free — 63%) |
| Tailscale IP | 100.98.163.17 |
| Special | **k3s Kubernetes running** |
| Uptime | Active |

=================================================================
## 2. NETWORKING AUDIT
=================================================================

### TAILSCALE MESH (ONLINE)
```
wheeler-aiops-01      100.121.230.28     Linux    Online
wheeler-core-db-01    100.118.166.117    Linux    Online
srv1476866            100.98.163.17      Linux    Online
```
STATUS: All 3 nodes online. Mesh operational.

### HETZNER PRIVATE NETWORK
```
Name: wheeler-core-network
CIDR: 10.0.0.0/16
Subnet: 10.0.0.0/24 (gateway: 10.0.0.1)
Zone: us-west
Created: 2026-05-21
Attached servers: wheeler-core-db-01 (10.0.0.2)
```
**CRITICAL GAP: wheeler-aiops-01 is NOT attached to the private network.**
This means inter-server traffic between AI Ops and Worker goes through public IPs or Tailscale.

### USER'S TARGET NETWORK DESIGN
```
Target CIDR:  10.10.0.0/16
AI Ops:       10.10.1.10
Worker/Data:  10.10.1.20
```
**FINDING: Existing network uses 10.0.0.0/16, not 10.10.0.0/16.**
Either re-create with target CIDR or adapt plan to existing network.

### PUBLIC PORTS EXPOSED (AI Ops)
| Port | Service | Binding | Risk |
|------|---------|---------|------|
| 22 | SSH | 0.0.0.0 | ACCEPTABLE (rate-limited) |
| 80/443 | HTTP/HTTPS | 0.0.0.0 | ACCEPTABLE |
| 5432 | Postgres (native) | 0.0.0.0 | **HIGH RISK** |
| 5433 | Postgres (frgops-standby) | 0.0.0.0 | **HIGH RISK** |
| 5434 | Postgres (ravynai) | 0.0.0.0 | **HIGH RISK** |
| 7860 | LangFlow | 0.0.0.0 | MEDIUM |
| 8007 | RavynAI App | 0.0.0.0 | MEDIUM |
| 8088 | Superset | 0.0.0.0 | MEDIUM |
| 8090 | Unknown | 0.0.0.0 | MEDIUM |
| 8098 | Prediction Radar | 0.0.0.0 | MEDIUM |
| 3001 | Uptime Kuma | 0.0.0.0 | MEDIUM |
| 3002 | Grafana | 0.0.0.0 | LOW (Tailscale-gated) |
| 5000 | ChangeDetection | 0.0.0.0 | MEDIUM |
| 5001 | Dockge | 0.0.0.0 | MEDIUM |
| 9000 | Portainer | 0.0.0.0 | **DENIED by UFW** |
| 9090 | Prometheus | 0.0.0.0 | **DENIED by UFW** |
| 19999 | Netdata | 0.0.0.0 | MEDIUM |
| 3130 | Healthchecks | 0.0.0.0 | LOW |
| 8123 | ClickHouse HTTP | 0.0.0.0 | **HIGH RISK** |

### UFW CONFIGURATION
- ACTIVE and well-configured
- Tailscale-only rules for sensitive services
- Some public DB ports have DENY rules (5433, 9090, 9000)
- 100.64.0.0/10 (Tailscale/CGNAT range) allowed for DB ports
- fail2ban active and running

=================================================================
## 3. SECURITY AUDIT
=================================================================

### SECRET EXPOSURE — CRITICAL FINDINGS

1. **DeepSeek API Key in ~/.zshrc** (world-readable: -rw-r--r--)
   ```bash
   export ANTHROPIC_AUTH_TOKEN=sk-4ac726fce2564ce88ba7f22640c8eff3
   ```

2. **Hetzner Cloud Token in ~/.bashrc** (world-readable: -rw-r--r--)
   ```bash
   export HCLOUD_TOKEN=0cIsim41rr5mfo1onucy4mLrGWzCPMarIDk6JjMt6hjtNZHcCkzoDpuMQZqOSkl9
   ```

3. **No SSH config file exists** (~/.ssh/config is empty)
4. **Multiple Postgres instances exposed** on public interfaces
5. **No secrets manager** (age/sops not installed)
6. **No gitleaks hooks** configured

### EXPOSURE CLASSIFICATION
- 🔴 CRITICAL: API keys in world-readable shell configs
- 🔴 CRITICAL: Database ports exposed publicly (5432, 5433, 5434)
- 🟠 HIGH: HCLOUD_TOKEN in bashrc (full cloud API access)
- 🟠 HIGH: ClickHouse HTTP exposed on 8123
- 🟡 MEDIUM: Many services on 0.0.0.0 that could be Tailscale-only
- 🟢 LOW: SSH rate-limited, fail2ban active

=================================================================
## 4. DOCKER AUDIT (AI Ops — 30 CONTAINERS)
=================================================================

### MONITORING STACK
| Container | Status | Port |
|-----------|--------|------|
| uptime-kuma | Up (healthy) | 3001 |
| aiops-grafana | Up | 3002 |
| aiops-prometheus | Up | 9090 |
| netdata | Up (healthy) | 19999 |
| loki | Up | 3100 (localhost) |
| promtail | Up | 9080 (localhost) |
| aiops-healthchecks | Up | 3130 |
| hostinger-health-exporter | Up | 9091 |

### APPLICATION STACK
| Container | Status | Port |
|-----------|--------|------|
| prediction-radar-app-web | Up | 8098 |
| prediction-radar-app-api | Up (healthy) | internal |
| prediction-radar-dashboard-v2 | Up (healthy) | 3000 (internal) |
| prediction-radar-app-scheduler | Up | internal |
| prediction-radar-app-worker | Up | internal |
| prediction-radar-app-db | Up (healthy) | 5432 (internal) |
| prediction-radar-app-redis | Up (healthy) | 6379 (internal) |
| aiops-ravynai-app | Up (healthy) | 8007 |
| aiops-superset | Up (healthy) | 8088 |
| langflow | Up | 7860 |
| open-webui | Up (healthy) | 3000 (localhost) |
| docuseal | Up | 3010 |

### INFRASTRUCTURE STACK
| Container | Status | Port |
|-----------|--------|------|
| portainer | Up | 9000 |
| dockge | Up (healthy) | 5001 |
| aiops-changedetection | Up | 5000 |
| aiops-clickhouse | Up | 8123 |
| temporal-postgres | Up | internal |
| temporal-temporal-1 | Up | internal |
| temporal-temporal-ui-1 | **Restarting** | internal |
| frgops-standby | Up | 5433 |
| dockge-test-nginx | Up | 8080 |
| usesend | Up | internal |

### FAILING SERVICES
- temporal-temporal-ui-1: Restarting loop (1 restart every ~36 seconds)
- aiops-loki: Stuck in "Created" state (not started)
- backup-verification (PM2): Stopped

### DOCKER NETWORKS (17 networks)
All are bridge networks — no overlay/swarm networking. Each compose project has its own isolated bridge.

=================================================================
## 5. PM2 PROCESS AUDIT (AI Ops — 18 PROCESSES)
=================================================================

### AGENT SERVICES (online)
| Process | Memory | Uptime |
|---------|--------|--------|
| ecosystem-guardian | 72.6 MB | 14h |
| event-bus-relay | 72.5 MB | 14h |
| war-room-server | 65.7 MB | 14h |
| voice-outreach-service | 53.8 MB | 14h |
| openclaw-dashboard | 72.0 MB | 15h |
| design-agent-svc | 120.8 MB | 13h |
| horizon-agent-svc | 107.3 MB | 13h |
| paperless-agent-svc | 112.6 MB | 13h |
| prediction-radar-agent-svc | 116.2 MB | 13h |
| ravyn-agent-svc | 113.0 MB | 13h |
| frgcrm-agent-svc | 104.8 MB | 13h |
| insforge-agent-svc | 79.1 MB | 13h |
| surplusai-scraper-agent-svc | 116.7 MB | 13h |
| voice-agent-svc | 111.7 MB | 13h |
| surplusai-portal-api | 107.1 MB | 10h |

### CRITICAL SERVICES
| Process | Memory | Uptime |
|---------|--------|--------|
| litellm | 357.0 MB | 11h (6 restarts) |
| frgcrm-api | 236.1 MB | 16m (2 restarts) |

### STOPPED
- backup-verification: Stopped

=================================================================
## 6. WORKER/DATA SERVER AUDIT (wheeler-core-db-01)
=================================================================

### DOCKER CONTAINERS (18 — focused, clean)
| Container | Role |
|-----------|------|
| wheeler-postgres | Primary database |
| wheeler-redis | Cache/queue |
| wheeler-minio | Object storage |
| temporal-server | Workflow engine |
| temporal-ui | Temporal dashboard |
| prediction-radar-worker | ML workers |
| prediction-radar-scheduler | Cron/scheduling |
| temporal-pipeline-worker | ETL workers |
| temporal-pipeline-scheduler | ETL scheduling |
| wheeler-grafana | Monitoring |
| wheeler-prometheus | Metrics |
| wheeler-loki | Log aggregation |
| wheeler-uptime-kuma | Uptime monitoring |
| promtail | Log shipping |
| redis-exporter | Redis metrics |
| postgres-exporter | Postgres metrics |
| node-exporter | System metrics |
| usesend | Email service |

STATUS: Clean, well-organized, purpose-fit. This is what the AI Ops server should look like.

=================================================================
## 7. HOSTINGER PRODUCTION AUDIT (srv1476866)
=================================================================

### CRITICAL FINDINGS
1. **60+ app directories** under /opt/apps — massive sprawl
2. **k3s Kubernetes running** — adds complexity layer
3. **Disk at 63% (241GB used)** — approaching warning threshold
4. **Multiple superpowers directories** found across /opt
5. **Temporal also running here** — cross-server duplication
6. **agent-skills-for-context-engineering, private-ai, tabby, firecrawl, etc.** — many experimental projects

### KEY APPS
authentik, bookstack, chatwoot, frgcrm, n8n-workflows, listmonk, plausible, twenty-crm, surplusai-portal, prediction-radar-app, ravynai-opportunity-graph

=================================================================
## 8. TOOLING INVENTORY (AI Ops)
=================================================================

### INSTALLED
| Tool | Version | Notes |
|------|---------|-------|
| git | 2.43.0 | OK |
| Docker | 29.5.2 | OK |
| Node.js | v22.22.2 | OK |
| Python | 3.12.3 | OK |
| tailscale | 1.98.3 | OK |
| UFW | active | OK |
| fail2ban | active | OK |
| PM2 | latest | OK |
| LiteLLM | running | Proxy for DeepSeek |

### MISSING (from target list)
gh, starship, tmux (config only), fzf, ripgrep, fd, jq, yq, bat, eza, zoxide, atuin, direnv, mise, uv, pnpm, bun, lazygit, lazydocker, age, sops, trivy, gitleaks, shellcheck, shfmt, pre-commit, ansible, opentofu, taskfile, just, act

### NOT APPLICABLE (Linux server, not Mac)
Homebrew — not needed on Ubuntu (use apt)

=================================================================
## 9. FILESYSTEM AUDIT
=================================================================

### /opt/wheeler-ecosystem/
**DOES NOT EXIST** as a unified directory. Instead there are scattered directories:
```
/opt/wheeler/                          — PM2 ecosystem config
/opt/wheeler-command-center/           — README only
/opt/wheeler-incident-command/         — Incident response
/opt/wheeler-knowledge-base/           — Knowledge base
/opt/wheeler-orchestrator/             — README only
/opt/wheeler-ai-cost-governance/       — AI cost monitoring
/opt/wheeler-cleanup-governance/       — Cleanup scripts
/opt/wheeler-security-audit/           — Security audit scripts
/opt/wheeler-data-consolidation/       — Data consolidation
/opt/wheeler-revenue-automation/       — Revenue automation
```

### /opt/stacks/
Organized compose stacks: 01-monitoring, 02-aiops, 03-openclaw-staging, 04-brain-staging, 05-frgops-staging, temporal, dockerecosystemmanager

### KEY DIRECTORIES
```
/opt/apps/       — 34 app subdirectories (prediction-radar, langflow, monitoring, etc.)
/opt/1panel/     — 1Panel management (may conflict with Dockge/Portainer)
/opt/backups/    — Backups directory
/opt/logs/       — Logs
/opt/migration/  — Migration artifacts
```

=================================================================
## 10. CLAUDE CODE / DEEPSEEK CONFIGURATION
=================================================================

### CURRENT SETUP
```bash
# ~/.zshrc
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN=sk-4ac726fce2564ce88ba7f22640c8eff3
export ANTHROPIC_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
export CLAUDE_CODE_EFFORT_LEVEL=max
```

### LITELLM PROXY
- PM2 process "litellm" running on port 4049 (localhost)
- Config at /root/.claude/litellm-deepseek.yaml
- Serves as proxy between Claude Code and DeepSeek API

### CLAUDE CODE PLUGINS
- 30+ plugins installed (all official Claude plugins)
- Massive PATH additions for each plugin

### SETTINGS
- settings.json: Base configuration
- settings.local.json: Permissions and local overrides (10KB - very large)
- Session files and history actively maintained

=================================================================
## 11. THE "SUPERPOWERS" MYSTERY — RESOLVED
=================================================================

**On Hostinger**, /opt/apps/prediction-radar-app/.superpowers is a FILE (not directory) containing "brainstorm".

Multiple superpowers directories exist:
- /opt/frg-ecosystem/repos/superpowers (git repo)
- /opt/libraries/superpowers (library)
- /opt/libraries/GitNexus/docs/superpowers
- /opt/libraries/posthog/docs/superpowers

**On AI Ops**, NO superpowers directory exists. The Hostinger /superpowers is a git repo with docs and library code, not a shell environment.

=================================================================
## 12. RISK ASSESSMENT MATRIX
=================================================================

| Risk | Severity | Description |
|------|----------|-------------|
| API keys in shell configs | 🔴 CRITICAL | World-readable secrets in .zshrc/.bashrc |
| Public DB ports | 🔴 CRITICAL | Postgres on 5432/5433/5434 exposed to internet |
| No private network for AI Ops | 🟠 HIGH | Inter-server traffic over public IP |
| Hostinger disk 63% full | 🟠 HIGH | 241GB used, no monitoring found |
| 1Panel + Dockge + Portainer | 🟠 HIGH | 3 competing management UIs |
| Service sprawl on AI Ops | 🟡 MEDIUM | 30 containers, 18 PM2 processes |
| Hostinger app sprawl | 🟡 MEDIUM | 60+ app directories, many experimental |
| temporal-ui restart loop | 🟡 MEDIUM | Failing service on AI Ops |
| No backup verification running | 🟡 MEDIUM | PM2 process "backup-verification" stopped |
| Missing dev tooling | 🟢 LOW | Can be installed gradually |
| No SSH config | 🟢 LOW | Easy fix |
| No standardized dotfiles | 🟢 LOW | Can be bootstrapped |

=================================================================
## 13. WHAT IS WORKING WELL
=================================================================

1. Tailscale mesh — all 3 servers connected and routable
2. Worker/Data server — clean, well-organized, purpose-fit
3. UFW firewall — active with specific rules
4. fail2ban — active and configured
5. Docker healthchecks — most containers have them
6. Monitoring stack — Grafana, Prometheus, Loki, Uptime Kuma, Netdata all deployed
7. LiteLLM proxy — DeepSeek access routed through local proxy
8. Wheeler governance tools — cost monitoring, cleanup scripts, security audit tools exist
9. PM2 process management — agent services well-organized
10. Private network exists — just needs AI Ops attached

=================================================================
## 14. IMMEDIATE ACTIONS (NO-REGRET)
=================================================================

1. **Attach AI Ops to Hetzner private network** — network already exists
2. **Move secrets out of .zshrc/.bashrc** — use ~/.pm2/secrets.env or age/sops
3. **chmod 600 ~/.zshrc ~/.bashrc** — remove world-readable
4. **Bind DB ports to Tailscale IP only** — 5433, 5434 should not be on 0.0.0.0
5. **Fix temporal-ui restart loop** — investigate and stabilize
6. **Remove dockge-test-nginx** — appears to be test artifact
7. **Decide: Portainer vs Dockge vs 1Panel** — standardize on ONE
8. **Start backup-verification** — critical safety net
9. **Install missing core tools** — gh, jq, yq, ripgrep, fd, fzf for operator efficiency
10. **Create ~/.ssh/config** — standardize server aliases

=================================================================
## 15. NEXT PHASE RECOMMENDATIONS
=================================================================

After completing immediate actions:
- Phase 2: Attach AI Ops to private network, set static IP 10.0.0.3
- Phase 3: Tailscale is done — document and harden
- Phase 4: Install standardized tooling across all servers
- Phase 5: Create wheeler-dev-bootstrap repo with dotfiles
- Phase 6: Clean up Claude Code config (move secrets, standardize)
- Phase 7: Build tmux Jarvis cockpit
- Phase 8: Organize /opt/wheeler-ecosystem/ unified directory
- Phase 9-16: Continue as planned

=================================================================
END OF PHASE 1 AUDIT
=================================================================
