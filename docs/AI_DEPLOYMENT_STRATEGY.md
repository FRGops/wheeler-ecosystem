# AI Deployment Strategy

**Version:** 1.0
**Date:** 2026-05-23
**Owner:** AI Platform Engineering
**Primary Server:** AIOPS (Hetzner / 5.78.140.118)
**Related Documents:** DEPLOYMENT_DASHBOARD_PLAN.md, CANARY_DEPLOYMENT_PLAN.md

---

## 1. AI Service Inventory

### 1.1 Service Catalog

| Service | Process Name | Host | Port | Manager | Repo | Description |
|---|---|---|---|---|---|---|
| LiteLLM Proxy | `wheeler-litellm` | AIOPS | 4000 | PM2 | `infra/litellm-config` | Routes requests to multiple LLM providers, handles auth, rate limiting, cost tracking |
| DeepSeek Routing | (via LiteLLM) | AIOPS | -- | LiteLLM config | -- | Primary LLM provider, direct API or via LiteLLM proxy |
| OpenRouter Fallback | (via LiteLLM) | AIOPS | -- | LiteLLM config | -- | Secondary provider with multi-model access, activated when DeepSeek is unavailable |
| AI Workers | `wheeler-ai-worker-*` | AIOPS | dynamic | PM2 | `workers/ai-workers` | Python processes consuming LLM APIs for business logic (lead enrichment, classification, etc.) |
| Embedding Service | `wheeler-embedding` | AIOPS | 5001 | PM2 | `services/embedding` | Generates embeddings for semantic search and RAG pipeline |
| AI Health Monitor | `wheeler-ai-health` | AIOPS | 9501 | systemd | `infra/ai-health` | Sends test inferences, tracks model availability, reports to dashboard aggregator |

### 1.2 Dependency Graph

```
                              +--------------------+
                              |   AI WORKERS       |
                              | (wheeler-ai-worker)|
                              +----------+---------+
                                         |
                           +-------------+-------------+
                           |                           |
                 +---------+---------+     +----------+---------+
                 |  EMBEDDING SVC    |     |  AI HEALTH MONITOR |
                 | (wheeler-embed)   |     | (wheeler-ai-health)|
                 +---------+---------+     +----------+---------+
                           |                           |
                           +-------------+-------------+
                                         |
                              +----------+---------+
                              |   LITELLM PROXY    |
                              | (wheeler-litellm)  |
                              +----------+---------+
                                         |
                         +---------------+---------------+
                         |                               |
              +----------+----------+        +-----------+----------+
              |   DEEPSEEK API      |        |   OPENROUTER API     |
              | (api.deepseek.com)  |        | (openrouter.ai/api)  |
              +---------------------+        +----------------------+
                         |                               |
              +----------+----------+        +-----------+----------+
              | deepseek-chat       |        | deepseek/deepseek-   |
              | deepseek-reasoner   |        |   chat               |
              +---------------------+        | openai/gpt-4o        |
                                             | anthropic/claude-    |
                                             |   sonnet              |
                                             +----------------------+
```

### 1.3 Service Lifecycle States

| State | Definition | Dashboard Color |
|---|---|---|
| `stopped` | Process not running | Gray |
| `launching` | PM2 starting the process | Yellow (spinner) |
| `starting` | Process running but not yet passing health checks | Yellow |
| `healthy` | Process running and passing all health checks | Green |
| `degraded` | Running but some health checks failing (e.g., one model unavailable) | Orange |
| `unhealthy` | Running but critical health checks failing (e.g., all models unreachable) | Red |
| `errored` | PM2 reports error status or process exited with error | Red |

---

## 2. LiteLLM Deployment Procedure

### 2.1 Pre-Deployment Checks

Before deploying any LiteLLM configuration change, verify:

1. **API Key Validity**
   ```bash
   # Test DeepSeek API key
   curl -s -X POST https://api.deepseek.com/v1/chat/completions \
     -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "deepseek-chat",
       "messages": [{"role": "user", "content": "Respond with OK"}],
       "max_tokens": 5
     }' | jq '.choices[0].message.content'

   # Test OpenRouter API key
   curl -s -X POST https://openrouter.ai/api/v1/chat/completions \
     -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "deepseek/deepseek-chat",
       "messages": [{"role": "user", "content": "Respond with OK"}],
       "max_tokens": 5
     }' | jq '.choices[0].message.content'
   ```

   Expected output from both: `"OK"`. If either fails, abort the deployment and investigate API key expiration or provider outage.

2. **Config Syntax Validation**
   ```bash
   # If using a YAML config, validate YAML syntax
   python3 -c "import yaml; yaml.safe_load(open('/opt/wheeler/litellm/config.yaml'))"
   echo "Config YAML is valid"
   ```

3. **Current State Snapshot**
   ```bash
   # Record current state for potential rollback
   cp /opt/wheeler/litellm/config.yaml /opt/wheeler/litellm/config.yaml.previous
   pm2 jlist | jq '.[] | select(.name == "wheeler-litellm")' > /tmp/litellm_pre_deploy.json
   ```

4. **Token Budget Check**
   ```bash
   # Verify API key has sufficient credits/quota
   curl -s https://api.deepseek.com/v1/user/balance \
     -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" | jq '.balance'
   # Alert if balance < $50
   ```

### 2.2 Deployment Steps

```bash
#!/bin/bash
# deploy-litellm.sh -- Deploy LiteLLM proxy with new configuration
set -euo pipefail

DEPLOY_ID="litellm-$(date +%Y%m%d-%H%M%S)"
LOG_DIR="/var/log/wheeler/deploy"
mkdir -p "$LOG_DIR"

echo "=== LiteLLM Deploy $DEPLOY_ID ===" | tee "$LOG_DIR/${DEPLOY_ID}.log"

# Step 1: Sync new config
echo "[1/5] Deploying new config.yaml..." | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
cp /opt/wheeler/litellm/config.yaml /opt/wheeler/litellm/config.yaml.previous
cp /opt/wheeler/litellm/staging/config.yaml /opt/wheeler/litellm/config.yaml
echo "Config deployed at $(date -Iseconds)" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"

# Step 2: Graceful restart
echo "[2/5] Restarting LiteLLM..." | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
pm2 restart wheeler-litellm --update-env 2>&1 | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
sleep 3

# Step 3: Verify process is running
echo "[3/5] Verifying process..." | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
pm2 jlist | jq -e '.[] | select(.name == "wheeler-litellm" and .pm2_env.status == "online")' || {
    echo "FATAL: LiteLLM process is not online" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
    exit 1
}

# Step 4: Verify /health endpoint
echo "[4/5] Checking /health endpoint..." | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
for i in $(seq 1 10); do
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/health 2>/dev/null || echo "000")
    if [ "$HEALTH" = "200" ]; then
        echo "Health check passed (attempt $i)" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
        break
    fi
    if [ "$i" -eq 10 ]; then
        echo "FATAL: Health check failed after 10 attempts" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
        exit 1
    fi
    sleep 2
done

# Step 5: Verify models are listed
echo "[5/5] Verifying model list..." | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
MODELS=$(curl -s http://localhost:4000/v1/models | jq '.data | length')
echo "LiteLLM reports $MODELS available models" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
if [ "$MODELS" -lt 2 ]; then
    echo "WARNING: Fewer models than expected (got $MODELS, expected >= 2)" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"
fi

echo "=== Deploy $DEPLOY_ID complete ===" | tee -a "$LOG_DIR/${DEPLOY_ID}.log"

# Write structured deploy log
cat > "$LOG_DIR/${DEPLOY_ID}_result.json" << EOFLOG
{
  "deploy_id": "$DEPLOY_ID",
  "timestamp": "$(date -Iseconds)",
  "service": "litellm",
  "server": "AIOPS",
  "status": "success",
  "version_to": "$(git -C /opt/wheeler/litellm describe --tags --always 2>/dev/null || echo 'config-only')",
  "models_available": $MODELS
}
EOFLOG
```

