module.exports = {
  apps: [{
    name: "executive-dashboard-api",
    script: "run.sh",
    interpreter: "none",
    cwd: "/opt/apps/executive-dashboard-api",
    env: {
      PATH: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      PYTHONUNBUFFERED: "1",
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
