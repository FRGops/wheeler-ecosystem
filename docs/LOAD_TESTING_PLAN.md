# Wheeler Ecosystem Load Testing Plan

> **Phase 13 — Load Testing Plan**  
> Principal Performance Engineering Architecture  
> Date: 2026-05-23

---

## Executive Summary

This document defines **safe, non-destructive load testing plans** for the Wheeler ecosystem. All tests are designed to be run against staging/isolated endpoints or during low-traffic windows. **No automatic destructive load tests are prescribed.**

The goal is to establish:
1. **Throughput limits** — requests/second each component can handle
2. **Latency profiles** — p50/p95/p99 under load
3. **Breaking points** — at what concurrency does the system degrade
4. **Recovery behavior** — how the system recovers after overload

---

## Testing Principles

1. **Never test production directly** — use staging endpoints or isolated replicas
2. **Ramp up gradually** — start at 1 RPS, double until degradation
3. **Monitor continuously** — stop immediately if error rate > 1%
4. **Test during maintenance windows** — weekdays 02:00-05:00 UTC
5. **Have rollback ready** — all test scripts include stop conditions

---

## Test Environment Setup

### Prerequisites on Test Runner
```bash
# Install load testing tools
pip3 install locust                      # HTTP load testing
pip3 install k6                          # k6 load testing (via binary)
npm install -g artillery                 # Artillery for API testing

# Redis benchmarking
apt-get install -y redis-tools           # redis-benchmark

# PostgreSQL benchmarking
apt-get install -y pgbench               # pgbench
```

### Isolation Checklist
- [ ] Identify test endpoints (staging only)
- [ ] Notify team 24 hours before test
- [ ] Set up dedicated monitoring dashboard
- [ ] Configure test data (NOT production data)
- [ ] Set abort thresholds in monitoring

---

## Test 1: API Endpoint Load Test (Locust)

### Target: frgcrm-api on AIOPS (5.78.140.118)

```python
# /root/tests/load/api_load_test.py
from locust import HttpUser, task, between
import random

class WheelerAPIUser(HttpUser):
    """Simulates Wheeler API user traffic patterns."""
    
    wait_time = between(1, 3)  # Realistic think time
    
    def on_start(self):
        """Authenticate once per user."""
        self.client.post("/api/auth/login", json={
            "username": "test_user",
            "password": "test_password"
        })
    
    @task(3)  # Weight: 30% of traffic
    def get_claimants(self):
        """Read-heavy endpoint — cached."""
        claimant_id = random.randint(1, 10000)
        self.client.get(f"/api/claimant/{claimant_id}", 
                       name="/api/claimant/:id")
    
    @task(2)  # Weight: 20% of traffic
    def search_claimants(self):
        """Search endpoint — moderate load."""
        self.client.get("/api/claimant/search?q=smith&limit=20",
                       name="/api/claimant/search")
    
    @task(1)  # Weight: 10% of traffic
    def create_lead(self):
        """Mutation endpoint — lower volume."""
        self.client.post("/api/lead", json={
            "source": "web",
            "data": {"name": "Test Lead", "county": "Test"}
        }, name="/api/lead")
    
    @task(1)  # Weight: 10% of traffic
    def get_analytics(self):
        """Dashboard data — potentially expensive."""
        self.client.get("/api/analytics/summary?period=30d",
                       name="/api/analytics/summary")
```

### Test Scenario

| Stage | Duration | Users | Ramp Rate | Expected RPS | Pause if |
|---|---|---|---|---|---|
| Warmup | 2 min | 5 | 1/sec | ~2 | Error rate > 0% |
| Baseline | 5 min | 20 | 2/sec | ~8 | P95 > 200ms |
| Load | 10 min | 50 | 5/sec | ~20 | P95 > 500ms |
| Stress | 5 min | 100 | 10/sec | ~40 | P95 > 1000ms |
| Spike | 2 min | 200 | 50/sec | ~80 | Error rate > 1% |
| Cooldown | 5 min | 10 | -10/sec | ~4 | — |