### 2.3 Post-Deployment Verification

After the deployment script succeeds, run these additional verification steps:

1. **Test proxy with a real chat completion:**
   ```bash
   curl -s http://localhost:4000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
     -d '{
       "model": "deepseek-chat",
       "messages": [{"role": "user", "content": "Count from 1 to 5."}],
       "max_tokens": 50
     }' | jq '{model: .model, content: .choices[0].message.content, tokens: .usage.total_tokens}'
   ```

   Expected: JSON response with `model: "deepseek-chat"`, content containing numbers 1-5, `tokens` > 0.

2. **Test streaming response:**
   ```bash
   curl -s -N http://localhost:4000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
     -d '{
       "model": "deepseek-chat",
       "messages": [{"role": "user", "content": "Say hello"}],
       "stream": true,
       "max_tokens": 20
     }' | head -5
   ```

   Expected: Multiple `data:` lines with SSE format.

3. **Verify API key passthrough:**
   ```bash
   # Using a customer-facing API key (not master key)
   curl -s http://localhost:4000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${CUSTOMER_API_KEY}" \
     -d '{
       "model": "deepseek-chat",
       "messages": [{"role": "user", "content": "Hi"}],
       "max_tokens": 5
     }' | jq '.model'
   ```

4. **Monitor logs for 2 minutes for errors:**
   ```bash
   pm2 logs wheeler-litellm --lines 50 --nostream | grep -iE "error|fail|timeout"
   ```

### 2.4 Rollback Procedure

If any verification step fails:

```bash
#!/bin/bash
# rollback-litellm.sh -- Restore previous configuration
set -euo pipefail

ROLLBACK_ID="rlb-litellm-$(date +%Y%m%d-%H%M%S)"
LOG_DIR="/var/log/wheeler/rollback"
mkdir -p "$LOG_DIR"

echo "=== Rolling back LiteLLM: $ROLLBACK_ID ==="

# Step 1: Restore previous config
if [ -f /opt/wheeler/litellm/config.yaml.previous ]; then
    cp /opt/wheeler/litellm/config.yaml.previous /opt/wheeler/litellm/config.yaml
    echo "Restored previous config.yaml"
else
    echo "WARNING: No previous config found, checking git"
    git -C /opt/wheeler/litellm checkout config.yaml
fi

# Step 2: Restart
pm2 restart wheeler-litellm --update-env
sleep 3

# Step 3: Verify restoration
curl -sf http://localhost:4000/health > /dev/null && echo "Health OK after rollback" || echo "FATAL: Health still failing"

# Step 4: Write rollback log
cat > "$LOG_DIR/${ROLLBACK_ID}.json" << EOFLOG
{
  "rollback_id": "$ROLLBACK_ID",
  "triggered_at": "$(date -Iseconds)",
  "service": "litellm",
  "reason": "post-deploy verification failure",
  "automatic": false,
  "triggered_by": "$(whoami)"
}
EOFLOG
```

---

## 3. DeepSeek Routing Configuration

### 3.1 LiteLLM Config for DeepSeek as Primary

**File:** `/opt/wheeler/litellm/config.yaml`

```yaml
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: "postgresql://litellm:${LITELLM_DB_PASS}@localhost:5432/litellm"
  disable_master_key_returned: true

model_list:
  # PRIMARY: DeepSeek direct
  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: ${DEEPSEEK_API_KEY}
      api_base: https://api.deepseek.com/v1
      rpm: 500                          # Requests per minute limit
      tpm: 500000                       # Tokens per minute limit
      timeout: 60                        # Seconds before timeout
      max_retries: 3
      stream_timeout: 120
    model_info:
      mode: chat
      max_tokens: 8192
      supports_function_calling: true
      supports_vision: false

  - model_name: deepseek-reasoner
    litellm_params:
      model: deepseek/deepseek-reasoner
      api_key: ${DEEPSEEK_API_KEY}
      api_base: https://api.deepseek.com/v1
      rpm: 100
      tpm: 200000
      timeout: 120
      max_retries: 2
      stream_timeout: 180
    model_info:
      mode: chat
      max_tokens: 32768
      supports_function_calling: true
      supports_vision: false

  # FALLBACK #1: OpenRouter (DeepSeek via OpenRouter)
  - model_name: deepseek-chat
    litellm_params:
      model: openrouter/deepseek/deepseek-chat
      api_key: ${OPENROUTER_API_KEY}
      api_base: https://openrouter.ai/api/v1
      rpm: 300
      tpm: 300000
      timeout: 90
      max_retries: 3
    model_info:
      mode: chat
      max_tokens: 8192

  # FALLBACK #2: OpenRouter GPT-4o (last resort)
  - model_name: deepseek-chat
    litellm_params:
      model: openrouter/openai/gpt-4o
      api_key: ${OPENROUTER_API_KEY}
      api_base: https://openrouter.ai/api/v1
      rpm: 100
      tpm: 100000
      timeout: 90
      max_retries: 2
    model_info:
      mode: chat
      max_tokens: 4096
```

### 3.2 Router Configuration (LiteLLM router_settings)

```yaml
router_settings:
  # Routing strategy: prioritize least-busy endpoint for same model name
  routing_strategy: "usage-based-routing-v2"

  # Fallback configuration: if primary fails, try next in list
  enable_pre_call_checks: true
  allowed_fails: 3                    # Consecutive failures before removing from rotation
  num_retries: 3                      # Per-request retries
  retry_after: 30                     # Seconds before retrying a failed deployment
  cooldown_time: 30                   # Seconds to cooldown a deployment after failure

  # Health check polling
  health_check_interval: 30           # Seconds between health checks

  # Circuit breaker (built into router)
  # Opens after 5 consecutive failures, half-open after 60s
  # If half-open request fails, re-opens for 120s
```

### 3.3 Rate Limit Configuration

