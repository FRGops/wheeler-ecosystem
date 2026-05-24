module.exports = {
  apps: [{
    name: "wheeler-brain-api",
    script: "main.py",
    interpreter: "python3",
    cwd: "/opt/apps/wheeler-brain-api",
    env: {
      PORT: "8160",
      NEO4J_URI: "bolt://127.0.0.1:7687",
      NEO4J_USER: "neo4j"
    },
    listen_timeout: 10000,
    kill_timeout: 5000,
    max_restarts: 5,
    restart_delay: 5000,
    error_file: "/var/log/wheeler/wheeler-brain-api-error.log",
    out_file: "/var/log/wheeler/wheeler-brain-api-out.log"
  }]
};
