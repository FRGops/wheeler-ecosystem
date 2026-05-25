module.exports = {
  apps: [{
    name: 'litellm',
    script: 'run.sh',
    interpreter: 'none',
    cwd: '/opt/apps/litellm',
    env: {
      PATH: '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      PYTHONUNBUFFERED: '1',
      REDIS_HOST: '127.0.0.1',
      REDIS_PORT: '6379'
    },
    autorestart: true,
    max_restarts: 10,
    restart_delay: 5000,
    max_memory_restart: '1G',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    error_file: '/root/.pm2/logs/litellm-error.log',
    out_file: '/root/.pm2/logs/litellm-out.log',
    merge_logs: true,
  }],
};