```yaml
litellm_settings:
  # Global rate limits
  rpm: 1000                           # Total requests per minute across all models
  tpm: 1000000                        # Total tokens per minute across all models

  # Per-deployment rate limits defined in model_list above
  # Overrides: set per-user/per-team limits in database

  # Rate limit error response
  rate_limit_error_tracking: true

  # Spend tracking
  success_callback: ["prometheus"]    # Send metrics to Prometheus
  failure_callback: ["prometheus"]

  # Set context window fallback
  drop_params: true                   # Drop unsupported params (e.g., vision for deepseek-chat)

  # Retry policy
  num_retries: 3
  request_timeout: 60
  set_verbose: false                  # Set to true for debugging
```

### 3.4 Health Check Configuration

**File:** `/opt/wheeler/ai-health/health_checks.yaml`

```yaml
health_checks:
  deepseek_primary:
    provider: deepseek
    model: deepseek-chat
    endpoint: https://api.deepseek.com/v1/chat/completions
    api_key_env: DEEPSEEK_API_KEY
    interval_seconds: 30
    timeout_seconds: 60
    request:
      messages:
        - role: user
          content: "Respond with exactly: HEALTHY"
      max_tokens: 5
      temperature: 0
    expected:
      status_code: 200
      content_contains: "HEALTHY"
      latency_max_ms: 5000
      tokens_min: 2
    on_failure:
      consecutive_failures_for_alert: 3
      consecutive_failures_for_failover: 5

  deepseek_reasoner:
    provider: deepseek
    model: deepseek-reasoner
    endpoint: https://api.deepseek.com/v1/chat/completions
    api_key_env: DEEPSEEK_API_KEY
    interval_seconds: 120            # Less frequent for expensive reasoning model
    timeout_seconds: 120
    request:
      messages:
        - role: user
          content: "What is 2+2? Answer with just the number."
      max_tokens: 5
    expected:
      status_code: 200
      content_contains: "4"
      latency_max_ms: 30000

  openrouter_deepseek:
    provider: openrouter
    model: deepseek/deepseek-chat
    endpoint: https://openrouter.ai/api/v1/chat/completions
    api_key_env: OPENROUTER_API_KEY
    interval_seconds: 60
    timeout_seconds: 60
    request:
      messages:
        - role: user
          content: "Respond with exactly: HEALTHY"
      max_tokens: 5
    expected:
      status_code: 200
      content_contains: "HEALTHY"
      latency_max_ms: 8000

  openrouter_gpt4o:
    provider: openrouter
    model: openai/gpt-4o
    endpoint: https://openrouter.ai/api/v1/chat/completions
    api_key_env: OPENROUTER_API_KEY
    interval_seconds: 300            # Less frequent for expensive fallback
    timeout_seconds: 60
    request:
      messages:
        - role: user
          content: "Respond with exactly: HEALTHY"
      max_tokens: 5
    expected:
      status_code: 200
      content_contains: "HEALTHY"
```

---

## 4. Model Fallback Routing

### 4.1 Routing Architecture

```
                       +-----------+
                       |  CLIENT   |
                       | (AI Worker |
                       |  or app)  |
                       +-----+-----+
                             |
                             v
                       +-----+-----+
                       |  LITELLM  |
                       |   PROXY   |
                       +-----+-----+
                             |
              +--------------+--------------+
              |              |              |
              v              v              v
        +-----+-----+ +-----+-----+ +-----+-----+
        | DEEPSEEK  | | OPENROUTER| | OPENROUTER|
        | (primary) | | (fallback | | (fallback |
        |           | |    #1)    | |    #2)    |
        | deepseek- | | deepseek/ | | openai/   |
        | chat      | | deepseek- | | gpt-4o    |
        +-----------+ | chat      | +-----------+
                      +-----------+
```

### 4.2 Circuit Breaker Pattern

The circuit breaker protects against cascading failures when the primary model is degraded. It is implemented at two levels:

**Level 1: LiteLLM Built-in Router (Automatic)**

LiteLLM's router has built-in cooldown logic. When a deployment (a specific model+provider combination) fails consecutively, LiteLLM removes it from the rotation for a cooldown period. Configuration:

```yaml
router_settings:
  allowed_fails: 5           # Consecutive failures trigger cooldown
  cooldown_time: 60          # Seconds to keep deployment out of rotation
  num_retries: 3             # Retry each individual request
```

States:
- **CLOSED:** Normal operation, requests go to primary
- **OPEN (after N consecutive failures):** Primary removed from rotation, requests route to fallback
- **HALF_OPEN (after cooldown_time):** One test request allowed to primary; if it succeeds, circuit closes; if it fails, circuit re-opens with doubled cooldown

**Level 2: AI Health Monitor (External, Configurable)**

The AI Health Monitor runs independently and maintains its own circuit breaker state, which feeds into the dashboard:

```python
# Conceptual circuit breaker logic
class CircuitBreaker:
    def __init__(self, name, failure_threshold=5, cooldown_seconds=60):
        self.name = name
        self.failure_threshold = failure_threshold
        self.cooldown_seconds = cooldown_seconds
        self.failure_count = 0
        self.state = "CLOSED"
        self.last_failure_time = None
        self.opened_at = None

    def record_success(self):
        self.failure_count = 0
        if self.state == "HALF_OPEN":
            self.state = "CLOSED"
            self._log("Circuit closed -- primary restored")

    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.state == "HALF_OPEN":
            self.state = "OPEN"
            self.cooldown_seconds *= 2  # Exponential backoff
            self._log(f"Circuit re-opened -- cooldown: {self.cooldown_seconds}s")
        elif self.failure_count >= self.failure_threshold:
            self.state = "OPEN"
            self.opened_at = time.time()
            self._log(f"Circuit opened after {self.failure_count} failures")

    def allow_request(self):
        if self.state == "CLOSED":
            return True
        if self.state == "OPEN":
            if time.time() - self.opened_at > self.cooldown_seconds:
                self.state = "HALF_OPEN"
                self._log("Circuit half-open -- testing primary")
                return True
            return False
        if self.state == "HALF_OPEN":
            return True  # Allow one probe request
```

### 4.3 Automatic Recovery Process

1. **Detection:** AI Health Monitor detects primary model failures via test inference
2. **Failover:** After N consecutive failures, circuit breaker opens; LiteLLM routes to fallback automatically
3. **Recovery probing:** Every `cooldown_time` seconds, one health check request probes the primary
4. **Recovery:** If probe succeeds, circuit closes; LiteLLM resumes routing to primary
5. **Alerting:** Circuit state changes are pushed to dashboard and Slack

### 4.4 Cost Considerations During Failover

| Scenario | Provider | Cost per 1M tokens (approx) | Cost Multiplier |
|---|---|---|---|
| Normal operation | DeepSeek direct | $0.14 (input) / $0.28 (output) | 1x |
| Failover #1 | OpenRouter DeepSeek | $0.14 (input) / $0.28 (output) + OpenRouter fee | 1.05x |
| Failover #2 | OpenRouter GPT-4o | $2.50 (input) / $10.00 (output) | 18-35x |

