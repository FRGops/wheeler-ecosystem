/**
 * Wheeler Platform — PM2 Ecosystem Configuration
 * ==============================================
 *
 * This is the canonical PM2 ecosystem file for all Wheeler services.
 * It defines three service groups, each tailored to its runtime and workload.
 *
 * Deploy Commands:
 *   pm2 start ecosystem.config.js --env production     # all services, prod
 *   pm2 start ecosystem.config.js --env staging        # all services, staging
 *   pm2 start ecosystem.config.js --only wheeler-api-production
 *   pm2 reload ecosystem.config.js                     # zero-downtime rolling restart
 *   pm2 save --force                                   # persist across reboots
 *
 * Monitoring:
 *   pm2 status           # compact table of all processes
 *   pm2 monit             # ncurses dashboard
 *   pm2 logs              # tail all logs
 *   pm2 logs <app-name>   # tail one service
 *
 * Server Topology (3-node Wheeler cluster):
 *   EDGE   (187.77.148.88)  — wheeler-api, wheeler-litellm
 *   AIOPS  (5.78.140.118)   — wheeler-ai-worker
 *   COREDB (5.78.210.123)   — PostgreSQL + Redis (no PM2; runs via Docker/systemd)
 *
 * Internal networking is over the Tailscale mesh (100.x.y.z addresses).
 * COREDB_TAILSCALE is injected at deploy time via the host environment.
 */

// =============================================================================
// CONSTANTS — Shared across all service definitions
// =============================================================================

const LOG_DATE_FORMAT = 'YYYY-MM-DD HH:mm:ss Z';

// COREDB is the single source of truth for stateful data.  All services
// reach it over the Tailscale mesh for encrypted, WireGuard-backed transport.
const COREDB_HOST = process.env.COREDB_TAILSCALE || '100.118.166.117';

// =============================================================================
// APP DEFINITIONS
// =============================================================================

