module.exports = {
  apps: [{
    name: "aiops-saas-api",
    script: "main.py",
    interpreter: "python3",
    cwd: "/opt/apps/aiops-saas-api",
    env: {
      PORT: "8150"
    },
    listen_timeout: 10000,
    kill_timeout: 5000,
    max_restarts: 5,
    restart_delay: 5000,
    error_file: "/var/log/wheeler/aiops-saas-api-error.log",
    out_file: "/var/log/wheeler/aiops-saas-api-out.log"
  }]
};
