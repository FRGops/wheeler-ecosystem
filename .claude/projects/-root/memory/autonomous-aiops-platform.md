---
name: autonomous-aiops-platform
description: "Wheeler Autonomous AI Ops + Self-Healing Engine — architecture, deliverables, and operational state as of 2026-05-24"
metadata: 
  node_type: memory
  type: project
  originSessionId: ecc0cddd-b2c8-4d99-9436-6f3f2f3937ac
---

The Wheeler Autonomous AI Ops platform is the always-on operational nervous system for the Wheeler ecosystem. Built and completed 2026-05-24 with final QA score A+ 97/100.

**Why:** The ecosystem must self-monitor, self-diagnose, self-heal, and self-correct 24/7 across AI Ops, Core-DB, Hostinger, Docker, PM2, Tailscale, monitoring, and gateways.

**How to apply:** When diagnosing any ecosystem issue, check watchdog scripts first (`/root/scripts/aiops-watchdog/ecosystem-health.sh`), then relevant Claude Code skill (`/root/.claude/skills/`), then formal documentation in the 10 deliverables at `/root/`. The self-healing engine uses verify→act→verify pattern.

## Architecture

- **Control Plane**: command-center (8100), ecosystem-guardian (8095), war-room-server (8091), event-bus-relay, Neo4j ecosystem graph (7474/7687)
- **Monitoring Stack**: Prometheus (9090), Loki (3100), Grafana, Alertmanager (9093), Uptime Kuma (3001), Netdata (19999), Healthchecks (3130), node_exporter (9100)
- **Agent Fleet**: 20+ Claude Code skills in `/root/.claude/skills/`
- **Deployment Engine**: `/root/deployment-engine/`
- **Rollback Engine**: `/root/rollback-engine/`
- **Watchdog Scripts**: `/root/scripts/aiops-watchdog/`

## 10 Deliverables (all at /root/)

1. AUTONOMOUS_AIOPS_ARCHITECTURE.md (883 lines)
2. SELF_HEALING_ENGINE.md (1,148 lines)
3. INCIDENT_RESPONSE_FRAMEWORK.md (828 lines)
4. DRIFT_DETECTION_FRAMEWORK.md (990 lines)
5. RESOURCE_INTELLIGENCE_ENGINE.md (847 lines)
6. DISASTER_RECOVERY_PLAN.md (1,445 lines)
7. ENFORCEMENT_EXPANSION_REPORT.md (1,108 lines)
8. EXECUTIVE_AIOPS_DASHBOARD.md (1,618 lines)
9. ECOSYSTEM_HEALTH_SCORING.md (977 lines)
10. WHEELER_AUTONOMOUS_AIOPS_REPORT.md (1,056 lines)

## Final QA (2026-05-24) — A+ 97/100

- 10/10 deliverables created (10,900+ total lines)
- 19/19 PM2 processes: ZERO secrets in env (command-center cleaned 53→10 vars, backup-verification removed)
- 42/42 Docker containers healthy, all 127.0.0.1 firewalled
- Zero :latest image tags, zero public port exposures (only SSH:22 on 0.0.0.0)
- FRGpassword1! fully rotated
- 7 watchdog scripts deployed in `/root/scripts/aiops-watchdog/`
- Scorecard: `/root/AIOPS_FINAL_QA_SCORECARD_20260524.md`
- Audit: `/root/AIOPS_ZERO_FALSE_GREEN_AUDIT_20260524.md`

## Known Issues

- Netdata HTTP endpoint: container healthy/metrics collecting, but web access control blocks Docker bridge (Prometheus scrapes fine)
- Watchdog orchestrator (ecosystem-health.sh): score aggregation needs minor tuning