**Mitigation strategies:**
- Alert on failover #2 activation (cost spike)
- Implement per-hour spend cap on fallback models
- Prefer failover #1 (same underlying model, minimal cost delta)
- Automatically scale down non-critical AI workers during extended failover #2

---

## 5. OpenRouter Failover Configuration

### 5.1 OpenRouter API Key Configuration

```bash
# Environment variables on AIOPS server
# Managed via systemd EnvironmentFile or PM2 ecosystem.config.js

OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENROUTER_REFERRER=https://wheeler-app.com
OPENROUTER_APP_NAME=wheeler-ai-platform
```

### 5.2 Model Mapping

LiteLLM config creates a seamless failover by using the same `model_name` for all fallback entries. Clients always request `deepseek-chat` -- LiteLLM routes to the appropriate provider based on availability:

| Client Requests | Primary (healthy) | Fallback #1 (primary degraded) | Fallback #2 (both degraded) |
|---|---|---|---|
| `deepseek-chat` | `deepseek/deepseek-chat` | `openrouter/deepseek/deepseek-chat` | `openrouter/openai/gpt-4o` |
| `deepseek-reasoner` | `deepseek/deepseek-reasoner` | (no direct fallback, errors returned) | (no fallback) |

### 5.3 OpenRouter-Specific Headers

```yaml
# In LiteLLM config, per-deployment settings
litellm_params:
  model: openrouter/deepseek/deepseek-chat
  api_key: ${OPENROUTER_API_KEY}
  api_base: https://openrouter.ai/api/v1
  headers:
    HTTP-Referer: "https://wheeler-app.com"
    X-Title: "wheeler-ai-platform"
  transforms: ["openrouter/auto"]   # Auto-transform to OpenRouter format
```

### 5.4 Failover Frequency Monitoring

Track how often we fail over and for how long:

```sql
-- Example query against LiteLLM spending database
SELECT
    date_trunc('day', start_time) as day,
    model_group,
    COUNT(*) as requests,
    SUM(CASE WHEN api_base LIKE '%openrouter%' THEN 1 ELSE 0 END) as fallback_requests,
    ROUND(100.0 * SUM(CASE WHEN api_base LIKE '%openrouter%' THEN 1 ELSE 0 END) / COUNT(*), 2) as fallback_pct
FROM litellm_spend_logs
WHERE start_time > NOW() - INTERVAL '30 days'
GROUP BY 1, 2
ORDER BY 1 DESC;
```

**Alert thresholds for failover:**
- Warning: Fallback percentage > 5% in any 1-hour window
- Critical: Fallback percentage > 20% in any 1-hour window
- Critical: Continuous failover > 30 minutes

---

## 6. AI Worker Deployment Order

### 6.1 Dependency Graph

```
DEPLOY ORDER (top to bottom):

1. API KEY VALIDATION
   - Verify DeepSeek API key valid
   - Verify OpenRouter API key valid
   - Verify LiteLLM master key valid

2. LITELLM PROXY (wheeler-litellm)
   - Must be healthy before any AI worker starts
   - Validated by: /health endpoint, /v1/models endpoint, test inference

3. DEEPSEEK REACHABILITY CHECK
   - Test inference through LiteLLM to DeepSeek
   - Verify latency is within SLA
   - Verify response quality

4. EMBEDDING SERVICE (wheeler-embedding)
   - Deploy before workers that depend on embeddings
   - Validated by: embedding test endpoint

5. AI WORKERS (wheeler-ai-worker-*)
   - Deploy in groups: non-critical first, critical last
   - Each worker warmup: sends test inference through LiteLLM

6. AI HEALTH MONITOR (wheeler-ai-health)
   - Deploy last (monitors everything above)
```

### 6.2 Worker Warmup Procedure

Each AI worker must pass warmup before being considered healthy:

```python
# Conceptual warmup script embedded in each worker
import time, requests, os

def worker_warmup():
    """Run before worker accepts production traffic."""
    litellm_url = os.environ.get("LITELLM_URL", "http://localhost:4000")
    api_key = os.environ.get("LITELLM_API_KEY")

    # Test 1: Basic connectivity
    health = requests.get(f"{litellm_url}/health", timeout=10)
    assert health.status_code == 200, "LiteLLM health check failed"
    assert health.json()["status"] == "healthy", "LiteLLM not healthy"

    # Test 2: Model availability
    models = requests.get(
        f"{litellm_url}/v1/models",
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=10
    )
    model_ids = [m["id"] for m in models.json()["data"]]
    assert "deepseek-chat" in model_ids, "deepseek-chat not available"

    # Test 3: Test inference
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{litellm_url}/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "deepseek-chat",
                    "messages": [{"role": "user", "content": "Say: WARMUP_OK"}],
                    "max_tokens": 10,
                    "temperature": 0
                },
                timeout=30
            )
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"]
            assert "WARMUP_OK" in content, f"Unexpected warmup response: {content}"
            print(f"Worker warmup passed (attempt {attempt + 1})")
            return True
        except Exception as e:
            print(f"Warmup attempt {attempt + 1} failed: {e}")
            time.sleep(2)

    raise RuntimeError("Worker warmup failed after 3 attempts")
```

### 6.3 Worker Group Deployment Order

| Order | Worker Group | Workers | Criticality | Warmup Timeout |
|---|---|---|---|---|
| 1 | Utility Workers | `wheeler-ai-util-*` | Low | 60s |
| 2 | Classification Workers | `wheeler-ai-classify-*` | Medium | 60s |
| 3 | Enrichment Workers | `wheeler-ai-enrich-*` | High | 90s |
| 4 | Real-Time Workers | `wheeler-ai-realtime-*` | Critical | 120s |

**Rule:** Each group must have at least 50% of workers passing warmup before deploying the next group.

### 6.4 Dependency Validation Script

```bash
#!/bin/bash
# validate-ai-deps.sh -- Run before AI worker deployment
set -euo pipefail

echo "=== Validating AI Dependencies ==="

# Check 1: LiteLLM health
echo -n "LiteLLM health: "
HEALTH=$(curl -sf http://localhost:4000/health | jq -r '.status')
if [ "$HEALTH" = "healthy" ]; then
    echo "PASS ($HEALTH)"
else
    echo "FAIL (status: $HEALTH)"
    exit 1
fi

# Check 2: DeepSeek reachable
echo -n "DeepSeek reachability: "
DS_RESP=$(curl -sf http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"PING"}],"max_tokens":5}' \
    | jq -r '.choices[0].message.content')
if [ -n "$DS_RESP" ]; then
    echo "PASS (response: $DS_RESP)"
else
    echo "FAIL (no response content)"
    exit 1
fi

# Check 3: OpenRouter reachable
echo -n "OpenRouter reachability: "
OR_RESP=$(curl -sf http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"PING"}],"max_tokens":5}' \
    -w '%{http_code}' -o /dev/null)
if [ "$OR_RESP" = "200" ]; then
    echo "PASS (HTTP $OR_RESP)"
else
    echo "WARNING (HTTP $OR_RESP) -- check which provider served the request"
fi

# Check 4: Embedding service (if deploying workers that need it)
echo -n "Embedding service: "
EMBED=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:5001/health)
if [ "$EMBED" = "200" ]; then
    echo "PASS"
else
    echo "WARNING (HTTP $EMBED) -- only required for RAG workers"
fi

echo "=== All critical dependencies PASSED ==="
```