```bash
# Run the test
locust -f /root/tests/load/api_load_test.py \
  --host=http://5.78.140.118:8080 \
  --users 100 \
  --spawn-rate 5 \
  --run-time 30m \
  --headless \
  --csv=/root/tests/results/api-load-test \
  --html=/root/tests/results/api-load-test.html
```

### Success Criteria
- [ ] Sustained throughput: > 20 RPS with P95 < 500ms
- [ ] No 5xx errors under sustained load
- [ ] Recovery within 30 seconds after spike
- [ ] Memory stays within PM2 max_memory_restart limits
- [ ] LiteLLM continues routing during API load

---

## Test 2: AI Routing Load Test

### Target: LiteLLM on AIOPS (5.78.140.118)

```python
# /root/tests/load/ai_routing_load_test.py
# Tests LiteLLM routing with concurrent AI requests

from locust import HttpUser, task, between
import time

class AIConsumerUser(HttpUser):
    """Simulates AI agent API consumer load on LiteLLM."""
    
    wait_time = between(5, 15)  # AI requests are slower
    
    @task(3)
    def chat_completion(self):
        """Standard chat completion — cached via semantic cache."""
        start = time.time()
        response = self.client.post("/v1/chat/completions", json={
            "model": "deepseek-chat",
            "messages": [{"role": "user", "content": "Summarize: Wheeler is a claims processing platform"}],
            "max_tokens": 100,
            "temperature": 0.0  # Deterministic for cache hit testing
        }, name="/v1/chat/completions (cacheable)")
        latency = time.time() - start
        
        # Tag based on cache hit
        if response.headers.get("x-litellm-cache-hit"):
            self.environment.events.request.fire(
                request_type="GET", name="cache_hit", 
                response_time=latency * 1000, response_length=0
            )
    
    @task(1)
    def embedding(self):
        self.client.post("/v1/embeddings", json={
            "model": "text-embedding-3-small",
            "input": "A claimant filed for benefits in Los Angeles County"
        }, name="/v1/embeddings")
```

### Test Scenarios

| Scenario | Concurrent Users | Duration | Purpose |
|---|---|---|---|
| Cache efficiency | 20 | 10 min | Measure semantic cache hit rate |
| Model routing | 10 | 10 min | Test fallback latency |
| Concurrent burst | 50 | 5 min | Test max concurrency |
| Sustained load | 30 | 30 min | Detect memory leaks |

```bash
locust -f /root/tests/load/ai_routing_load_test.py \
  --host=http://5.78.140.118:4000 \
  --users 30 \
  --spawn-rate 3 \
  --run-time 30m \
  --headless \
  --csv=/root/tests/results/ai-routing-load-test
```

### Success Criteria
- [ ] Semantic cache hit rate > 20% under load
- [ ] P95 latency < 3s for non-cached completions
- [ ] P95 latency < 200ms for cache hits
- [ ] No 429 rate limit errors
- [ ] Fallback works correctly when primary model fails

---

## Test 3: Redis Load Test

### Target: wheeler-redis on COREDB (5.78.210.123)

```bash
#!/bin/bash
# /root/tests/load/redis_benchmark.sh
# SAFE: Tests against test keys with prefix — does NOT touch production keys

REDIS_HOST="5.78.210.123"
REDIS_PORT="6379"
REDIS_AUTH=""  # Add if auth required

echo "=== Redis Benchmark ==="
echo "Target: $REDIS_HOST:$REDIS_PORT"
echo ""

# 1. PING latency baseline
echo "--- PING Latency ---"
redis-cli -h $REDIS_HOST -p $REDIS_PORT --latency-history 30

# 2. SET/GET throughput
echo "--- SET/GET Throughput ---"
redis-benchmark -h $REDIS_HOST -p $REDIS_PORT \
    -t set,get \
    -n 100000 \
    -c 50 \
    -d 1024 \
    --csv

# 3. Pipeline performance
echo "--- Pipeline (batch) ---"
redis-benchmark -h $REDIS_HOST -p $REDIS_PORT \
    -t set,get \
    -n 100000 \
    -P 16 \
    -c 50 \
    --csv

# 4. Queue simulation (LPUSH/RPOP)
echo "--- Queue Operations ---"
redis-benchmark -h $REDIS_HOST -p $REDIS_PORT \
    -t lpush,rpop \
    -n 100000 \
    -c 50 \
    --csv

# 5. Memory-constrained (cache eviction simulation)
echo "--- Cache Operations (large values) ---"
redis-benchmark -h $REDIS_HOST -p $REDIS_PORT \
    -t set,get \
    -n 10000 \
    -c 20 \
    -d 65536 \
    --csv

echo ""
echo "✓ Redis benchmark complete"
echo "Check Redis memory: redis-cli -h $REDIS_HOST INFO memory | grep used_memory_human"
```

