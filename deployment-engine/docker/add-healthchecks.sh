#!/bin/bash
# ==============================================================================
# Docker HEALTHCHECK Remediation Script
# Fixes: coredb-redis-exporter (no HEALTHCHECK, scratch image)
#        coredb-postgres-exporter (no HEALTHCHECK)
#
# Strategy:
#   - coredb-redis-exporter: Recreate with alpine variant (has shell/wget)
#     and add HEALTHCHECK hitting :9121/metrics
#   - coredb-postgres-exporter: Recreate with same image + HEALTHCHECK
#     hitting :9187/metrics (wget already available)
#
# Uses Python to extract config and build safe docker run commands to
# avoid shell escaping issues with special characters in env vars.
# ==============================================================================
set -euo pipefail

LOG_FILE="/root/deployment-engine/logs/docker-healthcheck-fix.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_ENV_FILE="/tmp/docker-healthcheck-env-$$.txt"

cleanup() {
    rm -f "$TMP_ENV_FILE"
}
trap cleanup EXIT

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "Docker HEALTHCHECK Fix — $TIMESTAMP"
echo "=============================================="

# ---- PHASE 1: Pre-flight --------------------------------------------------
echo ""
echo "--- PHASE 1: Pre-flight ---"

echo "Current HEALTHCHECK state:"
docker inspect coredb-redis-exporter coredb-postgres-exporter 2>/dev/null | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    hc = c['Config'].get('Healthcheck', None)
    name = c['Name'].lstrip('/')
    status = c['State']['Status']
    print(f'  {name}: status={status}, HEALTHCHECK={\"present\" if hc else \"MISSING\"}')
"

# ---- PHASE 2: Fix coredb-postgres-exporter --------------------------------
echo ""
echo "--- PHASE 2: Fix coredb-postgres-exporter ---"

PG_CONTAINER="coredb-postgres-exporter"
PG_IMAGE="prometheuscommunity/postgres-exporter:v0.16.0"

if docker inspect "$PG_CONTAINER" >/dev/null 2>&1; then
    echo "Rebuilding $PG_CONTAINER with HEALTHCHECK..."

    # Use Python to safely extract config and build the run command
    python3 << 'PYEOF'
import subprocess, json, os

name = "coredb-postgres-exporter"
image = "prometheuscommunity/postgres-exporter:v0.16.0"

# Get current config
result = subprocess.run(["docker", "inspect", name], capture_output=True, text=True)
c = json.loads(result.stdout)[0]
cfg = c['Config']
hc_cfg = c['HostConfig']

# Extract env vars to a temp file
env_vars = cfg.get('Env', [])
env_file = "/tmp/docker-healthcheck-env.txt"
with open(env_file, 'w') as f:
    for e in env_vars:
        f.write(e + '\n')

# Build command
cmd = [
    "docker", "stop", name
]
subprocess.run(cmd, capture_output=True)
subprocess.run(["docker", "rm", name], capture_output=True)

network = list(c['NetworkSettings']['Networks'].keys())[0]
memory = hc_cfg.get('Memory', 0)
memory_swap = hc_cfg.get('MemorySwap', 0)
nano_cpus = hc_cfg.get('NanoCpus', 0)

run_cmd = [
    "docker", "run", "-d",
    "--name", name,
    "--network", network,
    "--restart", "unless-stopped",
    "--env-file", env_file,
    "--cap-drop", "ALL",
    "--health-cmd", "wget --no-verbose --tries=1 --spider http://localhost:9187/metrics || exit 1",
    "--health-interval", "30s",
    "--health-timeout", "10s",
    "--health-retries", "3",
    "--health-start-period", "10s",
]

if memory > 0:
    run_cmd.extend(["--memory", str(memory)])
if memory_swap > 0:
    run_cmd.extend(["--memory-swap", str(memory_swap)])
if nano_cpus > 0:
    cpus = nano_cpus / 1_000_000_000
    run_cmd.extend(["--cpus", str(cpus)])

run_cmd.append(image)

print(f"  Network: {network}")
print(f"  Memory: {memory}")
print(f"  Env vars: {len(env_vars)}")
result = subprocess.run(run_cmd, capture_output=True, text=True)
if result.returncode == 0:
    print(f"  [OK] {name} started: {result.stdout.strip()[:12]}")
else:
    print(f"  [ERROR] Failed: {result.stderr}")
    raise SystemExit(1)
PYEOF
    echo "[OK] $PG_CONTAINER recreated"
else
    echo "[WARN] Container $PG_CONTAINER not found — skipping"
fi

# ---- PHASE 3: Fix coredb-redis-exporter -----------------------------------
echo ""
echo "--- PHASE 3: Fix coredb-redis-exporter ---"

REDIS_CONTAINER="coredb-redis-exporter"
REDIS_IMAGE_ALPINE="oliver006/redis_exporter:v1.67.0-alpine"

if docker inspect "$REDIS_CONTAINER" >/dev/null 2>&1; then
    echo "Rebuilding $REDIS_CONTAINER with HEALTHCHECK (alpine base)..."

    # Ensure alpine image is pulled
    if ! docker image inspect "$REDIS_IMAGE_ALPINE" >/dev/null 2>&1; then
        echo "  Pulling $REDIS_IMAGE_ALPINE..."
        docker pull "$REDIS_IMAGE_ALPINE"
    fi
    echo "  [OK] Alpine image available"

    # Use Python to safely rebuild the container
    python3 << 'PYEOF'
