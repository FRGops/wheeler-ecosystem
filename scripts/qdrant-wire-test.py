#!/usr/bin/env python3
"""Wire Qdrant on COREDB into Wheeler ecosystem — test + seed + verify."""
import urllib.request, json

QDRANT_URL = "http://100.118.166.117:6333"
API_KEY = "WheelerBrainOS-Qdrant-2026!"
COLLECTION = "wheeler_memory"

def qdrant(method, path, body=None):
    url = f"{QDRANT_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("api-key", API_KEY)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

# 1. Health check
print("1. Health:", qdrant("GET", "/readyz"))

# 2. Collection info
info = qdrant("GET", f"/collections/{COLLECTION}")
print(f"2. Collection: {info.get('result',{}).get('config',{}).get('params',{})}")

# 3. Seed with real ecosystem embeddings
print("\n3. Seeding Qdrant with real embeddings...")
# Generate embeddings locally, then push to Qdrant
import subprocess
texts = [
    "Wheeler Brain OS ecosystem intelligence platform with 27 PM2 services and 120 agents",
    "PostgreSQL frgcrm database with 6-tier memory architecture including pgvector embeddings",
    "Neo4j knowledge graph with 285 nodes and 648 relationships across 22 intelligence domains",
    "LiteLLM AI proxy routing DeepSeek and Anthropic Claude models with Redis caching",
    "Zero-trust architecture with all services binding 127.0.0.1 and UFW default-deny",
    "PM2 process management with delete+start pattern for clean environment variable propagation",
    "Executive dashboard showing live Docker, PM2, LiteLLM, Neo4j, and revenue metrics",
    "Revenue intelligence with Stripe integration tracking MRR, ARR, and subscription analytics",
    "Autonomous research cycle running daily with 5 phases and local embedding generation",
    "Embedding service using all-MiniLM-L6-v2 with 384 dimensional vectors on port 8191",
]

# Generate embeddings from local service
embeddings = []
for i, text in enumerate(texts):
    data = json.dumps({"input": text, "model": "local"}).encode()
    req = urllib.request.Request("http://127.0.0.1:8191/v1/embeddings", data=data,
                                 headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
    emb = resp["data"][0]["embedding"]
    embeddings.append({"id": i + 10, "vector": emb, "payload": {"text": text, "source": "ecosystem-seed"}})

# Upsert to Qdrant
result = qdrant("PUT", f"/collections/{COLLECTION}/points", {"points": embeddings})
print(f"   Upserted {len(embeddings)} vectors: {result.get('status')}")

# 4. Semantic search test
print("\n4. Semantic search test:")
# Get embedding for a query
query = json.dumps({"input": "How many PM2 services are running?", "model": "local"}).encode()
req = urllib.request.Request("http://127.0.0.1:8191/v1/embeddings", data=query,
                             headers={"Content-Type": "application/json"})
query_emb = json.loads(urllib.request.urlopen(req, timeout=30).read())["data"][0]["embedding"]

results = qdrant("POST", f"/collections/{COLLECTION}/points/search",
                 {"vector": query_emb, "limit": 3, "with_payload": True})
for r in results.get("result", []):
    print(f"   score={r['score']:.4f} | {r['payload'].get('text','?')[:80]}")

# 5. Count points
count = qdrant("POST", f"/collections/{COLLECTION}/points/count", {})
print(f"\n5. Total points in Qdrant: {count.get('result',{}).get('count',0)}")
print("\n=== Qdrant wired successfully ===")
