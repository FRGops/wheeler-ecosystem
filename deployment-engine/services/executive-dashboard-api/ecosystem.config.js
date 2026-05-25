module.exports = {
  apps: [{
    name: "executive-dashboard-api",
    script: "main.py",
    interpreter: "python3",
    cwd: "/opt/apps/executive-dashboard-api",
    env: {
      PORT: "8180",
      NEO4J_URI: "bolt://127.0.0.1:7687",
      NEO4J_USER: "neo4j",
      NEO4J_PASSWORD: "WheelerBrainOS-Graph-2026!-Neo4j-Root"
    },
    listen_timeout: 10000,
    kill_timeout: 5000,
    max_restarts: 5,
    restart_delay: 5000,
    error_file: "/var/log/wheeler/executive-dashboard-api-error.log",
    out_file: "/var/log/wheeler/executive-dashboard-api-out.log"
  }]
};
