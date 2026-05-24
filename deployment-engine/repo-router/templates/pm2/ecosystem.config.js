// =============================================================================
// Repo Router - PM2 Ecosystem File Template
// Source: templates/pm2/ecosystem.config.js
// Description: PM2 process definitions with watch config, env vars, error
//              handling, and log rotation for Wheeler services.
// =============================================================================

module.exports = {
  apps: [
    {
      name: process.env.PM2_APP_NAME || "wheeler-service",
      script: process.env.PM2_SCRIPT || "dist/server.js",
      cwd: process.env.PM2_CWD || "/opt/app/current",
      interpreter: process.env.PM2_INTERPRETER || "node",
      interpreter_args: process.env.PM2_INTERPRETER_ARGS || "",
      exec_mode: process.env.PM2_EXEC_MODE || "fork",
      instances: process.env.PM2_INSTANCES
        ? parseInt(process.env.PM2_INSTANCES, 10)
        : 1,
      max_restarts: 10,
      min_uptime: "30s",
      max_memory_restart: process.env.PM2_MAX_MEMORY || "512M",
      kill_timeout: 10000,
      listen_timeout: 15000,
      restart_delay: 5000,
      autorestart: true,
      cron_restart: process.env.PM2_CRON_RESTART || "",
      watch: process.env.PM2_WATCH === "true" ? ["src", "config"] : false,
      watch_delay: 1000,
      watch_options: {
        followSymlinks: false,
        usePolling: false,
      },
      env: {
        NODE_ENV: "production",
        PORT: process.env.PORT || "3000",
        LOG_LEVEL: process.env.LOG_LEVEL || "info",
      },
      env_staging: {
        NODE_ENV: "staging",
        LOG_LEVEL: "debug",
      },
      error_file: process.env.PM2_ERROR_LOG || "/var/log/pm2/wheeler-service-error.log",
      out_file: process.env.PM2_OUT_LOG || "/var/log/pm2/wheeler-service-out.log",
      log_file: process.env.PM2_COMBINED_LOG || "/var/log/pm2/wheeler-service-combined.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
      pid_file: process.env.PM2_PID_FILE || "/var/run/pm2/wheeler-service.pid",
      source_map_support: true,
      force: false,
      treekill: true,
      node_args: "--max-old-space-size=" + (process.env.PM2_HEAP_SIZE || "512"),
    },
    {
      name: (process.env.PM2_APP_NAME || "wheeler-service") + "-worker",
      script: process.env.PM2_WORKER_SCRIPT || "dist/worker.js",
      cwd: process.env.PM2_CWD || "/opt/app/current",
      exec_mode: "fork",
      instances: process.env.PM2_WORKER_INSTANCES
        ? parseInt(process.env.PM2_WORKER_INSTANCES, 10)
        : 2,
      max_restarts: 5,
      min_uptime: "15s",
      max_memory_restart: process.env.PM2_WORKER_MAX_MEMORY || "256M",
      kill_timeout: 15000,
      restart_delay: 10000,
      autorestart: true,
      env: {
        NODE_ENV: "production",
        WORKER_TYPE: "background",
        LOG_LEVEL: process.env.LOG_LEVEL || "info",
      },
      error_file: process.env.PM2_WORKER_ERROR_LOG || "/var/log/pm2/wheeler-worker-error.log",
      out_file: process.env.PM2_WORKER_OUT_LOG || "/var/log/pm2/wheeler-worker-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
    },
    {
      name: (process.env.PM2_APP_NAME || "wheeler-service") + "-scheduler",
      script: process.env.PM2_SCHEDULER_SCRIPT || "dist/scheduler.js",
      cwd: process.env.PM2_CWD || "/opt/app/current",
      exec_mode: "fork",
      instances: 1,
      max_restarts: 3,
      min_uptime: "10s",
      cron_restart: "0 0 * * *",
      autorestart: true,
      env: {
        NODE_ENV: "production",
        SCHEDULER_ENABLED: "true",
        LOG_LEVEL: process.env.LOG_LEVEL || "info",
      },
      error_file: process.env.PM2_SCHEDULER_ERROR_LOG || "/var/log/pm2/wheeler-scheduler-error.log",
      out_file: process.env.PM2_SCHEDULER_OUT_LOG || "/var/log/pm2/wheeler-scheduler-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,
    },
  ],

  deploy: {
    production: {
      user: process.env.DEPLOY_USER || "deploy",
      host: process.env.DEPLOY_HOST || "localhost",
      ref: "origin/main",
      repo: process.env.GIT_REPO || "",
      path: process.env.DEPLOY_PATH || "/opt/app",
      "post-deploy":
        "npm ci --production && " +
        "npm run build && " +
        "pm2 reload ecosystem.config.js --env production --update-env",
      "pre-setup": "mkdir -p /opt/app /var/log/pm2 /var/run/pm2",
    },
  },
};
