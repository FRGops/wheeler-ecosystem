# =============================================================================
# Wheeler Enterprise — Centralized Logging Architecture
# =============================================================================
# Design for unified log aggregation across all 3 servers.
# =============================================================================

## ── Architecture Overview ───────────────────────────────────────────────

Three-layer logging architecture:

  Layer 1: Collection (Promtail on each server)
  Layer 2: Aggregation (Loki on AIOPS)
  Layer 3: Visualization (Grafana on AIOPS) + Long-term archive (S3/MinIO)

Flow:
  Docker containers → json-file stdout/stderr → Promtail → Loki → Grafana
  PM2 processes     → .pm2/logs/*.log          → Promtail → Loki → Grafana
  System logs       → journald → rsyslog        → Promtail → Loki → Grafana
  AI agent logs     → /var/log/wheeler/agents/  → Promtail → Loki → Grafana
  Nginx/Traefik     → access/error logs         → Promtail → Loki → Grafana

## ── PM2 Log Shipping ──────────────────────────────────────────────────

PM2 writes logs to ~/.pm2/logs/ by default. Promtail tails these files.

PM2 ecosystem.config.js additions for structured logging:

```javascript
module.exports = {
  apps: [{
    name: 'my-service',
    script: './server.js',
    // Structured JSON logging for AI agents and APIs
    log_type: 'json',
    // Merge stdout/stderr to single stream
    merge_logs: true,
    // Log date format
    log_date_format: 'YYYY-MM-DDTHH:mm:ss.sssZ',
    // Max log file size before rotation
    max_size: '50M',
    // Number of rotated files to keep
    retain: 10,
    // Compress rotated logs
    compress: true,
    // Custom log format for structured output
    env: {
      NODE_ENV: 'production',
      LOG_FORMAT: 'json'
    }
  }]
};
```

## ── Docker Log Shipping ───────────────────────────────────────────────

Docker daemon.json already configures json-file driver with rotation:
  max-size: 50MB per file
  max-file: 3 rotated files
  mode: non-blocking (container won't block if log buffer fills)

Promtail's docker_sd_config automatically discovers all containers
and ships their logs to Loki with container metadata.

## ── AI Agent Structured Log Format ────────────────────────────────────

All AI agents MUST output JSON logs with this schema:

```json
{
  "timestamp": "2025-01-15T10:30:00.000Z",
  "level": "info",
  "agent": "litellm-proxy",
  "model": "deepseek-v3",
  "provider": "deepseek",
  "request_id": "req_abc123",
  "user_id": "user_xyz",
  "tokens": {
    "prompt": 1500,
    "completion": 300,
    "total": 1800
  },
  "cost": {
    "currency": "USD",
    "amount": 0.0042
  },
  "latency_ms": 850,
  "status": "success",
  "error": null,
  "metadata": {
    "endpoint": "/v1/chat/completions",
    "temperature": 0.7,
    "stream": false
  }
}
```

Required fields: timestamp, level, agent, model, status
Optional fields: tokens, cost, latency_ms, error, metadata

## ── Log Retention Policies ────────────────────────────────────────────

| Log Type              | Hot (Loki) | Warm (MinIO) | Cold (Archive) | Compliance |
|-----------------------|------------|--------------|-----------------|------------|
| Docker containers     | 30 days    | 90 days      | None            | Standard   |
| PM2 applications      | 30 days    | 90 days      | None            | Standard   |
| AI agent requests     | 90 days    | 365 days     | 7 years         | SOX/GDPR   |
| Nginx/Traefik access  | 30 days    | 90 days      | None            | Standard   |
| Auth logs             | 90 days    | 365 days     | None            | Security   |
| PostgreSQL logs       | 30 days    | 90 days      | None            | Standard   |
| System logs           | 14 days    | 30 days      | None            | Standard   |

"Hot" = Loki (queryable in Grafana)
"Warm" = Compressed in object storage (restore to query)
"Cold" = Archive tier (compliance only)

## ── Log Shipping Security ─────────────────────────────────────────────

1. All Promtail → Loki traffic flows over Tailscale mesh (100.64.0.0/10)
2. Loki's HTTP port (3100) is not exposed to public internet (UFW blocks)
3. Sensitive log fields are redacted via Promtail pipeline stages:
   - API keys, passwords, tokens → replaced with [REDACTED]
4. Log tampering detection: Loki chunks are content-addressed

## ── Cost Allocation Tags ──────────────────────────────────────────────

Docker labels for cost tracking:
  com.wheeler.service: "litellm-proxy"
  com.wheeler.role: "ai-infra"

These flow through Promtail → Loki labels → Grafana dashboards
for per-service cost analysis.
