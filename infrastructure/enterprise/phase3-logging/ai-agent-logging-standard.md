# =============================================================================
# Wheeler Enterprise — AI Agent Structured Logging Standard
# =============================================================================
# JSON schema for all AI agent logs. Used by LiteLLM proxy, LangFlow,
# custom agents, and any service that calls LLM APIs.
# =============================================================================

# ── Log Levels ───────────────────────────────────────────────────────────
# debug   — Detailed tracing, token-level debugging
# info    — Normal successful request
# warn    — Retryable errors, rate limits hit, fallback activated
# error   — Failed request, model unavailable, timeout
# fatal   — Service cannot operate (e.g., all providers down)

# ── Required Fields ─────────────────────────────────────────────────────
# timestamp   — ISO 8601 with timezone (RFC3339)
# level       — One of: debug, info, warn, error, fatal
# agent       — Service name (e.g., "litellm-proxy", "langflow", "ravynai-agent")
# status      — "success" | "error" | "fallback" | "rate_limited"

# ── Example: Successful Request ─────────────────────────────────────────
# ```json
# {
#   "timestamp": "2026-05-23T14:30:00.000Z",
#   "level": "info",
#   "agent": "litellm-proxy",
#   "model": "deepseek-chat",
#   "provider": "deepseek",
#   "request_id": "req_d5e6f7a8",
#   "user_id": "app-ravynai",
#   "tokens": {
#     "prompt": 2400,
#     "completion": 512,
#     "total": 2912
#   },
#   "cost": {
#     "currency": "USD",
#     "amount": 0.0029
#   },
#   "latency_ms": 1200,
#   "status": "success",
#   "error": null,
#   "metadata": {
#     "endpoint": "/chat/completions",
#     "temperature": 0.7,
#     "stream": true,
#     "cache_hit": false
#   }
# }
# ```

# ── Example: Rate Limited (Fallback Triggered) ──────────────────────────
# ```json
# {
#   "timestamp": "2026-05-23T14:31:00.000Z",
#   "level": "warn",
#   "agent": "litellm-proxy",
#   "model": "deepseek-chat",
#   "provider": "deepseek",
#   "request_id": "req_b9c0d1e2",
#   "user_id": "app-prediction-radar",
#   "tokens": null,
#   "cost": null,
#   "latency_ms": 150,
#   "status": "rate_limited",
#   "error": "Rate limit exceeded for deepseek/deepseek-chat",
#   "metadata": {
#     "endpoint": "/chat/completions",
#     "fallback_provider": "openai",
#     "fallback_model": "gpt-4o-mini",
#     "retry_count": 1
#   }
# }
# ```

# ── Example: Provider Outage ────────────────────────────────────────────
# ```json
# {
#   "timestamp": "2026-05-23T14:32:00.000Z",
#   "level": "error",
#   "agent": "litellm-proxy",
#   "model": "claude-opus-4-7",
#   "provider": "anthropic",
#   "request_id": "req_f1a2b3c4",
#   "user_id": "app-frgops",
#   "tokens": null,
#   "cost": null,
#   "latency_ms": 30000,
#   "status": "error",
#   "error": "Connection timeout after 30s — Anthropic API unreachable",
#   "metadata": {
#     "endpoint": "/messages",
#     "fallback_provider": "deepseek",
#     "fallback_model": "deepseek-v4-pro",
#     "timeout_ms": 30000,
#     "retry_count": 3
#   }
# }
# ```

# ── Python Logger Implementation ────────────────────────────────────────
# ```python
# import json
# import logging
# import time
# from datetime import datetime, timezone
#
# class WheelerAgentFormatter(logging.Formatter):
#     def format(self, record):
#         log_entry = {
#             "timestamp": datetime.now(timezone.utc).isoformat(),
#             "level": record.levelname.lower(),
#             "agent": getattr(record, "agent", "unknown"),
#             "model": getattr(record, "model", "unknown"),
#             "provider": getattr(record, "provider", "unknown"),
#             "request_id": getattr(record, "request_id", None),
#             "user_id": getattr(record, "user_id", None),
#             "tokens": getattr(record, "tokens", None),
#             "cost": getattr(record, "cost", None),
#             "latency_ms": getattr(record, "latency_ms", None),
#             "status": getattr(record, "status", "unknown"),
#             "error": record.message if record.levelno >= logging.WARNING else None,
#             "metadata": getattr(record, "metadata", {})
#         }
#         return json.dumps(log_entry, default=str)
# ```

# ── Node.js Logger Implementation ──────────────────────────────────────
# ```javascript
# const winston = require('winston');
#
# const wheelerFormat = winston.format.combine(
#   winston.format.timestamp(),
#   winston.format.json()
# );
#
# const logger = winston.createLogger({
#   level: process.env.LOG_LEVEL || 'info',
#   format: wheelerFormat,
#   defaultMeta: {
#     agent: process.env.AGENT_NAME || 'unknown',
#     model: process.env.MODEL_NAME || 'unknown',
#     provider: process.env.PROVIDER_NAME || 'unknown'
#   },
#   transports: [
#     new winston.transports.File({
#       filename: '/var/log/wheeler/agents/agent.log',
#       maxsize: 52428800, // 50MB
#       maxFiles: 10
#     }),
#     new winston.transports.Console({
#       format: winston.format.combine(
#         winston.format.colorize(),
#         winston.format.simple()
#       )
#     })
#   ]
# });
# ```