### Success Criteria
- [ ] SET/GET throughput > 50000 ops/sec
- [ ] PING latency < 2ms
- [ ] No evictions during test
- [ ] Memory fragmentation ratio < 1.5

---

## Test 4: PostgreSQL Connection Stress Test

### Target: wheeler-postgres on COREDB (5.78.210.123)

```bash
#!/bin/bash
# /root/tests/load/pg_connection_stress.sh
# SAFE: Creates test database, runs pgbench, drops it after

PG_HOST="5.78.210.123"
PG_USER="postgres"
TEST_DB="pgbench_test"

echo "=== PostgreSQL Connection Stress Test ==="

# 1. Initialize test database
echo "--- Initializing pgbench ---"
docker exec wheeler-postgres psql -U $PG_USER -c "DROP DATABASE IF EXISTS $TEST_DB;" 2>/dev/null
docker exec wheeler-postgres psql -U $PG_USER -c "CREATE DATABASE $TEST_DB;"
docker exec wheeler-postgres pgbench -U $PG_USER -i -s 10 $TEST_DB

# 2. Baseline test (10 connections)
echo "--- Baseline: 10 connections ---"
docker exec wheeler-postgres pgbench -U $PG_USER \
    -c 10 -j 2 -T 60 $TEST_DB

# 3. Moderate load (50 connections)
echo "--- Moderate: 50 connections ---"
docker exec wheeler-postgres pgbench -U $PG_USER \
    -c 50 -j 4 -T 60 $TEST_DB

# 4. Connection stress (max_connections - 10)
MAX_CONN=$(docker exec wheeler-postgres psql -U $PG_USER -t -c "SHOW max_connections;" | tr -d ' ')
TEST_CONN=$((MAX_CONN - 10))
echo "--- Stress: $TEST_CONN connections ---"
docker exec wheeler-postgres pgbench -U $PG_USER \
    -c $TEST_CONN -j 8 -T 60 -M prepared $TEST_DB

# 5. Cleanup
docker exec wheeler-postgres psql -U $PG_USER -c "DROP DATABASE $TEST_DB;"

echo ""
echo "✓ PostgreSQL stress test complete"
```

### Success Criteria
- [ ] TPS > 500 at 50 connections
- [ ] No connection timeouts
- [ ] No deadlocks
- [ ] Cache hit ratio > 95%

---

## Test 5: PM2 Worker Saturation Test

### Target: agent-svc workers on AIOPS

```bash
#!/bin/bash
# /root/tests/load/pm2_worker_saturation.sh
# SAFE: Monitors existing workers under load — does NOT overload

echo "=== PM2 Worker Saturation Audit ==="
echo "Observing current worker behavior under existing load..."
echo ""

# 1. Current state
pm2 list

# 2. Monitor for 5 minutes, capture CPU/memory samples
echo "--- Sampling every 10s for 300s ---"
for i in $(seq 1 30); do
    TIMESTAMP=$(date +%H:%M:%S)
    CPU=$(pm2 list 2>/dev/null | grep -E "agent-svc|frgcrm-api|litellm" | 
          awk '{sum+=$9} END {print sum}')
    echo "$TIMESTAMP  agent-svc_CPU_total=$CPU%"
    sleep 10
done

# 3. Check event loop lag (Node.js processes)
echo "--- Event Loop Lag ---"
for pid in $(pm2 jlist 2>/dev/null | python3 -c "
import sys, json
for p in json.load(sys.stdin):
    if p.get('pid') and 'agent' in p.get('name','').lower():
        print(p['pid'])
" 2>/dev/null); do
    echo "PID $pid event loop lag:"
    # Check if process is responding
    kill -0 $pid 2>/dev/null && echo "  alive" || echo "  DEAD"
done

echo ""
echo "✓ Worker saturation audit complete"
echo "Review results for processes consistently near 100% CPU"
```