module.exports = {
  apps: [

    // =========================================================================
    // SECTION 1 — Node.js API Services
    // =========================================================================
    //
    // The REST API layer (Express / Fastify / Hono).  These services are
    // stateless — session data, caches, and queues are external (Redis on
    // COREDB).  They run in cluster mode to saturate all available vCPUs on
    // the EDGE node (typically 4 vCPUs, giving 4 workers).
    //
    // Cluster mode uses the Node.js cluster module under the hood:
    //   - The master process binds the port.
    //   - Incoming connections are distributed round-robin to workers.
    //   - pm2 reload replaces workers one-by-one for zero-downtime deploys.
    //
    // Tuning guidance:
    //   - instances: 'max'  — one worker per logical CPU core.
    //   - If the EDGE node has other workloads, set instances to a fixed
    //     number (e.g., 2) to leave headroom.
    //   - max_memory_restart is a safety net, not a memory budget.  If a
    //     service routinely exceeds 400M RSS, investigate for leaks first.
    // =========================================================================
    {
      // ── Identification ──────────────────────────────────────────────────
      name: 'wheeler-api-${env}',
        // The ${env} suffix is interpolated by PM2 from the --env flag.
        // With --env production  →  name becomes  wheeler-api-production
        // With --env staging     →  name becomes  wheeler-api-staging

      // ── Entry Point ─────────────────────────────────────────────────────
      script: './dist/server.js',
        // Compiled TypeScript output.  Assumes tsconfig outDir is 'dist'.
        // For plain JS projects this would be './src/server.js'.

      cwd: '/opt/wheeler/api',
        // Absolute path to the service root.  All relative paths (script,
        // log files) are resolved from here.

      // ── Runtime Mode ────────────────────────────────────────────────────
      exec_mode: 'cluster',
      instances: 'max',
        // Cluster mode with max instances.  Each worker is a full Node.js
        // process; all share the same port via the cluster master's socket
        // handoff (SO_REUSEPORT on Linux).

      // ── Watch ───────────────────────────────────────────────────────────
      watch: false,
        // NEVER enable watch in production.  File-watching is CPU-intensive
        // and can trigger spurious restarts.  Use CI/CD to deploy new code.

      // ── Restart Policy ──────────────────────────────────────────────────
      autorestart: true,
      max_restarts: 10,
        // Max 10 restarts within the rolling window (restart_delay * max_restarts
        // ≈ 50 s).  Exceeding this puts the process into 'errored' state.

      restart_delay: 5000,
        // 5-second cooldown between restart attempts.  Prevents tight restart
        // loops from saturating CPU and log I/O.

      min_uptime: '10s',
        // A process that exits before 10 s of uptime is considered a "fast
        // crash" and its restart counts toward max_restarts.  A process that
        // survives 10 s resets the counter.

      max_memory_restart: '512M',
        // If RSS exceeds 512 MiB, PM2 sends SIGTERM and restarts the worker.
        // This is set at 125 % of normal peak memory (~400 MiB for this API).
        // If you observe frequent memory-triggered restarts, investigate for
        // memory leaks or increase this limit (1G max for API services).

      // ── Startup / Shutdown Timeouts ─────────────────────────────────────
      listen_timeout: 10000,
        // Wait up to 10 s for the worker to bind its port and emit 'ready'.
        // If the worker does not call process.send('ready') within this window,
        // PM2 considers startup failed and triggers a restart.

      kill_timeout: 10000,
        // After sending SIGTERM, PM2 waits 10 s for the process to exit
        // gracefully before escalating to SIGKILL.  The application's SIGTERM
        // handler MUST finish within this window — close DB pools, flush logs,
        // stop accepting connections, and call process.exit(0).

      // ── Logging ─────────────────────────────────────────────────────────
      error_file: '/var/log/wheeler/pm2/api-error.log',
      out_file: '/var/log/wheeler/pm2/api-out.log',
      merge_logs: true,
        // All cluster workers write to the same pair of log files.  This is
        // simpler for log shippers (Promtail) and `pm2 logs`.
        // Set to false if you need per-worker log isolation for debugging.

      log_date_format: LOG_DATE_FORMAT,
        // ISO-8601 compatible: 2026-05-23 14:30:00 +0000

      // ── Health Check ────────────────────────────────────────────────────
      wait_ready: true,
        // PM2 waits for process.send('ready') before marking the worker
        // online.  Your server.js MUST call this after listen() succeeds:
        //
        //   app.listen(port, () => {
        //     console.log(`Listening on :${port}`);
        //     process.send('ready');
        //   });

      instance_var: 'INSTANCE_ID',
        // Each worker gets INSTANCE_ID injected: '0', '1', '2', ...
        // Useful for differentiating workers in logs and metrics.

      // ── Environment — Production ────────────────────────────────────────
      env: {
        NODE_ENV: 'production',
        PORT: 3001,
        HEALTH_CHECK_PORT: 3001,
        HEALTH_CHECK_PATH: '/health',
        COREDB_HOST: COREDB_HOST,
        // Additional env vars (DB_URL, API_KEYS) are injected by the host
        // environment or a .env file sourced before PM2 starts.
      },

      // ── Environment — Staging ───────────────────────────────────────────
      env_staging: {
        NODE_ENV: 'staging',
        PORT: 3001,
        HEALTH_CHECK_PORT: 3001,
        HEALTH_CHECK_PATH: '/health',
        COREDB_HOST: COREDB_HOST,
        instances: 1,
        exec_mode: 'fork',
        // Staging uses a single fork-mode instance for simpler debugging.
        // Memory and restart limits are inherited from the top-level keys.
      }
    },

    // =========================================================================
    // SECTION 2 — Python AI Workers
    // =========================================================================
    //
    // Long-running Python processes for AI inference, model serving, and
    // async task processing.  Each worker loads models into RAM (or GPU
    // memory) and exposes a lightweight HTTP endpoint consumed by the API
    // layer or Brain OS orchestration engine.
    //
    // Key differences from Node.js services:
    //   - exec_mode: 'fork'  — Python does NOT use the Node.js cluster module.
    //     fork mode launches independent OS processes (one per instance).
    //   - interpreter: 'python3'  — or an absolute path to a virtualenv python.
    //   - Higher memory limit and longer timeouts because model loading is
    //     slow and memory-heavy.
    //
    // Tuning guidance:
    //   - instances: 2  — two independent workers.  Beyond this the Python GIL
    //     limits throughput gains unless the workload is purely I/O-bound.
    //     For CPU-bound inference, pin workers to specific cores.
    //   - PYTHONUNBUFFERED=1  — critical.  Without this stdout/stderr is block-
    //     buffered and logs can be delayed by minutes, making debugging
    //     nearly impossible.
    // =========================================================================
    {
      // ── Identification ──────────────────────────────────────────────────
      name: 'wheeler-ai-worker-${env}',

      // ── Entry Point ─────────────────────────────────────────────────────
      script: 'main.py',
        // The Python script that bootstraps the worker: loads models, starts
        // the HTTP or gRPC server, and emits a health signal.

      interpreter: 'python3',
        // Use the system python3.  For virtualenv isolation, point to the
        // venv binary:  /opt/wheeler/venvs/ai-worker/bin/python
        // A wrapper script (/opt/wheeler/scripts/run-ai-worker.sh) is another
        // option — it can activate the venv and set env vars before exec.

      cwd: '/opt/wheeler/ai-worker',

      // ── Runtime Mode ────────────────────────────────────────────────────
      exec_mode: 'fork',
      instances: 2,
        // Two independent worker processes, each binding a different port
        // (WORKER_PORT + instance index) or fronted by an internal proxy.

      // ── Watch ───────────────────────────────────────────────────────────
      watch: false,

      // ── Restart Policy ──────────────────────────────────────────────────
      autorestart: true,
      max_restarts: 5,
        // Lower than the API because model-load failures (OOM, corrupted
        // weights, GPU driver issues) should not loop indefinitely.

      restart_delay: 10000,
        // 10 s cooldown.  Model loading is expensive; rapid restarts would
        // waste CPU and I/O rereading weights from disk.

      min_uptime: '15s',
        // Startup includes model warm-up, so 15 s is a realistic threshold
        // before the process is considered "stable."

      max_memory_restart: '2G',
        // 2 GiB accommodates typical model weights (7B-13B parameter LLMs,
        // embedding models, classifier ensembles).  Adjust upward for 70B+
        // models or combined pipelines.

      // ── Startup / Shutdown Timeouts ─────────────────────────────────────
      kill_timeout: 15000,
        // 15 s for graceful shutdown: finish in-flight inference requests,
        // flush prediction caches, close DB connections.

      listen_timeout: 30000,
        // 30 s for startup.  Model loading from disk (especially over NFS or
        // object storage) can take 20-30 s for large models.

      // ── Logging ─────────────────────────────────────────────────────────
      error_file: '/var/log/wheeler/pm2/ai-worker-error.log',
      out_file: '/var/log/wheeler/pm2/ai-worker-out.log',
      merge_logs: true,
      log_date_format: LOG_DATE_FORMAT,

      // ── Health Check ────────────────────────────────────────────────────
      wait_ready: true,
        // The Python worker should signal readiness by writing to a file or
        // calling a small HTTP endpoint.  A wrapper script can poll and then
        // send the PM2 ready signal.

      // ── Environment — Production ────────────────────────────────────────
      env: {
        PYTHONUNBUFFERED: '1',
          // Disable stdout/stderr buffering.  Without this, logs are held in
          // a 4 KiB buffer and may not appear for minutes under low volume.
        WORKER_PORT: 3002,
        HEALTH_CHECK_PORT: 3002,
        COREDB_HOST: COREDB_HOST,
        LOG_LEVEL: 'INFO',
      },

      // ── Environment — Staging ───────────────────────────────────────────
      env_staging: {
        PYTHONUNBUFFERED: '1',
        WORKER_PORT: 3002,
        HEALTH_CHECK_PORT: 3002,
        COREDB_HOST: COREDB_HOST,
        LOG_LEVEL: 'DEBUG',
        instances: 1,
      }
    },

    // =========================================================================
    // SECTION 3 — LiteLLM Proxy
    // =========================================================================
    //
    // LiteLLM is a unified proxy that sits in front of multiple LLM providers
    // (OpenAI, Anthropic, Azure OpenAI, local vLLM, Ollama, etc.).  It:
    //   - Normalizes all provider APIs to a single OpenAI-compatible interface.
    //   - Handles rate limiting, retries, and failover.
    //   - Provides cost tracking and usage analytics.
    //   - Supports load balancing across multiple instances of the same model.
    //
    // LiteLLM is I/O-bound (proxying HTTP requests), so a single instance is
    // sufficient.  The proxy itself is stateless — API keys and configuration
    // live in /opt/wheeler/litellm/config.yaml.
    //
    // Tuning guidance:
    //   - instances: 1  — one proxy is enough for most workloads.  Scale out
    //     behind a load balancer if you exceed ~500 concurrent requests.
    //   - max_memory_restart: '1G'  — covers model metadata caching, response
    //     buffering, and connection pooling.  LiteLLM is not memory-heavy.
    //   - The --config flag refers to /opt/wheeler/litellm/config.yaml, which
    //     contains model definitions, routing rules, and API key references.
    //     API keys themselves should be set as environment variables (e.g.,
    //     OPENAI_API_KEY) and NOT hardcoded in the config file.
    // =========================================================================
    {
      // ── Identification ──────────────────────────────────────────────────
      name: 'wheeler-litellm-${env}',

      // ── Entry Point ─────────────────────────────────────────────────────
      script: 'litellm',
        // LiteLLM is installed as a Python package and exposes a CLI entry
        // point.  PM2 calls it via the python3 interpreter.

      args: '--config /opt/wheeler/litellm/config.yaml --port 4000',
        // --config points to the YAML model definition file.
        // --port 4000 is the standard LiteLLM port.

      interpreter: 'python3',
      cwd: '/opt/wheeler/litellm',

      // ── Runtime Mode ────────────────────────────────────────────────────
      exec_mode: 'fork',
      instances: 1,

      // ── Watch ───────────────────────────────────────────────────────────
      watch: false,

      // ── Restart Policy ──────────────────────────────────────────────────
      autorestart: true,
      max_restarts: 5,
      restart_delay: 10000,
      min_uptime: '10s',
      max_memory_restart: '1G',

      // ── Startup / Shutdown Timeouts ─────────────────────────────────────
      kill_timeout: 15000,
        // Allow 15 s for in-flight streaming responses to complete before
        // forcefully terminating the proxy.
      listen_timeout: 15000,

      // ── Logging ─────────────────────────────────────────────────────────
      error_file: '/var/log/wheeler/pm2/litellm-error.log',
      out_file: '/var/log/wheeler/pm2/litellm-out.log',
      merge_logs: true,
      log_date_format: LOG_DATE_FORMAT,

      // ── Health Check ────────────────────────────────────────────────────
      wait_ready: false,
        // LiteLLM does not emit a PM2-ready signal natively.  The listen_timeout
        // window is sufficient to confirm the port is open.  For an explicit
        // check, wrap litellm in a shell script that polls :4000/health before
        // exiting with code 0.

      // ── Environment — Production ────────────────────────────────────────
      env: {
        LITELLM_LOG: 'INFO',
        LITELLM_MASTER_KEY: process.env.LITELLM_MASTER_KEY || '',
        // API keys for upstream providers (OpenAI, Anthropic, etc.) are
        // injected by the host environment.  The config.yaml references them
        // via os.environ[...] syntax.
        OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || '',
      },

      // ── Environment — Staging ───────────────────────────────────────────
      env_staging: {
        LITELLM_LOG: 'DEBUG',
        LITELLM_MASTER_KEY: process.env.LITELLM_MASTER_KEY || '',
        OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || '',
      }
    }
  ],

  // =========================================================================
  // DEPLOY CONFIGURATION (optional — used by `pm2 deploy`)
  // =========================================================================
  //
  // Uncomment and configure for git-based deploys:
  //
  // deploy: {
  //   production_edge: {
  //     user: 'wheeler',
  //     host: '187.77.148.88',
  //     ref: 'origin/main',
  //     repo: 'git@github.com:wheeler/platform.git',
  //     path: '/opt/wheeler/api',
  //     'post-deploy': 'npm ci && npm run build && pm2 reload ecosystem.config.js --env production',
  //   },
  //   production_aiops: {
  //     user: 'wheeler',
  //     host: '5.78.140.118',
  //     ref: 'origin/main',
  //     repo: 'git@github.com:wheeler/platform.git',
  //     path: '/opt/wheeler/ai-worker',
  //     'post-deploy': 'pip install -r requirements.txt && pm2 reload ecosystem.config.js --env production --only wheeler-ai-worker-production',
  //   },
  // }
};
