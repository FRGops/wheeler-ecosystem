/**
 * =============================================================================
 * Wheeler AIOPS — OPTIMIZED PM2 Ecosystem Configuration
 * =============================================================================
 * Generated:  2026-05-23
 * Based on:   Phase 2 PM2 Optimization Audit
 * Target:     AIOPS server (5.78.140.118) — 16 cores, 30 GB RAM
 * Node:       Hetzner CPX51
 * Tailscale:  100.121.230.28
 *
 * OPTIMIZATIONS APPLIED (vs. previous configs):
 *   1. Cluster mode for I/O-bound services (litellm, openclaw-dashboard)
 *   2. Memory caps on all services (3 previously un-capped)
 *   3. Tiered restart policies (critical=10, agent=5, infra=5)
 *   4. Standardized restart_delay=5000ms across all services
 *   5. Centralized log paths under /opt/logs/pm2/<service>/
 *   6. Fixed Redis URL with authentication for litellm
 *   7. Reduced inflated memory caps (agent services: 500M→400M, frgcrm-api: 2G→1G)
 *   8. pm2-logrotate integrated with 30-day retention
 *
 * DEPLOY:
 *   pm2 start optimized-ecosystem.config.js --env production
 *   pm2 reload optimized-ecosystem.config.js --env production   (zero-downtime)
 *   pm2 save --force
 *
 * ROLLBACK:
 *   pm2 delete all
 *   pm2 start /root/templates/pm2/backup-ecosystem-$(date).config.js
 *   pm2 save --force
 * =============================================================================
 */

// ─── Core Database URLs (COREDB via Tailscale) ──────────────────────────────
const COREDB_TAILSCALE = process.env.COREDB_TAILSCALE || "100.118.166.117";
// REDIS_PASSWORD: resolved at runtime via ${REDIS_PASSWORD} in env blocks
// DB_PASSWORD: resolved at runtime via ${DB_PASSWORD} in env blocks

// DATABASE_URL: resolved at runtime via ${DATABASE_URL} in env blocks
// To set externally: export DATABASE_URL="postgresql://wheeler:PASSWORD@HOST:5432/wheeler_core"

// REDIS_URL: resolved at runtime via ${REDIS_URL} in env blocks
// To set externally: export REDIS_URL="redis://:PASSWORD@HOST:6379"

// ─── Shared Constants ──────────────────────────────────────────────────────
const LOG_DATE_FORMAT = "YYYY-MM-DD HH:mm:ss Z";
const LOG_BASE        = "/opt/logs/pm2";       // centralized log directory
const NODE_ARGS       = "--max-old-space-size=2048 --expose-gc";

// ─── Tiered Restart Policies ───────────────────────────────────────────────
const RESTART_CRITICAL = { max_restarts: 10, restart_delay: 5000, min_uptime: "10s" };
const RESTART_AGENT    = { max_restarts: 5,  restart_delay: 5000, min_uptime: "10s" };
const RESTART_INFRA    = { max_restarts: 5,  restart_delay: 5000, min_uptime: "5s"  };
const RESTART_MANUAL   = { autorestart: false };  // for intentionally stopped services

// ─── Common Log Config ─────────────────────────────────────────────────────
function logConfig(serviceName) {
  return {
    error_file: `${LOG_BASE}/${serviceName}/error.log`,
    out_file:   `${LOG_BASE}/${serviceName}/out.log`,
    merge_logs: true,
    log_date_format: LOG_DATE_FORMAT,
  };
}

