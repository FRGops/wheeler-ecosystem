#!/usr/bin/env python3
"""Backfill semantic, deployment, and operational memory from live ecosystem state."""
import subprocess, json, sys
from datetime import datetime, timezone

DB = "frgcrm"
USER = "frgops"
NOW = datetime.now(timezone.utc).isoformat()

def pg(cmd):
    r = subprocess.run(["docker", "exec", "frgops-standby", "psql", "-U", USER, "-d", DB,
                        "-t", "-A", "-c", cmd], capture_output=True, text=True, timeout=15)
    return r.stdout.strip()

# ═══════════════════════════════════════════════════════════════
# SEMANTIC MEMORY — ecosystem concepts, services, domains
# ═══════════════════════════════════════════════════════════════
print("── Populating semantic_memory ──")

concepts = [
    # Intelligence domains
    ("Intelligence Domain", "Business Intelligence", "Strategic business metrics, KPI tracking, revenue analytics, and executive reporting across all Wheeler business units", ["KPI Tracking", "Revenue Analytics", "Executive Reporting"]),
    ("Intelligence Domain", "Infrastructure Intelligence", "Real-time infrastructure monitoring across Docker, PM2, networking, hardware, and cloud resources", ["Docker Monitoring", "PM2 Health", "Network Topology"]),
    ("Intelligence Domain", "Knowledge Graph", "Neo4j-powered ecosystem graph mapping 285+ nodes and 648+ relationships across servers, services, agents, and domains", ["Neo4j", "Graph Traversal", "Relationship Mapping"]),
    ("Intelligence Domain", "Memory Layer", "6-tier memory architecture: Redis L1, Neo4j L2, pgvector L3, PostgreSQL L4, ClickHouse L5, MinIO L6", ["Redis", "PostgreSQL", "pgvector", "ClickHouse"]),
    ("Intelligence Domain", "Lead Intelligence", "Real estate lead scoring, prioritization, and qualification for foreclosure and surplus fund opportunities", ["Lead Scoring", "Foreclosure Leads", "Surplus Fund Leads"]),
    ("Intelligence Domain", "Market Intelligence", "Real estate market trends, pricing analytics, competitor monitoring, and opportunity identification", ["Market Trends", "Competitor Analysis", "Pricing Data"]),

    # Memory tiers
    ("Architecture", "Memory Tier L1 - Redis", "Operational cache at 127.0.0.1:6379, 256MB maxmemory, allkeys-lru eviction. Used by LiteLLM for AI response caching and ecosystem-health for real-time state", ["Redis", "Cache", "LiteLLM"]),
    ("Architecture", "Memory Tier L2 - Neo4j", "Knowledge graph at bolt://127.0.0.1:7687, 285 nodes, 648 relationships, 13 label types. Stores ecosystem topology, agent registry, domain mapping", ["Neo4j", "Graph Database", "Cypher"]),
    ("Architecture", "Memory Tier L3 - pgvector", "Semantic vector search in PostgreSQL :5433, all-MiniLM-L6-v2 embeddings (384-dim), IVFFlat cosine index. Powers semantic retrieval for research cycle", ["pgvector", "Embeddings", "Semantic Search"]),
    ("Architecture", "Memory Tier L4 - PostgreSQL", "Relational memory at :5433, frgcrm database. episodic_memory (31 events), semantic_memory (concepts), deployment_memory, operational_memory tables", ["PostgreSQL", "Relational", "ACID"]),
    ("Architecture", "Memory Tier L5 - ClickHouse", "Time-series analytics at :8123. Stores long-term operational metrics, AI spend history, and PM2 performance trends", ["ClickHouse", "Time Series", "OLAP"]),
    ("Architecture", "Memory Tier L6 - MinIO", "Cold storage archive. S3-compatible object store for backup archives, historical logs, and compliance retention", ["MinIO", "S3", "Archive"]),

    # Core services
    ("Service", "wheeler-brain-api", "Central intelligence API at :8160. Neo4j graph queries, memory retrieval, hybrid search (graph+vector+keyword), domain intelligence", ["Neo4j", "FastAPI", "Memory Layer"]),
    ("Service", "executive-dashboard-api", "Executive dashboard at :8180. Live ecosystem data, intelligence command center, KPI metrics, Docker/PM2/LiteLLM monitoring", ["Dashboard", "FastAPI", "Monitoring"]),
    ("Service", "revenue-metrics-collector", "Revenue data collector at :8170. Stripe integration, MRR/ARR tracking, subscription analytics, payment monitoring", ["Stripe", "Revenue", "Metrics"]),
    ("Service", "embedding-service", "Local embedding service at :8191. all-MiniLM-L6-v2 (384-dim), OpenAI-compatible API. Semantic text embeddings for memory layer", ["Embeddings", "Sentence Transformers", "Vector Search"]),
    ("Service", "litellm", "AI model proxy at :4049. Routes to DeepSeek (chat, reasoner) and Anthropic (Claude Sonnet, Opus). Redis-cached, rate-limited", ["AI Proxy", "Model Routing", "Redis Cache"]),

    # AI Models
    ("AI Model", "deepseek-chat", "DeepSeek V3 chat model via LiteLLM. 1000 RPM. General-purpose conversational AI for Wheeler agents", ["DeepSeek", "Chat", "General Purpose"]),
    ("AI Model", "deepseek-reasoner", "DeepSeek V4 Pro reasoning model via LiteLLM. 500 RPM. Complex reasoning and analysis tasks", ["DeepSeek", "Reasoning", "Analysis"]),
    ("AI Model", "claude-sonnet-4", "Anthropic Claude Sonnet 4 via LiteLLM. 100 RPM. Code generation, architecture design, agent coordination", ["Anthropic", "Claude", "Code Generation"]),
    ("AI Model", "claude-opus-4", "Anthropic Claude Opus 4 via LiteLLM. 50 RPM. Complex multi-step reasoning, strategic planning", ["Anthropic", "Claude", "Strategic Reasoning"]),

    # Zero-trust architecture
    ("Architecture", "Zero-Trust Network", "All services bind 127.0.0.1 only. UFW default-deny. Tailscale mesh for cross-server communication. No public exposure", ["UFW", "Tailscale", "127.0.0.1"]),
    ("Architecture", "PM2 Process Management", "27 PM2 processes managed with delete+start pattern for clean env propagation. Auto-resurrect enabled. Watchdog every 5min", ["PM2", "Process Management", "Auto-Restart"]),
    ("Architecture", "Autonomous Workflows", "8 cron-driven autonomous workflows: memory sync (7min), research cycle (daily), Neo4j backup (daily), health checks (hourly), watchdog (5min)", ["Cron", "Automation", "Self-Healing"]),
]

