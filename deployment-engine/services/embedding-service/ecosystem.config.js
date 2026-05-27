module.exports = {
  apps: [{
    name: "embedding-service",
    script: "main.py",
    interpreter: "python3",
    cwd: "/opt/apps/embedding-service",
    env: {
      PORT: "8191"
    },
    listen_timeout: 30000,
    kill_timeout: 10000,
    max_memory_restart: '1G',
    max_restarts: 5,
    restart_delay: 5000,
    error_file: "/var/log/wheeler/embedding-service-error.log",
    out_file: "/var/log/wheeler/embedding-service-out.log"
  }]
};
