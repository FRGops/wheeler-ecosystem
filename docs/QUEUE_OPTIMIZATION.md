# Wheeler Ecosystem Queue + Worker Optimization

> **Phase 10 — Queue + Worker Optimization**  
> Principal Infrastructure Optimization Engineering  
> Date: 2026-05-23

---

## Executive Summary

**Critical Gap**: The Wheeler ecosystem has **no distributed task queue**. All background work runs through:
1. **PM2 fork-mode processes** (agent-svc workers)
2. **Python ThreadPoolExecutor** (OCR pipeline, 4 threads)
3. **Direct process spawning** (prediction-radar-worker)

This means:
- No retry logic for failed tasks
- No dead-letter queue
- No task prioritization
- No workload visibility
- No backpressure handling
- No horizontal scaling of workers
- Lost work on process crash

---

## Current Architecture Assessment

### What Exists

| Component | Type | Concurrency | Queue | Retry | Visibility |
|---|---|---|---|---|---|
| agent-svc × 9 | PM2 fork | 1 per process | None (fire & forget) | PM2 auto-restart only | PM2 monit |
| prediction-radar-worker | PM2 fork | PR_WORKER_CONCURRENCY=4 | Internal only | None | PM2 monit |
| OCR pipeline | ThreadPoolExecutor | 4 threads | In-memory | None | None |
| OPENCLAW | PM2 fork | MAX_WORKERS=8 | Internal only | None | None |
| event-bus-relay | PM2 fork | 1 | Internal event loop | None | PM2 monit |

### What's Missing

| Capability | Status | Impact |
|---|---|---|
| Distributed task queue | Missing | Cannot scale workers horizontally |
| Task prioritization | Missing | All tasks equal priority |
| Dead-letter queue | Missing | Failed tasks silently lost |
| Retry with backoff | Missing | Transient failures become permanent |
| Rate limiting | Missing | No protection against downstream overload |
| Task timeout | Missing | Stuck tasks block workers forever |
| Workflow orchestration | Temporal exists on EDGE | Underutilized |
| Queue monitoring | Missing | No visibility into queue depth/age |
| Graceful degradation | Missing | Overload cascades through system |

---

## Recommended Architecture

### For AI/Agent Tasks: Redis + BullMQ (Node.js agents) or ARQ (Python agents)

```
┌──────────────────────────────────────────────────────────┐
│                    TASK INGESTION                          │
│  API endpoints → validate → enqueue                      │
│  Event bus → event → enqueue                             │
│  Cron scheduler → scheduled job → enqueue                │
└─────────────┬────────────────────────────────────────────┘
              │
┌─────────────▼────────────────────────────────────────────┐
│              REDIS QUEUE (COREDB)                         │
│  Queue: agent-tasks (priority 1-10)                      │
│  Queue: ocr-tasks (CPU-intensive)                        │
│  Queue: notification-tasks (low priority)                │
│  Queue: enrichment-tasks (medium priority)               │
│  Queue: dlq (dead letter, manual review)                 │
└─────────────┬────────────────────────────────────────────┘
              │
┌─────────────▼────────────────────────────────────────────┐
│                  WORKER POOL (AIOPS)                       │
│  agent-worker-1 → process queue:agent-tasks               │
│  agent-worker-2 → process queue:agent-tasks               │
│  agent-worker-3 → process queue:agent-tasks               │
│  ocr-worker-1   → process queue:ocr-tasks                 │
│  ocr-worker-2   → process queue:ocr-tasks                 │
│  enrichment-worker-1 → process queue:enrichment-tasks     │
│  enrichment-worker-2 → process queue:enrichment-tasks     │
└──────────────────────────────────────────────────────────┘
```

---

## Queue Design per Workload Type

### 1. AI Agent Tasks (agent-svc workers)
```
Priority: 1-5 (critical=1, normal=3, background=5)
Concurrency: 3-5 per worker
Retry: 3 attempts, exponential backoff (1s, 5s, 25s)
Timeout: 120s per task
Dead Letter: After 3 failures → DLQ for manual review
Rate Limit: 10 tasks/second per worker
```

### 2. OCR/Document Processing
```
Priority: 3-7
Concurrency: 2 per worker (CPU-bound)
Retry: 2 attempts, 30s backoff
Timeout: 300s per document
Dead Letter: After 2 failures → DLQ
Rate Limit: 5 tasks/second
```

### 3. Claimant Enrichment
```
Priority: 2-6
Concurrency: 4 per worker (I/O-bound)
Retry: 3 attempts, exponential (2s, 10s, 60s)
Timeout: 60s per enrichment
Dead Letter: After 3 failures → DLQ
Batch Size: 50 claimants per batch
```

### 4. Notifications/Email
```
Priority: 5-10 (lowest priority)
Concurrency: 8 per worker
Retry: 2 attempts, 60s backoff
Timeout: 30s
Rate Limit: 20/second (respect email provider limits)
```

---

## Python ARQ Implementation (Recommended for Python services)

### Worker Definition

