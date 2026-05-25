---
name: embedding-service-local
description: "Local embedding service deployed at :8191 using all-MiniLM-L6-v2 (384-dim), pgvector table altered from 1536 to 384"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c464a89a-e107-4a3c-8f5b-3033636692a0
---

Local embedding service at 127.0.0.1:8191 using sentence-transformers all-MiniLM-L6-v2 (384 dimensions). OpenAI-compatible API at POST /v1/embeddings. pgvector table `vector_embeddings` altered from `vector(1536)` to `vector(384)` with IVFFlat cosine index.

**Why:** DeepSeek and Anthropic don't provide embeddings API. Local embedding model eliminates external API dependency, fits zero-trust architecture.

**How to apply:** Research cycle at /root/scripts/research-cycle.py calls 127.0.0.1:8191/v1/embeddings directly (not via LiteLLM). Source code at /root/deployment-engine/services/embedding-service/. PM2: `embedding-service` on ID ~79, port 8191. Model loads ~850MB RAM.