import subprocess, json

name = "coredb-redis-exporter"
image = "oliver006/redis_exporter:v1.67.0-alpine"

result = subprocess.run(["docker", "inspect", name], capture_output=True, text=True)
c = json.loads(result.stdout)[0]
cfg = c['Config']
hc_cfg = c['HostConfig']

env_vars = cfg.get('Env', [])
env_file = "/tmp/docker-healthcheck-env.txt"
with open(env_file, 'w') as f:
    for e in env_vars:
        f.write(e + '\n')

subprocess.run(["docker", "stop", name], capture_output=True)
subprocess.run(["docker", "rm", name], capture_output=True)

network = list(c['NetworkSettings']['Networks'].keys())[0]
memory = hc_cfg.get('Memory', 0)
memory_swap = hc_cfg.get('MemorySwap', 0)
nano_cpus = hc_cfg.get('NanoCpus', 0)

run_cmd = [
    "docker", "run", "-d",
    "--name", name,
    "--network", network,
    "--restart", "unless-stopped",
    "--env-file", env_file,
    "--cap-drop", "ALL",
    "--health-cmd", "wget -qO- http://localhost:9121/metrics >/dev/null || exit 1",
    "--health-interval", "30s",
    "--health-timeout", "10s",
    "--health-retries", "3",
    "--health-start-period", "10s",
]

if memory > 0:
    run_cmd.extend(["--memory", str(memory)])
if memory_swap > 0:
    run_cmd.extend(["--memory-swap", str(memory_swap)])
if nano_cpus > 0:
    cpus = nano_cpus / 1_000_000_000
    run_cmd.extend(["--cpus", str(cpus)])

run_cmd.append(image)

print(f"  Network: {network}")
print(f"  Memory: {memory}")
print(f"  Image: {image}")
print(f"  Env vars: {len(env_vars)}")
result = subprocess.run(run_cmd, capture_output=True, text=True)
if result.returncode == 0:
    print(f"  [OK] {name} started: {result.stdout.strip()[:12]}")
else:
    print(f"  [ERROR] Failed: {result.stderr}")
    raise SystemExit(1)
PYEOF
    echo "[OK] $REDIS_CONTAINER recreated"
else
    echo "[WARN] Container $REDIS_CONTAINER not found — skipping"
fi

# ---- PHASE 4: Wait for stabilization --------------------------------------
echo ""
echo "--- PHASE 4: Stabilization ---"
echo "Waiting for healthchecks to pass (20s)..."
for i in $(seq 1 20); do
    sleep 1
    if [ $((i % 5)) -eq 0 ]; then
        echo -n "  ${i}s... "
    fi
done
echo ""

# ---- PHASE 5: Verification ------------------------------------------------
echo ""
echo "--- PHASE 5: Verification ---"

echo "Container status:"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'coredb|NAMES'

echo ""
echo "HEALTHCHECK details:"
docker inspect coredb-redis-exporter coredb-postgres-exporter 2>/dev/null | python3 -c "
import sys, json
all_healthy = True
for c in json.load(sys.stdin):
    hc = c['Config'].get('Healthcheck', None)
    name = c['Name'].lstrip('/')
    status = c['State']['Status']
    health = c['State'].get('Health', {}).get('Status', 'N/A')
    hc_test = hc['Test'] if hc else ['MISSING']
    print(f'  {name}:')
    print(f'    Container: {status}')
    print(f'    Health:   {health}')
    print(f'    Check:    {hc_test}')
    if health != 'healthy':
        all_healthy = False
        # Check logs for the last few lines
        import subprocess
        logs = subprocess.run(['docker', 'logs', '--tail', '5', name], capture_output=True, text=True)
        print(f'    Recent logs:')
        for line in logs.stdout.strip().split('\n')[-3:]:
            if line.strip():
                print(f'      {line.strip()[:120]}')

if not all_healthy:
    print()
    print('  WARNING: Not all containers are healthy yet. This can be normal during start period.')
    print('  Health checks run every 30s with a 10s start period.')
"

# ---- PHASE 6: Summary -----------------------------------------------------
echo ""
echo "=============================================="

HEALTHY_COUNT=$(docker inspect coredb-redis-exporter coredb-postgres-exporter 2>/dev/null | \
    python3 -c "import sys,json; print(sum(1 for c in json.load(sys.stdin) if c['State'].get('Health',{}).get('Status')=='healthy'))")

HC_COUNT=$(docker inspect coredb-redis-exporter coredb-postgres-exporter 2>/dev/null | \
    python3 -c "import sys,json; print(sum(1 for c in json.load(sys.stdin) if c['Config'].get('Healthcheck') is not None))")

echo "  Containers with HEALTHCHECK: $HC_COUNT/2"
echo "  Containers healthy: $HEALTHY_COUNT/2"

if [ "$HC_COUNT" -ge 2 ]; then
    echo "  RESULT: PASS — HEALTHCHECK directives added to both coredb exporters"
    echo "  Score recovery: +2 points (Docker HEALTHCHECK gaps)"
else
    echo "  RESULT: PARTIAL — $HC_COUNT/2 containers have HEALTHCHECK"
fi
echo "=============================================="

echo ""
echo "Log saved to: $LOG_FILE"
echo "Completed at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