```python
# /root/wheeler-autonomous-ops/queue/worker.py
from arq import create_pool
from arq.connections import RedisSettings, ArqRedis
from pydantic import BaseModel
from typing import Optional
import asyncio

class QueueConfig:
    """Central queue configuration for Wheeler ecosystem."""
    
    REDIS_URL = "redis://5.78.210.123:6379"
    
    QUEUES = {
        "agent_tasks": {"max_retries": 3, "timeout": 120, "concurrency": 5},
        "ocr_tasks": {"max_retries": 2, "timeout": 300, "concurrency": 2},
        "enrichment_tasks": {"max_retries": 3, "timeout": 60, "concurrency": 4},
        "notification_tasks": {"max_retries": 2, "timeout": 30, "concurrency": 8},
    }
    
    RETRY_BACKOFF = [1, 5, 25]  # seconds, exponential
    DEAD_LETTER_QUEUE = "dlq"
    
    @classmethod
    def redis_settings(cls) -> RedisSettings:
        return RedisSettings(host="5.78.210.123", port=6379)


# ---- Worker functions ----

async def process_agent_task(ctx, task_id: str, payload: dict) -> dict:
    """Execute an AI agent task with retry and timeout."""
    agent_type = payload.get("agent_type")
    params = payload.get("params", {})
    
    # Call appropriate agent
    result = await execute_agent(agent_type, **params)
    
    return {"task_id": task_id, "status": "completed", "result": result}


async def process_ocr_document(ctx, doc_id: str, file_path: str) -> dict:
    """Process a document through OCR pipeline."""
    result = await run_ocr_pipeline(file_path)
    return {"doc_id": doc_id, "status": "completed", "pages": result}


async def process_enrichment_batch(ctx, batch_id: str, claimant_ids: list[str]) -> dict:
    """Enrich a batch of claimants."""
    results = {}
    for cid in claimant_ids:
        results[cid] = await enrich_claimant(cid)
    return {"batch_id": batch_id, "status": "completed", "enriched": len(results)}


async def process_notification(ctx, notification_id: str, 
                                channel: str, recipient: str, 
                                content: dict) -> dict:
    """Send notification through specified channel."""
    await send_notification(channel, recipient, content)
    return {"notification_id": notification_id, "status": "sent"}


# ---- Dead Letter Handler ----

async def handle_dead_letter(ctx, original_task: str, error: str, 
                               attempts: int, payload: dict) -> dict:
    """Log failed tasks to DLQ for manual review."""
    await log_to_dlq(
        task=original_task,
        error=error,
        attempts=attempts,
        payload=payload,
        timestamp=time.time()
    )
    return {"status": "logged_to_dlq"}
```

### Worker Configuration (PM2)

```javascript
// Single ARQ worker pool managed by PM2
{
  name: "queue-worker",
  script: "queue/worker.py",
  interpreter: "python3",
  instances: 4,           // 4 worker processes
  exec_mode: "cluster",
  max_memory_restart: "512M",
  env: {
    REDIS_URL: "redis://5.78.210.123:6379",
    WORKER_CONCURRENCY: "16"  // 4 processes × 4 async tasks each
  }
}
```

---

## Node.js BullMQ Implementation (for JavaScript agent-svc workers)

### Queue Setup

```typescript
// /root/wheeler-autonomous-ops/queue/bullmq-setup.ts
import { Queue, Worker, QueueScheduler } from 'bullmq';
import IORedis from 'ioredis';

const connection = new IORedis({
  host: '5.78.210.123',
  port: 6379,
  maxRetriesPerRequest: null,
  enableReadyCheck: false,
});

// Queue definitions with priorities
export const agentQueue = new Queue('agent-tasks', {
  connection,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 1000 },
    timeout: 120000,
    removeOnComplete: { age: 3600 },     // Keep 1 hour for auditing
    removeOnFail: { age: 86400 },         // Keep 1 day for debugging
  },
});

export const ocrQueue = new Queue('ocr-tasks', { connection });
export const enrichmentQueue = new Queue('enrichment-tasks', { connection });
export const notificationQueue = new Queue('notification-tasks', { connection });

// Worker definition
const agentWorker = new Worker('agent-tasks', async (job) => {
  const { agentType, params } = job.data;
  
  // Progress reporting
  await job.updateProgress(10);
  
  const result = await executeAgent(agentType, params);
  
  await job.updateProgress(100);
  return result;
}, {
  connection,
  concurrency: 5,
  limiter: {
    max: 10,          // 10 tasks
    duration: 1000,   // per second
  },
});
```

---

## Queue Monitoring Dashboard

### Metrics to Expose

```python
# Endpoint: GET /api/queue/health
async def get_queue_health():
    """Expose queue metrics for monitoring."""
    redis = await get_redis()
    
    metrics = {}
    for queue_name in ["agent-tasks", "ocr-tasks", "enrichment-tasks", "notification-tasks"]:
        waiting = await redis.llen(f"arq:queue:{queue_name}")
        active = await redis.scard(f"arq:in-progress")
        dead = await redis.llen(f"arq:dead-letter:{queue_name}")
        
        metrics[queue_name] = {
            "waiting": waiting,
            "active": active,
            "dead_letter": dead,
            "status": "healthy" if waiting < 1000 else "backlogged",
            "estimated_latency_seconds": waiting * 0.5 if waiting > 0 else 0
        }
    
    return {
        "timestamp": time.time(),
        "queues": metrics,
        "overall_status": "healthy" if all(m["status"] == "healthy" for m in metrics.values()) else "degraded"
    }
```