---

## 7. AI Health Validation

### 7.1 Test Inference Validation

**Purpose:** Verify the full inference pipeline works end-to-end with expected quality.

**Procedure:**

```python
# test_inference.py -- Run as part of deploy verification
import json, time, requests

LITELLM_URL = "http://localhost:4000"
API_KEY = os.environ["LITELLM_MASTER_KEY"]
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

TEST_CASES = [
    {
        "name": "basic_completion",
        "request": {
            "model": "deepseek-chat",
            "messages": [{"role": "user", "content": "What is the capital of France? Answer with only the city name."}],
            "max_tokens": 10,
            "temperature": 0
        },
        "validations": [
            ("status_code", lambda r: r.status_code == 200),
            ("has_choices", lambda r: len(r.json()["choices"]) > 0),
            ("content_not_empty", lambda r: len(r.json()["choices"][0]["message"]["content"]) > 0),
            ("content_contains_paris", lambda r: "paris" in r.json()["choices"][0]["message"]["content"].lower()),
            ("has_usage", lambda r: r.json()["usage"]["total_tokens"] > 0),
            ("model_correct", lambda r: "deepseek" in r.json()["model"].lower()),
        ]
    },
    {
        "name": "function_calling",
        "request": {
            "model": "deepseek-chat",
            "messages": [{"role": "user", "content": "What is the weather in London?"}],
            "tools": [{
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get weather for a city",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "city": {"type": "string", "description": "City name"}
                        },
                        "required": ["city"]
                    }
                }
            }],
            "max_tokens": 100,
            "temperature": 0
        },
        "validations": [
            ("status_code", lambda r: r.status_code == 200),
            ("has_tool_calls", lambda r: len(r.json()["choices"][0]["message"].get("tool_calls", [])) > 0),
            ("tool_name_correct", lambda r: r.json()["choices"][0]["message"]["tool_calls"][0]["function"]["name"] == "get_weather"),
        ]
    },
    {
        "name": "json_mode",
        "request": {
            "model": "deepseek-chat",
            "messages": [{"role": "user", "content": "Output JSON: {\"name\": \"Alice\", \"age\": 30}"}],
            "max_tokens": 100,
            "temperature": 0,
            "response_format": {"type": "json_object"}
        },
        "validations": [
            ("status_code", lambda r: r.status_code == 200),
            ("valid_json", lambda r: json.loads(r.json()["choices"][0]["message"]["content"]) is not None),
        ]
    },
]

def run_inference_tests():
    results = []
    start_time = time.time()

    for tc in TEST_CASES:
        tc_start = time.time()
        try:
            resp = requests.post(
                f"{LITELLM_URL}/v1/chat/completions",
                headers=HEADERS,
                json=tc["request"],
                timeout=60
            )
            latency = (time.time() - tc_start) * 1000

            checks = []
            for check_name, check_fn in tc["validations"]:
                try:
                    passed = check_fn(resp)
                    checks.append({"check": check_name, "passed": passed})
                except Exception as e:
                    checks.append({"check": check_name, "passed": False, "error": str(e)})

            all_passed = all(c["passed"] for c in checks)
            results.append({
                "test": tc["name"],
                "passed": all_passed,
                "latency_ms": round(latency, 1),
                "checks": checks
            })
        except Exception as e:
            results.append({
                "test": tc["name"],
                "passed": False,
                "error": str(e),
                "latency_ms": round((time.time() - tc_start) * 1000, 1)
            })

    total_time = time.time() - start_time
    summary = {
        "total_tests": len(TEST_CASES),
        "passed": sum(1 for r in results if r["passed"]),
        "failed": sum(1 for r in results if not r["passed"]),
        "total_time_seconds": round(total_time, 1),
        "results": results
    }
    return summary

if __name__ == "__main__":
    results = run_inference_tests()
    print(json.dumps(results, indent=2))
    if results["failed"] > 0:
        exit(1)
```

### 7.2 Token Usage Validation

Verify the token usage in responses is within expected ranges:

```python
def validate_token_usage(response_json):
    """Check token usage is within expected bounds."""
    usage = response_json.get("usage", {})
    checks = []

    # Prompt tokens should be non-zero
    prompt_tokens = usage.get("prompt_tokens", 0)
    checks.append(("prompt_tokens_positive", prompt_tokens > 0))

    # Completion tokens should be non-zero (unless max_tokens=0)
    completion_tokens = usage.get("completion_tokens", 0)
    checks.append(("completion_tokens_positive", completion_tokens > 0))

    # Total should equal prompt + completion
    total_tokens = usage.get("total_tokens", 0)
    checks.append((
        "total_equals_sum",
        total_tokens == prompt_tokens + completion_tokens
    ))

    # Total should not exceed request max_tokens + prompt_tokens significantly
    # (allowing some overhead)
    checks.append((
        "total_reasonable",
        total_tokens <= prompt_tokens + 5000  # generous upper bound
    ))

    return all(passed for _, passed in checks), checks
```

### 7.3 Streaming Validation

```python
def validate_streaming_response():
    """Test SSE streaming end-to-end."""
    import sseclient  # pip install sseclient-py

    response = requests.post(
        f"{LITELLM_URL}/v1/chat/completions",
        headers=HEADERS,
        json={
            "model": "deepseek-chat",
            "messages": [{"role": "user", "content": "Count from 1 to 5."}],
            "stream": True,
            "max_tokens": 50
        },
        stream=True,
        timeout=30
    )

    events = []
    client = sseclient.SSEClient(response)
    for event in client.events():
        if event.data == "[DONE]":
            break
        events.append(json.loads(event.data))

    checks = []
    # We received some events
    checks.append(("received_events", len(events) > 0))
    # First event has a role
    if events:
        checks.append(("first_event_has_delta", "choices" in events[0]))
    # Last event before DONE has usage
    if len(events) > 1:
        last = events[-1]
        checks.append(("last_event_has_usage", "usage" in last and last["usage"]["total_tokens"] > 0))

    return all(passed for _, passed in checks), checks
```

### 7.4 Embedding Validation

