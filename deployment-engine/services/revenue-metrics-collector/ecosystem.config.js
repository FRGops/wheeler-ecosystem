module.exports = {
  apps: [{
    name: "revenue-metrics-collector",
    script: "main.py",
    interpreter: "python3",
    cwd: "/opt/apps/revenue-metrics-collector",
    env: {
      PORT: "8170"
    },
    listen_timeout: 10000,
    kill_timeout: 5000,
    max_restarts: 5,
    restart_delay: 5000,
    error_file: "/var/log/wheeler/revenue-metrics-collector-error.log",
    out_file: "/var/log/wheeler/revenue-metrics-collector-out.log"
  }]
};