for concept_type, concept, definition, related in concepts:
    definition_esc = definition.replace("'", "''")
    related_json = json.dumps(related)
    existing = pg(f"SELECT count(*) FROM semantic_memory WHERE concept = '{concept}' AND domain = '{concept_type}'")
    if existing == "0":
        pg(f"""INSERT INTO semantic_memory (concept, definition, domain, related_concepts, confidence)
               VALUES ('{concept}', '{definition_esc}', '{concept_type}', '{related_json}', 1.0)""")
        print(f"  + {concept_type}: {concept}")
    else:
        print(f"  ~ {concept_type}: {concept} (exists)")

# ═══════════════════════════════════════════════════════════════
# DEPLOYMENT MEMORY — current deployment state of all services
# ═══════════════════════════════════════════════════════════════
print("\n── Populating deployment_memory ──")

try:
    result = subprocess.run(["pm2", "jlist"], capture_output=True, text=True, timeout=10)
    procs = json.loads(result.stdout)
    for p in procs:
        name = p.get("name", "?")
        pid = p.get("pid", 0)
        env = p.get("pm2_env", {})
        status = env.get("status", "?")
        restarts = env.get("restart_time", 0)
        uptime_sec = int(env.get("pm_uptime_time", 0))
        version = env.get("version", "N/A") or "N/A"

        existing = pg(f"SELECT count(*) FROM deployment_memory WHERE service_name = '{name}' ORDER BY deployed_at DESC LIMIT 1")
        pg(f"""INSERT INTO deployment_memory (service_name, version, deployed_at, deployed_by, success, preflight_results, postdeploy_results, notes)
               VALUES ('{name}', '{version}', '{NOW}', 'wheeler-deploy-agent', true,
                       '{{"pm2_status": "{status}", "uptime_seconds": {uptime_sec}}}'::jsonb,
                       '{{"pm2_status": "{status}", "pid": {pid}}}'::jsonb,
                       'Memory backfill — {NOW}. Status: {status}, restarts: {restarts}')""")
    print(f"  Deployed: {len(procs)} services recorded")