```python
def validate_embedding():
    """Test embedding generation."""
    resp = requests.post(
        f"http://localhost:5001/v1/embeddings",
        headers={"Content-Type": "application/json"},
        json={
            "model": "text-embedding-3-small",  # or local model
            "input": "This is a test sentence for embedding validation."
        },
        timeout=30
    )
    data = resp.json()
    checks = []
    checks.append(("status_200", resp.status_code == 200))
    checks.append(("has_data", len(data.get("data", [])) > 0))
    if data.get("data"):
        embedding = data["data"][0]["embedding"]
        checks.append(("embedding_is_list", isinstance(embedding, list)))
        checks.append(("embedding_non_empty", len(embedding) > 0))
        checks.append(("embedding_has_floats", all(isinstance(x, (int, float)) for x in embedding)))
        # Check common dimensions (1536 for OpenAI ada-002, 3072 for text-embedding-3-large)
        checks.append(("embedding_dimension_valid", len(embedding) in [384, 768, 1024, 1536, 3072]))

    return all(passed for _, passed in checks), checks
```

### 7.5 Multi-Model Validation

Verify all configured models respond through the proxy:

```python
def validate_all_models():
    """Check every configured model responds."""
    # Get list of configured models
    models_resp = requests.get(
        f"{LITELLM_URL}/v1/models",
        headers=HEADERS,
        timeout=10
    )
    model_ids = [m["id"] for m in models_resp.json()["data"]]

    results = {}
    for model_id in model_ids:
        try:
            resp = requests.post(
                f"{LITELLM_URL}/v1/chat/completions",
                headers=HEADERS,
                json={
                    "model": model_id,
                    "messages": [{"role": "user", "content": "Say: OK"}],
                    "max_tokens": 5
                },
                timeout=30
            )
            if resp.status_code == 200:
                content = resp.json()["choices"][0]["message"]["content"]
                results[model_id] = {"status": "ok", "latency_ms": resp.elapsed.total_seconds() * 1000}
            else:
                results[model_id] = {"status": "error", "http_code": resp.status_code, "body": resp.text[:200]}
        except Exception as e:
            results[model_id] = {"status": "error", "exception": str(e)}

    return results
```

### 7.6 Latency SLA Validation

| Model | p50 Target | p95 Target | p99 Target | Check Interval |
|---|---|---|---|---|
| deepseek-chat (primary) | < 2s | < 5s | < 10s | Every 30s |
| deepseek-reasoner | < 5s | < 15s | < 30s | Every 120s |
| deepseek-chat (via OpenRouter) | < 3s | < 8s | < 15s | Every 60s |
| gpt-4o (via OpenRouter) | < 3s | < 8s | < 15s | Every 300s |
| Embedding (local) | < 200ms | < 500ms | < 1s | Every 60s |

---

## 8. AI-Specific Rollback Considerations

### 8.1 Risk Matrix for AI Deploy Changes

| Change Type | Risk Level | Rollback Speed | Impact if Failed | Token Cost of Failure |
|---|---|---|---|---|
| AI Worker code change | Medium | Fast (`pm2 restart`) | Single worker degraded | None (worker code) |
| LiteLLM config change (model list) | High | Fast (restore config + restart) | All AI requests potentially broken | Tokens wasted on failed requests during outage |
| LiteLLM config change (routing) | High | Fast (restore config + restart) | Wrong model routed, cost spike | High -- could route to expensive fallback |
| LiteLLM version upgrade | Medium | Medium (downgrade pip package) | Proxy may crash | Moderate |
| API key rotation | Critical | Immediate (revert env var) | All models unavailable | All requests fail |
| Embedding model change | Medium | Slow (re-index required) | Embedding quality degradation | Some wasted embedding tokens |
| New model onboarding | Low | Fast (remove from config) | Only new model calls fail | Low (new model likely low traffic) |

### 8.2 LiteLLM Config Rollback vs Worker Rollback

**LiteLLM Config Rollback (Fast -- < 30 seconds)**
```bash
# 1. Restore previous config
cp /opt/wheeler/litellm/config.yaml.previous /opt/wheeler/litellm/config.yaml
# 2. Graceful restart (zero-downtime if using PM2 cluster mode)
pm2 restart wheeler-litellm --update-env
# 3. Verify
curl -sf http://localhost:4000/health
```
- In-flight requests may get short errors during restart (typically < 2 seconds)
- PM2 cluster mode (multiple instances) can achieve true zero-downtime

**AI Worker Rollback (Slower -- 1-2 minutes)**
```bash
# 1. Checkout previous version
cd /opt/wheeler/workers && git checkout <previous-tag>
# 2. Reinstall dependencies if needed
pip install -r requirements.txt
# 3. Restart workers
pm2 restart wheeler-ai-worker-*
# 4. Run warmup on each worker
# 5. Verify health
```
- Workers must complete warmup before accepting traffic
- Rolling restart: restart one worker at a time, wait for health, proceed to next

### 8.3 Token Cost Implications of Failed Deployments

A failed AI deployment can waste tokens in several ways:

1. **Retry storms:** If a worker sends requests but the proxy is misconfigured, requests may fail and retry, consuming tokens without useful output
2. **Wrong model routing:** If config accidentally routes to an expensive model (GPT-4o at 35x cost), a rapid token burn can occur
3. **Infinite loops:** Buggy worker code might loop on LLM calls

**Safeguards:**
```yaml
# Litellm config: hard per-minute cost limits
litellm_settings:
  global_max_parallel_requests: 50
  max_budget: 500            # Hard stop if daily budget exceeded (USD)
  budget_duration: 1d

# Per-deployment cost limiting
model_list:
  - model_name: deepseek-chat
    litellm_params:
      model: openrouter/openai/gpt-4o
      max_budget: 10            # Max $10/day for fallback #2
      budget_duration: 1d
```

**Monitoring during deployment:**
- Watch token spend rate in dashboard Panel H during and 5 minutes after deploy
- Alert if spend rate increases more than 50% within 5 minutes of deploy

### 8.4 Circuit Breaker State During Rollback

When rolling back AI services:

1. **Preserve circuit breaker state:** Do not reset failure counts during rollback. The failure counts reflect real provider issues.
2. **If circuit is OPEN when rollback starts:** The rollback itself may need to route through fallback. This is expected.
3. **After rollback completes:** Run health validation (Section 7). If primary now healthy, circuit will close naturally via half-open probing.
4. **Manual circuit reset (emergency only):**
   ```bash
   # If circuit is stuck open but primary is known healthy:
   curl -X POST http://localhost:4000/cooldown/reset \
     -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
   ```

---

## 9. Monitoring AI Service Health

### 9.1 Key Metrics

| Metric Category | Specific Metric | Source | Alert Threshold |
|---|---|---|---|
| **Request Latency** | p50, p95, p99 per model | LiteLLM /metrics | p95 > 5s (warning), p95 > 10s (critical) |
| **Error Rate** | % of requests returning 4xx/5xx, by model | LiteLLM /metrics | > 5% (warning), > 15% (critical) |
| **Token Usage** | Tokens per minute, tokens per day, tokens per model | LiteLLM /metrics | Sudden spike > 2x baseline (warning) |
| **Circuit Breaker** | State per deployment (closed/half_open/open) | AI Health Monitor | Open > 5 min (warning), Open > 15 min (critical) |
| **Failover Count** | Times failover activated, duration per event | AI Health Monitor | > 10 events/day (warning) |
| **Cost** | Estimated USD per model per day | LiteLLM spend logs | Daily > budget threshold |
| **Model Availability** | Health check pass/fail per model | AI Health Monitor | Any model failing > 2 consecutive checks |
| **Worker Health** | Workers online, warmup status, error rate | PM2 + custom /metrics | < 50% healthy workers (critical) |
| **API Key Validity** | Days until API key expiry, balance remaining | Manual check + balance API | Balance < $50 (warning), Key expiring < 7 days (warning) |
| **Rate Limit Hits** | Count of 429 responses per model | LiteLLM /metrics | > 5/min (warning) |

