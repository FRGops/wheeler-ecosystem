# Wheeler Brain OS — Executive Command Center

**Version:** 2.0.0 | **Date:** 2026-05-24 | **Status:** DEPLOYED at command.aiops:8100

## Architecture

FastAPI server at `127.0.0.1:8100`, nginx reverse-proxied at `command.aiops:443` with basic auth.

### API Endpoints

| Endpoint | Method | Auth | Returns |
|---|---|---|---|
| `/api/health` | GET | basic | `{"status":"healthy","timestamp":"..."}` |
| `/api/ecosystem` | GET | basic | Full ecosystem health: containers, PM2, system, score |
| `/` | GET | basic | HTML dashboard |

### Health Score Formula

```
score = (container_health_pct × 0.5) + (pm2_online_pct × 0.3) + (0.2 bonus)
```

### Dashboard Pages (Current)

1. **Ecosystem Overview** — KPI grid: containers, PM2, memory, disk, load, score
2. **Container Fleet** — 42 containers with status, image, ports
3. **PM2 Process List** — 20 processes with memory, CPU, status

### Dashboard Pages (Planned)

4. Deployments — recent + pending
5. Repo Router — all Wheeler repos
6. Observability — Prometheus + Loki + Uptime Kuma fusion
7. AI Agent Fleet — 52 agents with status
8. Cost Monitoring — API spend, server costs
9. Alerts — active + acknowledged
10. Security Posture — UFW, SSL certs, secrets scan
11. Tailscale Mesh — node connectivity
12. Server Health — per-server CPU/RAM/disk
13. Docker Health — per-container details
14. PM2 Health — per-process trends
15. Rollback Readiness — backup freshness
16. Revenue Systems — FRG, RavynAI, SurplusAI
17. Automation Status — active automations
18. Ecosystem Intelligence — AI recommendations

## Authentication

- nginx basic auth: `admin` user with bcrypt password
- Rate limiting: 10 req/s burst
- Security headers: HSTS, X-Frame-Options, X-Content-Type-Options

## Data Flow

```
Docker socket ──┐
PM2 jlist ──────┼──► Command Center ──► JSON API ──► HTML Dashboard
System stats ───┘         │
                          ▼
                   Neo4j Ecosystem Graph
```