except Exception as e:
    print(f"  Error: {e}")

# ═══════════════════════════════════════════════════════════════
# OPERATIONAL MEMORY — known incidents and resolutions
# ═══════════════════════════════════════════════════════════════
print("\n── Populating operational_memory ──")

incidents = [
    ("pgvector_compilation", "P3", "frgops-standby",
     "pgvector extension not available for Alpine PostgreSQL 16.14 container — no apk package exists",
     "Compiled pgvector 0.8.2 from source inside container: git clone, make, manual copy of .control and .sql files. IVFFlat cosine index created on vector_embeddings table.",
     "Alpine containers may lack pre-built extensions — maintain source-compilation procedure in runbooks",
     2400),
    ("litellm_prisma_migration", "P2", "litellm",
     "LiteLLM crashed on restart after adding Redis cache config — Prisma migration attempted connection to COREDB :5432 using stale DATABASE_URL env var",
     "Started LiteLLM with DATABASE_URL='' to suppress Prisma migration. Redis cache configured via YAML (redis_host: 127.0.0.1) rather than env vars.",
     "PM2 env persistence can carry stale DATABASE_URL across restarts — always use delete+start pattern for LiteLLM config changes",
     900),
    ("embedding_pipeline_blocked", "P2", "research-cycle",
     "Research cycle embedding generation failed — DeepSeek and Anthropic don't provide embeddings API. LiteLLM /v1/embeddings returned 404",
     "Deployed local embedding service using all-MiniLM-L6-v2 (384-dim) at :8191 with OpenAI-compatible API. pgvector table altered from 1536 to 384 dims. Research cycle updated to call embedding service directly.",
     "Don't assume AI providers support all endpoint types — verify API coverage before designing pipelines. Local models are safer for zero-trust architecture",
     3600),
    ("docker_healthcheck_false_positive", "P3", "executive-dashboard-api",
     "Dashboard alerts incorrectly flagged 2 containers as unhealthy — they lacked HEALTHCHECK directives but were running fine",
     "Changed alert logic from 'total - healthy = unhealthy' to explicit docker ps --filter 'health=unhealthy'. Added get_docker_no_healthcheck() for informational tracking.",
     "Subtraction-based health metrics are fragile — always explicitly query for the failure state, not its complement",
     600),
    ("wheeler_brain_neo4j_auth", "P1", "wheeler-brain-api",
     "Wheeler Brain API showed Neo4j 'degraded' — two stacked failures: neo4j Python package not installed AND NEO4J_PASSWORD missing from PM2 env",
     "pip install neo4j on host. Added NEO4J_PASSWORD to ecosystem.config.js env block. Restarted with delete+start pattern.",
     "PM2 env:{} blocks override .env files — every required env var must be explicitly listed. Missing env vars default to empty string, not error",
     1800),
]

for inc_type, severity, service, root_cause, resolution, principle, mttr in incidents:
    root_esc = root_cause.replace("'", "''")
    res_esc = resolution.replace("'", "''")
    princ_esc = principle.replace("'", "''")
    pg(f"""INSERT INTO operational_memory (incident_type, severity, service_name, root_cause, resolution, principle_derived, mttr_seconds)
           VALUES ('{inc_type}', '{severity}', '{service}', '{root_esc}', '{res_esc}', '{princ_esc}', {mttr})""")
    print(f"  + {inc_type}: {service} (MTTR {mttr}s, {severity})")

# ═══════════════════════════════════════════════════════════════
# VERIFY
# ═══════════════════════════════════════════════════════════════
print("\n═══ Memory Tables After Population ═══")
for table in ["episodic_memory", "semantic_memory", "deployment_memory", "operational_memory", "vector_embeddings"]:
    count = pg(f"SELECT count(*) FROM {table}")
    print(f"  {table}: {count}")
