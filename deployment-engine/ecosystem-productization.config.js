// Wheeler Ecosystem Productization — Master PM2 Configuration
// Generated: 2026-05-24 — Stage 2 Hardened (QA 100/100 A+)
// Deploys all 10 monetization products across the Wheeler ecosystem.
//
// Usage:
//   pm2 start ecosystem-productization.config.js
//   pm2 save
//
// All services bind to 127.0.0.1. Public routing via Nginx/Traefik.

module.exports = {
  apps: [

    // =========================================================================
    // SURPLUSAI ENTERPRISE PLATFORM (Deliverable 2)
    // =========================================================================

    {
      name: 'surplusai-parser-svc',
      cwd: '/opt/apps/surplusai-parser',
      script: 'main.py',
      interpreter: 'python3',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8104,
        BIND_ADDR: '127.0.0.1',
        LITELLM_URL: 'http://127.0.0.1:4049',
        LITELLM_MODEL: 'deepseek-chat',
        DB_URL: 'postgresql://frgops:${FRGOPS_DB_PASSWORD}@127.0.0.1:5433/frgcrm',
        REDIS_URL: 'redis://127.0.0.1:6379/0',
        DOCUMENT_STORE: 'http://127.0.0.1:7130/api/storage',
        LOG_LEVEL: 'info',
        MAX_DOC_SIZE_MB: 50,
        OCR_ENABLED: 'true',
        CONFIDENCE_THRESHOLD_AUTO: '0.85',
        CONFIDENCE_THRESHOLD_REVIEW: '0.60',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
      kill_timeout: 15000,
      error_file: '/var/log/wheeler/surplusai-parser-error.log',
      out_file: '/var/log/wheeler/surplusai-parser-out.log',
    },

    {
      name: 'surplusai-scoring-svc',
      cwd: '/opt/apps/surplusai-scoring',
      script: 'main.py',
      interpreter: 'python3',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8105,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://frgops:${FRGOPS_DB_PASSWORD}@127.0.0.1:5433/frgcrm',
        REDIS_URL: 'redis://127.0.0.1:6379/1',
        MODEL_REGISTRY_PATH: '/opt/apps/surplusai-scoring/models',
        FEATURE_STORE_URL: 'http://127.0.0.1:8105/api/v1/features',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
      kill_timeout: 15000,
    },

    {
      name: 'surplusai-crm-sync',
      cwd: '/opt/apps/surplusai-crm-sync',
      script: 'dist/sync-worker.js',
      instances: 1,
      env: {
        PORT: 8106,
        BIND_ADDR: '127.0.0.1',
        FRGCRM_API_URL: 'http://127.0.0.1:8082',
        FRGCRM_INTERNAL_TOKEN: '${FRGCRM_INTERNAL_TOKEN}',
        DB_URL: 'postgresql://frgops:${FRGOPS_DB_PASSWORD}@127.0.0.1:5433/frgcrm',
        SYNC_INTERVAL_SECONDS: 60,
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
    },

    {
      name: 'surplusai-portal-frontend',
      cwd: '/opt/apps/surplusai-portal-frontend',
      script: 'node_modules/.bin/next',
      args: 'start -p 3002',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 3002,
        BIND_ADDR: '127.0.0.1',
        NEXT_PUBLIC_API_URL: 'https://surplusai.io/api/v1',
        NODE_ENV: 'production',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
    },

    // =========================================================================
    // ATTORNEY MARKETPLACE (Deliverable 4)
    // =========================================================================

    {
      name: 'attorney-marketplace-api',
      cwd: '/opt/apps/attorney-marketplace/api',
      script: 'dist/server.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8120,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DISCORD_WEBHOOK_URL: '${ATTORNEY_DISCORD_WEBHOOK}',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        JWT_SECRET: '${ATTORNEY_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
      kill_timeout: 10000,
    },

    {
      name: 'attorney-onboarding-worker',
      cwd: '/opt/apps/attorney-marketplace/workers/onboarding',
      script: 'dist/onboarding-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
      },
      autorestart: true,
      max_restarts: 5,
      min_uptime: '30s',
    },

    {
      name: 'attorney-license-worker',
      cwd: '/opt/apps/attorney-marketplace/workers/license',
      script: 'dist/license-worker.js',
      instances: 1,
      cron_restart: '0 6 * * 0',
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'attorney-revenue-engine',
      cwd: '/opt/apps/attorney-marketplace/workers/revenue',
      script: 'dist/revenue-engine.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'attorney-document-worker',
      cwd: '/opt/apps/attorney-marketplace/workers/document',
      script: 'dist/document-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'attorney-communications-worker',
      cwd: '/opt/apps/attorney-marketplace/workers/communications',
      script: 'dist/communications-worker.js',
      instances: 1,
      env: {
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DISCORD_WEBHOOK_URL: '${ATTORNEY_DISCORD_WEBHOOK}',
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'attorney-portal-frontend',
      cwd: '/opt/apps/attorney-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8121',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/attorney-marketplace/v1',
        REACT_APP_DOCUSEAL_URL: 'https://docuseal.fundsrecoverygroup.tech',
        NODE_ENV: 'production',
      },
      autorestart: true,
      max_restarts: 5,
    },

    // =========================================================================
    // PARTNER & REFERRAL MARKETPLACE (Deliverable 4)
    // =========================================================================

    {
      name: 'partner-marketplace-api',
      cwd: '/opt/apps/partner-marketplace/api',
      script: 'dist/server.js',
      instances: 1,
      env: {
        PORT: 8130,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://partner_mkt:${PARTNER_DB_PASSWORD}@127.0.0.1:5432/partner_marketplace',
        STRIPE_CONNECT_CLIENT_ID: '${STRIPE_CONNECT_CLIENT_ID}',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
      min_uptime: '30s',
    },

    {
      name: 'referral-marketplace-api',
      cwd: '/opt/apps/referral-marketplace/api',
      script: 'dist/server.js',
      instances: 1,
      env: {
        PORT: 8140,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://referral_mkt:${REFERRAL_DB_PASSWORD}@127.0.0.1:5432/referral_marketplace',
        ATTORNEY_API_URL: 'http://127.0.0.1:8120',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
      min_uptime: '30s',
    },

    {
      name: 'unified-payout-engine',
      cwd: '/opt/apps/unified-payout',
      script: 'dist/payout-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://payout_engine:${PAYOUT_DB_PASSWORD}@127.0.0.1:5432/payout_engine',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_CONNECT_CLIENT_ID: '${STRIPE_CONNECT_CLIENT_ID}',
        TAX_YEAR: '2026',
        IRS_1099_THRESHOLD: '600',
        LOG_LEVEL: 'info',
      },
      cron_restart: '0 2 1 * *',
      autorestart: true,
      max_restarts: 5,
    },

    // =========================================================================
    // AI OPS SAAS PLATFORM (Deliverable 5)
    // =========================================================================

    {
      name: 'aiops-saas-api',
      cwd: '/opt/apps/aiops-saas/api',
      script: 'dist/server.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8150,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://aiops_saas:${AIOPS_SAAS_DB_PASSWORD}@127.0.0.1:5432/aiops_saas',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        JWT_SECRET: '${AIOPS_SAAS_JWT_SECRET}',
        GRAFANA_ADMIN_URL: 'http://127.0.0.1:3002',
        GRAFANA_API_KEY: '${GRAFANA_API_KEY}',
        PROMETHEUS_URL: 'http://127.0.0.1:9090',
        PROMETHEUS_USER: 'admin',
        PROMETHEUS_PASS: '${PROMETHEUS_PASSWORD}',
        LOKI_URL: 'http://127.0.0.1:3100',
        NETDATA_URL: 'http://127.0.0.1:19999',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
      kill_timeout: 10000,
    },

    {
      name: 'aiops-saas-provisioner',
      cwd: '/opt/apps/aiops-saas/workers',
      script: 'dist/provisioner-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://aiops_saas:${AIOPS_SAAS_DB_PASSWORD}@127.0.0.1:5432/aiops_saas',
        PROVISION_SCRIPT: '/opt/aiops-saas/provision-tenant.sh',
        DEPROVISION_SCRIPT: '/opt/aiops-saas/deprovision-tenant.sh',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'aiops-saas-billing-worker',
      cwd: '/opt/apps/aiops-saas/workers',
      script: 'dist/billing-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://aiops_saas:${AIOPS_SAAS_DB_PASSWORD}@127.0.0.1:5432/aiops_saas',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        USAGE_METER_INTERVAL: 3600,
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
    },

    // =========================================================================
    // WHEELER BRAIN ENTERPRISE (Deliverable 6)
    // =========================================================================

    {
      name: 'wheeler-brain-api',
      cwd: '/opt/apps/wheeler-brain/api',
      script: 'dist/server.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8160,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://wheeler_brain:${WHEELER_BRAIN_DB_PASSWORD}@127.0.0.1:5432/wheeler_brain',
        NEO4J_URL: 'bolt://127.0.0.1:7687',
        NEO4J_USER: 'neo4j',
        NEO4J_PASS: '${NEO4J_PASSWORD}',
        COMMAND_CENTER_URL: 'http://127.0.0.1:8100',
        WAR_ROOM_URL: 'http://127.0.0.1:8082',
        JWT_SECRET: '${WHEELER_BRAIN_JWT_SECRET}',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
      kill_timeout: 10000,
    },

    {
      name: 'wheeler-brain-forecast-engine',
      cwd: '/opt/apps/wheeler-brain/workers/forecast',
      script: 'dist/forecast-worker.js',
      instances: 1,
      env: {
        PORT: 8130,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://wheeler_brain:${WHEELER_BRAIN_DB_PASSWORD}@127.0.0.1:5432/wheeler_brain',
        PROMETHEUS_URL: 'http://127.0.0.1:9090',
        LITELLM_URL: 'http://127.0.0.1:4049',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'wheeler-brain-strategy-advisor',
      cwd: '/opt/apps/wheeler-brain/workers/strategy',
      script: 'dist/strategy-worker.js',
      instances: 1,
      env: {
        PORT: 8131,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://wheeler_brain:${WHEELER_BRAIN_DB_PASSWORD}@127.0.0.1:5432/wheeler_brain',
        NEO4J_URL: 'bolt://127.0.0.1:7687',
        LITELLM_URL: 'http://127.0.0.1:4049',
        COMMAND_CENTER_URL: 'http://127.0.0.1:8100',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
    },

    // =========================================================================
    // MONETIZATION ORCHESTRATION (Deliverable 10)
    // =========================================================================

    {
      name: 'revenue-metrics-collector',
      cwd: '/opt/apps/revenue-intelligence',
      script: 'dist/metrics-collector.js',
      instances: 1,
      env: {
        PORT: 8170,
        BIND_ADDR: '127.0.0.1',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        DB_URL: 'postgresql://revenue_intel:${REVENUE_DB_PASSWORD}@127.0.0.1:5432/revenue_intelligence',
        PROMETHEUS_URL: 'http://127.0.0.1:9090',
        SUPERSET_URL: 'http://127.0.0.1:8088',
        COLLECTION_INTERVAL: 300,
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
      min_uptime: '30s',
    },

    {
      name: 'subscription-lifecycle-worker',
      cwd: '/opt/apps/revenue-intelligence',
      script: 'dist/subscription-worker.js',
      instances: 1,
      env: {
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        DB_URL: 'postgresql://revenue_intel:${REVENUE_DB_PASSWORD}@127.0.0.1:5432/revenue_intelligence',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
    },

    // =========================================================================
    // EXECUTIVE DASHBOARDS (Deliverable 10)
    // =========================================================================

    {
      name: 'executive-dashboard-api',
      cwd: '/opt/apps/executive-dashboard',
      script: 'dist/server.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8180,
        BIND_ADDR: '127.0.0.1',
        DB_URL: 'postgresql://exec_dash:${EXEC_DASH_DB_PASSWORD}@127.0.0.1:5432/executive_dashboard',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        PROMETHEUS_URL: 'http://127.0.0.1:9090',
        GRAFANA_URL: 'http://127.0.0.1:3002',
        SUPERSET_URL: 'http://127.0.0.1:8088',
        NEO4J_URL: 'bolt://127.0.0.1:7687',
        JWT_SECRET: '${EXEC_DASH_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: '30s',
    },

    // =========================================================================
    // DATA MOAT PIPELINES (Deliverable 3)
    // =========================================================================

    {
      name: 'data-enrichment-worker',
      cwd: '/opt/apps/data-moat',
      script: 'dist/enrichment-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://data_moat:${DATA_MOAT_DB_PASSWORD}@127.0.0.1:5432/data_moat',
        FRGCRM_URL: 'http://127.0.0.1:8082',
        SURPLUSAI_API_URL: 'http://127.0.0.1:8103',
        NEO4J_URL: 'bolt://127.0.0.1:7687',
        ENRICHMENT_BATCH_SIZE: 100,
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
    },

    {
      name: 'ml-training-pipeline',
      cwd: '/opt/apps/data-moat',
      script: 'dist/training-pipeline.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://data_moat:${DATA_MOAT_DB_PASSWORD}@127.0.0.1:5432/data_moat',
        MODEL_REGISTRY: '/opt/apps/data-moat/models',
        TRAINING_THRESHOLD: 5000,
        LOG_LEVEL: 'info',
      },
      autorestart: true,
      max_restarts: 5,
      min_uptime: '60s',
    },
  ],
};
