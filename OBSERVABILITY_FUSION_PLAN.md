# Wheeler Brain OS — Observability Fusion Plan

**Version:** 2.0.0 | **Date:** 2026-05-24

## Current Observability Stack

| System | Port | Purpose | Status |
|---|---|---|---|
| Prometheus | :9090 | Metrics collection | Active |
| Grafana | :3002 | Visualization | Active |
| Loki | :3100 | Log aggregation | Active |
| Promtail | — | Log shipping | Active |
| Alertmanager | :9093 | Alert routing | Active |
| Uptime Kuma | :3001 | Uptime monitoring | Active |
| Netdata | :19999 | System metrics | Active |
| Pushgateway | :9092 | Ephemeral metrics | Active |
| PM2 logs | ~/.pm2/logs/ | Process logs | Active |
| Journald | — | System logs | Active |

## Fusion Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  COMMAND CENTER (:8100)                  │
│              Unified health score + alerts               │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ METRICS  │   │   LOGS   │   │  UPTIME  │
│ Prometheus│  │  Loki    │   │  Kuma    │
│ Netdata   │  │ Journald │   │ Healthchecks│
│ PM2 stats │  │ PM2 logs │   │          │
└──────────┘   └──────────┘   └──────────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│              ALERT CORRELATION ENGINE                    │
│         alert-correlation agent + Alertmanager          │
└─────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│              INCIDENT RESPONSE                           │
│       war-room-server (:8091) + incident-response       │
└─────────────────────────────────────────────────────────┘
```

## Key Metrics Tracked

- Container health (42 containers)
- PM2 process health (20 processes)
- System: CPU, RAM, disk, load
- API: LiteLLM latency, error rates
- Database: Postgres connections, replication lag
- Network: Tailscale connectivity, nginx request rates
- Security: UFW status, SSL cert expiry, secret scan results

## Alert Severity Levels

| Level | Response | Agent |
|---|---|---|
| CRITICAL | Immediate, war-room | incident-response-agent |
| HIGH | Within 1 hour | wheeler-infra-agent |
| MEDIUM | Within 24 hours | monitoring-intelligence |
| LOW | Next business day | autonomous-optimization |