### 9.2 Prometheus Metrics from LiteLLM

LiteLLM exposes a `/metrics` endpoint in Prometheus format. Key metrics to monitor:

```
# Request count by model
litellm_requests_total{model="deepseek-chat", status="success"} 15234
litellm_requests_total{model="deepseek-chat", status="failure"} 47

# Latency histogram by model
litellm_request_duration_seconds_bucket{model="deepseek-chat", le="1"} 8923
litellm_request_duration_seconds_bucket{model="deepseek-chat", le="5"} 14871
litellm_request_duration_seconds_bucket{model="deepseek-chat", le="10"} 15210

# Token counts
litellm_tokens_total{model="deepseek-chat", type="prompt"} 4582300
litellm_tokens_total{model="deepseek-chat", type="completion"} 1245600

# Spend in USD
litellm_spend_metric_total{model="deepseek-chat"} 123.45

# Rate limit hits
litellm_rate_limit_errors_total{model="deepseek-chat"} 12

# Deployment state
litellm_deployment_state{model="deepseek-chat", deployment="deepseek/deepseek-chat"} 1  # 1=healthy
litellm_deployment_cooled_down{model="deepseek-chat", deployment="deepseek/deepseek-chat"} 0
```

### 9.3 Dashboard Panel Designs for AI Health

**Panel H-1: AI Status Overview (top banner)**

```
+-- LiteLLM Proxy: [green dot] Healthy (uptime: 12d 4h) -- v0.8.2 -- PID: 12345 --+
|  DeepSeek Chat:  [green dot] Available  |  p95: 2.1s  |  Err: 0.3%  |  CB: CLOSED|
|  DeepSeek Reason: [green dot] Available  |  p95: 8.3s  |  Err: 1.2%  |  CB: CLOSED|
|  OpenRouter DS:   [green dot] Standby    |  p95: 3.1s  |  Err: 0.0%  |  CB: CLOSED|
|  GPT-4o Fallback:  [green dot] Standby   |  p95: 5.2s  |  Err: 0.0%  |  CB: CLOSED|
+-------------------------------------------------------------------------------+
```

**Panel H-2: Token Usage (24h bar chart)**

```
Tokens per hour (last 24h)
|
|          ██
|       ██ ██ ██
|    ██ ██ ██ ██ ██    ██
| ██ ██ ██ ██ ██ ██ ██ ██ ██    ██ ██
+---------------------------------------> Hour
  00  02  04  06  08  10  12  14  16  18  20  22
```

**Panel H-3: Latency Distribution (per model, last hour)**

```
deepseek-chat latency p50/p95/p99
|
|                                        p99: 4.2s
|                              p95: 2.1s
|                    p50: 0.8s
+---------------------------------------------->
```

**Panel H-4: Circuit Breaker Timeline**

```
Circuit Breaker Events (last 7 days)

deepseek-chat (primary):
  CLOSED ████████████████████████████████████████ 99.2%
  OPEN                        █ 0.8% (3 events)

openrouter/deepseek-chat (fallback #1):
  CLOSED ████████████████████████████████████████ 100%
```

### 9.4 Alert Rules for AI Services

#### Prometheus Alert Rules (prometheus_rules.yml)

```yaml
groups:
  - name: ai_services
    interval: 30s
    rules:
      # LiteLLM proxy down
      - alert: LiteLLMProxyDown
        expr: up{job="litellm"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "LiteLLM proxy is down on {{ $labels.instance }}"
          runbook: "https://wiki.internal/runbooks/litellm-down"

      # Model error rate high
      - alert: ModelErrorRateHigh
        expr: |
          rate(litellm_requests_total{status="failure"}[5m])
          / rate(litellm_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Model {{ $labels.model }} error rate is {{ $value | humanizePercentage }}"
          description: "Error rate for {{ $labels.model }} exceeds 5% threshold"

      # Model error rate critical
      - alert: ModelErrorRateCritical
        expr: |
          rate(litellm_requests_total{status="failure"}[5m])
          / rate(litellm_requests_total[5m]) > 0.15
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Model {{ $labels.model }} error rate CRITICAL at {{ $value | humanizePercentage }}"

      # Model latency high
      - alert: ModelLatencyHigh
        expr: histogram_quantile(0.95, rate(litellm_request_duration_seconds_bucket[5m])) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Model {{ $labels.model }} p95 latency is {{ $value }}s"

      # Model latency critical
      - alert: ModelLatencyCritical
        expr: histogram_quantile(0.95, rate(litellm_request_duration_seconds_bucket[5m])) > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Model {{ $labels.model }} p95 latency CRITICAL at {{ $value }}s"

      # Circuit breaker open
      - alert: CircuitBreakerOpen
        expr: litellm_deployment_cooled_down == 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Circuit breaker open for {{ $labels.deployment }} (cooled down)"

      # Circuit breaker open extended
      - alert: CircuitBreakerOpenExtended
        expr: litellm_deployment_cooled_down == 1
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "Circuit breaker open > 15min for {{ $labels.deployment }}"

      # Token spend spike
      - alert: TokenSpendSpike
        expr: |
          rate(litellm_spend_metric_total[15m]) * 3600
          > rate(litellm_spend_metric_total[1h]) * 3600 * 2
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Token spend rate has doubled vs hourly average"

      # Rate limit hits increasing
      - alert: RateLimitHitsIncreasing
        expr: rate(litellm_rate_limit_errors_total[5m]) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Rate limit errors at {{ $value }}/s for {{ $labels.model }}"

      # No recent requests (possible pipeline stall)
      - alert: NoRecentAIRequests
        expr: rate(litellm_requests_total[10m]) == 0
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "No AI requests in last 10 minutes -- possible pipeline stall"
```

---

## 10. AI Deployment Checklist

### Pre-Deployment

- [ ] **API Key Verification:** All API keys (DeepSeek, OpenRouter) are valid and have sufficient balance (> $50 each)
- [ ] **Config Review:** Proposed config.yaml changes reviewed by at least one other engineer
- [ ] **Config Backup:** Current config.yaml copied to config.yaml.previous-{date}
- [ ] **Canary Plan:** If deploying a risky change, canary deployment plan approved (see CANARY_DEPLOYMENT_PLAN.md)
- [ ] **Test Environment:** Changes validated in staging/AIOPS-dev environment first
- [ ] **Rollback Plan:** Specific rollback steps documented for this deployment
- [ ] **Monitoring Window:** At least one engineer available for 30 minutes post-deploy monitoring
- [ ] **Notification:** #ops-deploy channel notified of upcoming deployment
- [ ] **Token Budget:** Daily token spend budget verified; hard cap configured in LiteLLM
- [ ] **Health Baseline:** Current latency p95, error rate, and token usage recorded for comparison