module.exports = {
  apps: [

    // ═══════════════════════════════════════════════════════════════════════
    //  TIER 1 — CRITICAL INFRASTRUCTURE
    // ═══════════════════════════════════════════════════════════════════════

    // ── 1. LiteLLM — LLM API Proxy (port 4049) ──────────────────────────
    //     OPTIMIZED: cluster mode (2 instances), memory cap 768M, Redis auth
    {
      name: "litellm",
      script: "litellm",
      args: "--port 4049 --host 0.0.0.0",
      cwd: "/opt/wheeler/services/litellm",
      interpreter: "python3",
      interpreter_args: "-m",
      exec_mode: "cluster",
      instances: 2,
      ...RESTART_CRITICAL,
      max_memory_restart: "768M",
      kill_timeout: 15000,
      wait_ready: true,
      listen_timeout: 30000,
      watch: false,
      autorestart: true,
      ...logConfig("litellm"),
      env: {
        NODE_ENV: "production",
        LITELLM_PORT: "4049",
        LITELLM_HOST: "0.0.0.0",
        LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}",
        LITELLM_TELEMETRY: "false",
        LITELLM_CACHE_TYPE: "redis",
        LITELLM_CACHE_REDIS_URL: "${REDIS_URL}",
        LITELLM_CACHE_REDIS_PASSWORD: "${REDIS_PASSWORD}",
        LITELLM_CACHE_TTL: "3600",
        LITELLM_LOG_LEVEL: "info",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        COREDB_HOST: "${COREDB_TAILSCALE}",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}",
        DEEPSEEK_API_KEY: "${DEEPSEEK_API_KEY}",
        GEMINI_API_KEY: "${GEMINI_API_KEY}",
        LITELLM_DATABASE_URL: "${DATABASE_URL}",
      },
      instance_var: "LITELLM_INSTANCE_ID",
    },

    // ── 2. FRGCRM API — Customer Relationship Management API (port 8082) ─
    //     OPTIMIZED: memory cap reduced 2G→1G, log path standardized
    {
      name: "frgcrm-api",
      cwd: "/opt/wheeler/apps/frgcrm/api",
      script: "/opt/wheeler/apps/frgcrm/venv/bin/python3",
      args: "-m uvicorn main:app --host 0.0.0.0 --port 8082 --workers 4",
      interpreter: "none",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_CRITICAL,
      max_memory_restart: "1G",
      kill_timeout: 15000,
      wait_ready: true,
      listen_timeout: 30000,
      watch: false,
      autorestart: true,
      ...logConfig("frgcrm-api"),
      env: {
        PYTHONUNBUFFERED: "1",
        NODE_ENV: "production",
        PORT: "8082",
        HOST: "0.0.0.0",
        DATABASE_URL: "${DATABASE_URL}",
        FRGCRM_DATABASE_URL: "postgresql://wheeler:${DB_PASSWORD}@${COREDB_TAILSCALE}:5432/wheeler_core",
        FRGCRM_REDIS_URL: "redis://${COREDB_TAILSCALE}:6379/1",
        REDIS_URL: "redis://${COREDB_TAILSCALE}:6379",
        COREDB_HOST: "${COREDB_TAILSCALE}",
        SECRET_KEY_BASE: "${FRGCRM_SECRET_KEY_BASE}",
        CORS_ORIGIN: "https://frgcrm.wheeler.ai",
        LITELLM_BASE_URL: "http://localhost:4049",
        LANGFUSE_HOST: "${LANGFUSE_HOST}",
        LOG_LEVEL: "info",
        STRIPE_SECRET_KEY: "${STRIPE_SECRET_KEY}",
        STRIPE_WEBHOOK_SECRET: "${STRIPE_WEBHOOK_SECRET}",
        OUTREACH_KILL_SWITCH: "${OUTREACH_KILL_SWITCH}",
        OUTREACH_DRY_RUN: "${OUTREACH_DRY_RUN}",
      },
    },

    // ── 3. OpenClaw Dashboard — Multi-agent monitoring dashboard (port 8110)
    //     OPTIMIZED: cluster mode (2 instances)
    {
      name: "openclaw-dashboard",
      cwd: "/opt/openclaw-dashboard",
      script: "server.js",
      exec_mode: "cluster",
      instances: 2,
      ...RESTART_AGENT,
      max_memory_restart: "256M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("openclaw-dashboard"),
      env: {
        NODE_ENV: "production",
        DASHBOARD_PORT: "8110",
        OPENCLAW_DIR: "/root/.openclaw",
        WORKSPACE_DIR: "/opt/openclaw-dashboard",
      },
      instance_var: "DASHBOARD_INSTANCE_ID",
    },

    // ═══════════════════════════════════════════════════════════════════════
    //  TIER 2 — INFRASTRUCTURE SERVICES
    // ═══════════════════════════════════════════════════════════════════════

    // ── 4. Ecosystem Guardian — PM2 health monitoring daemon ─────────────
    {
      name: "ecosystem-guardian",
      script: "lib/ecosystem-guardian.js",
      cwd: "/opt/apps/wheeler-brain-os",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_INFRA,
      max_memory_restart: "200M",
      kill_timeout: 5000,
      watch: false,
      autorestart: true,
      ...logConfig("ecosystem-guardian"),
      env: {
        NODE_ENV: "production",
        CHECK_INTERVAL_SEC: "60",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        COREDB_HOST: "${COREDB_TAILSCALE}",
      },
    },

    // ── 5. Event Bus Relay — Cross-service event routing ─────────────────
    //     OPTIMIZED: memory cap increased 150M→200M (66MB current, too close)
    {
      name: "event-bus-relay",
      script: "lib/events/relay.js",
      cwd: "/opt/apps/wheeler-brain-os",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_INFRA,
      max_memory_restart: "200M",
      kill_timeout: 5000,
      watch: false,
      autorestart: true,
      ...logConfig("event-bus-relay"),
      env: {
        NODE_ENV: "production",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        COREDB_HOST: "${COREDB_TAILSCALE}",
      },
    },

    // ── 6. Voice Outreach Service — Twilio-based outreach (no HTTP port) ─
    //     OPTIMIZED: memory cap added (was NOT SET)
    {
      name: "voice-outreach-service",
      script: "dist/server.js",
      cwd: "/opt/wheeler/services/voice-outreach",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "256M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("voice-outreach-service"),
      env: {
        PYTHONUNBUFFERED: "1",
        NODE_ENV: "production",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        COREDB_HOST: "${COREDB_TAILSCALE}",
        TWILIO_ACCOUNT_SID: "${TWILIO_ACCOUNT_SID}",
        TWILIO_AUTH_TOKEN: "${TWILIO_AUTH_TOKEN}",
        TWILIO_PHONE_NUMBER: "${TWILIO_PHONE_NUMBER}",
        LOG_LEVEL: "info",
      },
    },

    // ── 7. War Room Server — Real-time ops dashboard ─────────────────────
    //     OPTIMIZED: memory cap added (was NOT SET)
    {
      name: "war-room-server",
      script: "/opt/apps/war-room/start-with-env.sh",
      cwd: "/opt/apps/war-room",
      interpreter: "none",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "256M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("war-room-server"),
      env: {
        PYTHONUNBUFFERED: "1",
        NODE_ENV: "production",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        COREDB_HOST: "${COREDB_TAILSCALE}",
      },
    },

    // ═══════════════════════════════════════════════════════════════════════
    //  TIER 3 — AGENT SERVICES (polling-based, fork mode, single instance)
    //  OPTIMIZED: memory caps reduced 500M→400M (insforge→300M),
    //             tiered restart policy (agent=5)
    //  NOTE: NOT converted to cluster mode because polling-based agents
    //        would duplicate work and cause race conditions on shared state.
    // ═══════════════════════════════════════════════════════════════════════

    // ── 8. Design Agent Service (port 8020) ──────────────────────────────
    {
      name: "design-agent-svc",
      cwd: "/opt/apps/design-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("design-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8020",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "https://api.deepseek.com/v1",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 9. Horizon Agent Service (port 8006) ─────────────────────────────
    {
      name: "horizon-agent-svc",
      cwd: "/opt/apps/horizon-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("horizon-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8006",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "http://localhost:4049/v1",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 10. Paperless Agent Service (port 8009) ──────────────────────────
    {
      name: "paperless-agent-svc",
      cwd: "/opt/apps/paperless-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("paperless-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8009",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "http://localhost:4049/v1",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 11. Prediction Radar Agent Service (port 8011) ───────────────────
    {
      name: "prediction-radar-agent-svc",
      cwd: "/opt/apps/prediction-radar-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("prediction-radar-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8011",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "http://localhost:4049/v1",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 12. Ravyn Agent Service (port 8005) ──────────────────────────────
    {
      name: "ravyn-agent-svc",
      cwd: "/opt/apps/ravyn-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("ravyn-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8005",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "http://localhost:4049/v1",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 13. FRGCRM Agent Service (port 8003) ─────────────────────────────
    {
      name: "frgcrm-agent-svc",
      cwd: "/opt/apps/frgcrm-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("frgcrm-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8003",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "http://localhost:4049/v1",
        FRGCRM_API_URL: "http://localhost:8082",
        FRGCRM_INTERNAL_TOKEN: "${FRGCRM_INTERNAL_TOKEN}",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 14. Insforge Agent Service (port 8013) ───────────────────────────
    {
      name: "insforge-agent-svc",
      cwd: "/opt/apps/insforge-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "300M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("insforge-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8013",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        ANTHROPIC_BASE_URL: "https://api.deepseek.com/anthropic",
        INSFORGE_BASE_URL: "${INSFORGE_BASE_URL}",
        INSFORGE_API_KEY: "${INSFORGE_API_KEY}",
        POSTGREST_URL: "${POSTGREST_URL}",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 15. SurplusAI Scraper Agent Service (port 8007) ──────────────────
    {
      name: "surplusai-scraper-agent-svc",
      cwd: "/opt/apps/surplusai-scraper-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("surplusai-scraper-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8007",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "https://api.deepseek.com/v1",
        ANTHROPIC_BASE_URL: "https://api.deepseek.com/anthropic",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ── 16. Voice Agent Service (port 8008) ──────────────────────────────
    {
      name: "voice-agent-svc",
      cwd: "/opt/apps/voice-agent-svc",
      script: "./dist/index.js",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_AGENT,
      max_memory_restart: "400M",
      kill_timeout: 10000,
      watch: false,
      autorestart: true,
      ...logConfig("voice-agent-svc"),
      node_args: NODE_ARGS,
      env: {
        NODE_ENV: "production",
        PORT: "8008",
        POLLING_INTERVAL_MS: "300000",
        AGENT_MODEL: "deepseek-chat",
        OPENAI_API_KEY: "${OPENAI_API_KEY}",
        OPENAI_BASE_URL: "https://api.deepseek.com/v1",
        ANTHROPIC_BASE_URL: "https://api.deepseek.com/anthropic",
        DATABASE_URL: "${DATABASE_URL}",
        REDIS_URL: "${REDIS_URL}",
        LOG_LEVEL: "info",
      },
    },

    // ═══════════════════════════════════════════════════════════════════════
    //  TIER 4 — INTENTIONALLY STOPPED / MANUAL-RUN SERVICES
    // ═══════════════════════════════════════════════════════════════════════

    // ── 17. Backup Verification — Manual batch job ───────────────────────
    {
      name: "backup-verification",
      script: "dist/verify.js",
      cwd: "/opt/apps/backup-verification",
      exec_mode: "fork",
      instances: 1,
      ...RESTART_MANUAL,
      max_memory_restart: "256M",
      watch: false,
      ...logConfig("backup-verification"),
      env: {
        NODE_ENV: "production",
      },
    },
  ],

  // ─── PM2-Logrotate Configuration ──────────────────────────────────────
  // Applied via: pm2 set pm2-logrotate:<key> <value>
  //
  // Recommended settings (apply manually or via apply-optimizations.sh):
  //
  //   pm2 set pm2-logrotate:max_size 10M
  //   pm2 set pm2-logrotate:retain 30
  //   pm2 set pm2-logrotate:compress true
  //   pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
  //   pm2 set pm2-logrotate:workerInterval 30
  //   pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
  //   pm2 set pm2-logrotate:rotateModule true
  //
  // These ensure:
  //   - 10 MB max file size before rotation
  //   - 30 days of retained logs
  //   - gzip compression on rotated files
  //   - Daily rotation check at midnight
  //   - Module logs are also rotated
};
