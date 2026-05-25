module.exports = {
  apps: [{
    name: "executive-dashboard-api",
    script: "main.py",
    interpreter: "python3",
    cwd: "/opt/apps/executive-dashboard-api",
    env: {
      PORT: "8180"
    },
    listen_timeout: 10000,
    kill_timeout: 5000,
    max_restarts: 5,
    restart_delay: 5000,
    error_file: "/var/log/wheeler/executive-dashboard-api-error.log",
    out_file: "/var/log/wheeler/executive-dashboard-api-out.log"
  }]
};