### Deployment Execution

- [ ] **Deploy LiteLLM Config (if changed):**
  - [ ] Copy staging config to production
  - [ ] Run `config_syntax_validation` script
  - [ ] `pm2 restart wheeler-litellm --update-env`
  - [ ] Wait for process to show `online` (max 15 seconds)
  - [ ] Verify `/health` returns 200 with `status: healthy`
  - [ ] Verify `/v1/models` lists expected model count
  - [ ] Run test inference (Section 7.1) -- ALL tests must pass

- [ ] **Deploy AI Workers (if changed):**
  - [ ] Run `validate-ai-deps.sh` (Section 6.4) -- ALL checks must pass
  - [ ] Deploy utility workers first, wait for 50% healthy
  - [ ] Deploy classification workers, wait for 50% healthy
  - [ ] Deploy enrichment workers, wait for 50% healthy
  - [ ] Deploy real-time workers, wait for 100% healthy
  - [ ] Verify each worker passes warmup (Section 6.2)
  - [ ] Check worker logs for errors (`pm2 logs --lines 20 --nostream`)

- [ ] **Deploy Embedding Service (if changed):**
  - [ ] `pm2 restart wheeler-embedding --update-env`
  - [ ] Verify `/health` returns 200
  - [ ] Run embedding validation (Section 7.4)

- [ ] **Deploy AI Health Monitor (if changed):**
  - [ ] `sudo systemctl restart wheeler-ai-health`
  - [ ] Verify health checks running: `sudo journalctl -u wheeler-ai-health -f --lines 10`
  - [ ] Verify dashboard Panel H shows updated data

### Post-Deployment Verification (0-5 minutes)

- [ ] **Test Inference (Full Suite):** Run complete test suite from Section 7.1
- [ ] **Streaming Test:** Verify SSE streaming works end-to-end (Section 7.3)
- [ ] **Function Calling:** Verify function calling capability
- [ ] **Multi-Model:** Verify all configured models respond (Section 7.5)
- [ ] **Latency Check:** Confirm p95 latency within SLA for each model
- [ ] **Error Rate:** Check error rate has not increased from pre-deploy baseline

### Post-Deployment Verification (5-30 minutes)

- [ ] **Token Spend Rate:** Monitor token consumption rate -- should be within 20% of baseline
- [ ] **Worker Logs:** Check for any new error patterns in AI worker logs
- [ ] **Circuit Breaker:** Confirm all circuit breakers are CLOSED
- [ ] **Failover Count:** Confirm no unexpected failover events triggered
- [ ] **Dashboard Check:** All AI health panels showing green/healthy
- [ ] **Alert Silence:** No new AI-related alerts firing in dashboard

### Post-Deployment Verification (24 hours)

- [ ] **Daily Token Usage:** Compare to previous day -- investigate if > 50% increase
- [ ] **Daily Cost:** Compare to previous day -- investigate if > 50% increase
- [ ] **Error Rate (24h):** Should be < 2% overall
- [ ] **Latency (24h):** p95 should match or improve on pre-deploy baseline
- [ ] **User Reports:** Check for any AI-quality complaints from users

### Rollback Trigger Conditions

Initiate rollback if ANY of these occur during the monitoring window:

- [ ] Any critical health check fails (primary model unavailable, LiteLLM down)
- [ ] Error rate exceeds 10% for > 5 minutes
- [ ] Latency p95 exceeds SLA by 3x for > 5 minutes
- [ ] Token spend rate exceeds 5x baseline
- [ ] Circuit breaker opens for primary model
- [ ] More than 50% of AI workers report unhealthy
- [ ] Any test inference returns incorrect or garbage output

### Deployment Sign-Off

| Role | Name | Signature | Timestamp |
|---|---|---|---|
| **Deploying Engineer** | | | |
| **Reviewer (if config change)** | | | |
| **Post-Deploy Verifier** | | | |
| **24h Health Check** | | | |

---

## Appendix A: LiteLLM Troubleshooting Quick Reference

| Symptom | Likely Cause | First Check | Resolution |
|---|---|---|---|
| All requests failing | LiteLLM proxy down | `pm2 status wheeler-litellm` | `pm2 restart wheeler-litellm` |
| All requests failing, proxy up | API key expired or invalid | `pm2 logs wheeler-litellm --lines 20` for auth errors | Rotate API key, update env, restart |
| DeepSeek requests failing | DeepSeek API outage | `curl https://api.deepseek.com/v1/chat/completions` directly | Wait or manually force failover |
| High latency | Network issue or model overloaded | Check latency by model in dashboard Panel H | Route to alternate provider temporarily |
| 429 errors (rate limited) | Exceeded RPM/TPM limits | Check rate limit hits metric | Reduce request rate or increase limits |
| Token cost spike | Routing to expensive fallback | Check which provider is serving requests | Verify circuit breaker state |
| Model returns gibberish | Temperature too high or model issue | Test with temperature=0 | Lower temperature, switch model |
| Config changes not taking effect | LiteLLM caching old config | `pm2 restart wheeler-litellm --update-env` | Hard restart with `pm2 stop/start` |

---

## Appendix B: Useful Commands Reference

```bash
# LiteLLM status and control
pm2 status wheeler-litellm               # Process status
pm2 logs wheeler-litellm --lines 50      # Recent logs
pm2 restart wheeler-litellm              # Restart
pm2 restart wheeler-litellm --update-env # Restart with new env vars
pm2 stop wheeler-litellm                 # Stop
pm2 start wheeler-litellm                # Start

# Health checks
curl -s http://localhost:4000/health | jq .               # LiteLLM health
curl -s http://localhost:4000/v1/models | jq '.data | length'  # Model count
curl -s http://localhost:4000/metrics | grep litellm_     # Prometheus metrics

# Test inference (quick)
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' \
  | jq '{model: .model, content: .choices[0].message.content, latency: .usage}'

# AI worker status
pm2 list | grep wheeler-ai-worker        # All AI workers
pm2 logs wheeler-ai-worker-0 --lines 20  # Specific worker logs

# Token usage (today, from LiteLLM DB)
psql -d litellm -c "
  SELECT model_group,
         COUNT(*) as requests,
         SUM(prompt_tokens) as prompt_tok,
         SUM(completion_tokens) as completion_tok,
         ROUND(SUM(spend)::numeric, 4) as spend_usd
  FROM litellm_spend_logs
  WHERE start_time > CURRENT_DATE
  GROUP BY model_group
  ORDER BY spend_usd DESC;
"

# Circuit breaker status (via AI Health Monitor API)
curl -s http://localhost:9501/api/v1/circuit-breakers | jq .
```

---

*End of AI Deployment Strategy*