### Alerting Thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| Queue depth | > 500 waiting | > 2000 waiting | Scale workers up |
| Task age | > 60s old | > 300s old | Investigate stuck tasks |
| Dead letter growth | > 10/hour | > 50/hour | Check downstream dependencies |
| Worker utilization | > 80% | > 95% | Add worker instances |
| Retry rate | > 5% | > 20% | Check downstream health |

---

## Migration Path: Fire-and-Forget → Proper Queues

### Phase 1: Shadow Queue (Week 1)
- Deploy Redis queue infrastructure on COREDB
- Run new queue workers in parallel with existing PM2 processes
- Enqueue tasks to both old and new systems
- Compare results, measure reliability
- Zero production impact

### Phase 2: Gradual Cutover (Week 2-3)
- Route 10% of traffic to queue workers
- Monitor for errors, latency, dropped tasks
- Increase to 50%, then 100% per workload type
- Keep old PM2 processes as hot standby

### Phase 3: Cleanup (Week 4)
- Remove old fire-and-forget patterns
- Decommission redundant PM2 worker processes
- Document new queue architecture

---

## Leveraging Existing Temporal (on EDGE)

The EDGE server already runs **Temporal Server** (temporal-server Docker container using 67% CPU). Temporal is an enterprise workflow orchestration engine perfectly suited for:

- Multi-step AI agent workflows
- Saga pattern for distributed transactions
- Long-running claimant processing pipelines
- Scheduled/recurring jobs
- Complex retry and compensation logic

### Temporal Use Cases

| Workflow | Why Temporal | Priority |
|---|---|---|
| Claimant intake pipeline | Multi-step, requires compensation on failure | HIGH |
| AI agent orchestration | Long-running, needs heartbeating | HIGH |
| County adapter sync | Scheduled, needs retry with backoff | MEDIUM |
| Revenue calculation | Saga pattern, multiple services involved | MEDIUM |
| Batch notification | Fan-out, needs rate limiting | LOW |

---

## Resource Allocation

### Queue Infrastructure on COREDB

| Resource | Allocation | Rationale |
|---|---|---|
| Redis memory for queues | 200MB | Queue payloads + job data |
| Redis connections | 50 max | Workers + producers + monitoring |
| CPU overhead | < 5% of COREDB | Redis is I/O-bound for queue ops |
| Disk (RDB persistence) | Included in existing Redis | Queue state persisted via RDB |

### Worker Infrastructure on AIOPS

| Worker Type | Instances | Memory per Instance | Total Memory | CPU Cores |
|---|---|---|---|---|
| Agent worker | 3 | 256MB | 768MB | 3 |
| OCR worker | 2 | 512MB | 1024MB | 2 |
| Enrichment worker | 2 | 256MB | 512MB | 2 |
| Notification worker | 1 | 128MB | 128MB | 1 |
| **Total** | **8** | — | **~2.4GB** | **8 cores** |

This replaces 9 separate PM2 agent-svc processes (~1GB total) with a unified queue system that provides retry, visibility, backpressure, and horizontal scalability.

---

## Implementation Checklist

### Immediate (24 hours)
- [ ] Audit all task-like operations in agent-svc processes
- [ ] Document task flows: input → processing → output → failure modes
- [ ] Identify which tasks are idempotent (safe to retry)

### Short-term (7 days)
- [ ] Deploy Redis queue infrastructure on COREDB
- [ ] Implement ARQ worker prototype for 1 workload type
- [ ] Add queue health endpoint to monitoring
- [ ] Configure Grafana dashboard for queue metrics

### Medium-term (30 days)
- [ ] Migrate all agent-svc tasks to queue workers
- [ ] Implement dead-letter queue with admin UI
- [ ] Set up queue alerts (Prometheus → AlertManager)
- [ ] Document queue operations playbook

### Long-term (90 days)
- [ ] Evaluate Temporal for complex workflows
- [ ] Implement priority-based queue isolation
- [ ] Add queue rate limiting per tenant
- [ ] Horizontal worker auto-scaling

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Redis single point of failure | Low | Critical | Redis sentinel/replication on COREDB |
| Queue backlog during outage | Medium | High | Backpressure + consumer pause |
| Task duplication | Low | Medium | Idempotency keys, deduplication |
| Worker memory leaks | Medium | Medium | PM2 max_memory_restart on queue workers |
| Lost tasks during migration | Low | High | Shadow queue + dual-write during cutover |

---

## Templates Generated

- `/root/templates/queue/arq-worker.py` — Python ARQ worker template
- `/root/templates/queue/bullmq-setup.ts` — Node.js BullMQ setup
- `/root/templates/queue/queue-health-endpoint.py` — Monitoring endpoint
- `/root/templates/queue/pm2-queue-workers.config.js` — PM2 config for queue workers
- `/root/templates/queue/apply-queue-optimizations.sh` — Deployment script