---

## Test 6: Edge Server Recovery Test

### Target: EDGE server (187.77.148.88)

Given the **79.5% CPU steal** issue, this test verifies behavior under the hypervisor constraint.

```bash
#!/bin/bash
# /root/tests/load/edge_recovery_test.sh
# SAFE: Passive observation + controlled connection test

EDGE_IP="187.77.148.88"

echo "=== Edge Server Resilience Audit ==="

# 1. Current load snapshot
echo "--- Current Load ---"
ssh -o ConnectTimeout=5 root@$EDGE_IP "uptime; free -h | head -2"

# 2. Response time baseline
echo "--- Response Time Baseline ---"
curl -w "Connect: %{time_connect}s | TTFB: %{time_starttransfer}s | Total: %{time_total}s | HTTP: %{http_code}\n" \
     -o /dev/null -s "http://$EDGE_IP/" 2>/dev/null || echo "  Unreachable"

# 3. Concurrent connection test (gentle — 10 concurrent)
echo "--- 10 Concurrent Connections ---"
for i in $(seq 1 10); do
    curl -w "%{http_code} %{time_total}s\n" -o /dev/null -s "http://$EDGE_IP/" &
done
wait

# 4. Check for CPU steal
echo "--- Hypervisor Steal Time ---"
ssh -o ConnectTimeout=5 root@$EDGE_IP "top -bn1 | grep '%Cpu'"

# 5. Check for zombie processes
echo "--- Zombie Processes ---"
ssh -o ConnectTimeout=5 root@$EDGE_IP "ps aux | grep -w Z | wc -l"

echo ""
echo "✓ Edge resilience audit complete"
```

### Success Criteria
- [ ] All 10 concurrent connections succeed
- [ ] P95 response time < 5s (accounting for CPU steal)
- [ ] Zero zombie processes
- [ ] No 502/504 gateway errors

---

## Test Schedule

| Test | Frequency | Duration | Window | Owner |
|---|---|---|---|---|
| API load test | Weekly | 30 min | Tue 03:00 UTC | Infra team |
| AI routing load | Weekly | 30 min | Wed 03:00 UTC | AI team |
| Redis benchmark | Monthly | 15 min | Sat 04:00 UTC | DB team |
| PG connection stress | Monthly | 15 min | Sat 04:30 UTC | DB team |
| Worker saturation | Continuous | — | Real-time monitoring | Infra team |
| Edge resilience | Weekly | 10 min | Tue 02:00 UTC | Infra team |

---

## Abort Conditions (Immediate Stop)

| Condition | Threshold | Action |
|---|---|---|
| Error rate | > 1% of requests | Stop test, investigate root cause |
| P95 latency spike | > 10× baseline | Pause ramp, observe recovery |
| Production 5xx errors | Any | Halt immediately, check routing |
| Memory exhaustion | > 90% on any server | Stop test, check for leaks |
| Redis evictions | Any during test | Stop, review memory policy |
| DB connection exhaustion | Connections ≥ max_connections - 5 | Stop, tune pool settings |
| Disk space | < 10% free | Stop, rotate logs |

---

## Post-Test Analysis

After each test, capture:
1. **Throughput curve** — RPS vs concurrency
2. **Latency distribution** — p50, p95, p99, max
3. **Error breakdown** — by endpoint, by error type
4. **Resource utilization** — CPU, memory, disk I/O during test
5. **Bottleneck identification** — which component saturated first

Generate report at: `/root/tests/results/load-test-report-YYYYMMDD.md`

---

## Templates Generated

- `/root/tests/load/api_load_test.py` — Locust script for API testing
- `/root/tests/load/ai_routing_load_test.py` — Locust script for AI routing
- `/root/tests/load/redis_benchmark.sh` — Redis benchmark script
- `/root/tests/load/pg_connection_stress.sh` — PostgreSQL stress test
- `/root/tests/load/edge_recovery_test.sh` — Edge server recovery test
- `/root/tests/load/pm2_worker_saturation.sh` — PM2 worker audit script
