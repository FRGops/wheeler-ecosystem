"""Wheeler Local Embedding Service — 127.0.0.1:8191. OpenAI-compatible API."""
import json
from sentence_transformers import SentenceTransformer
from fastapi import FastAPI, Request
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Wheeler Embedding Service", version="1.0.0")
model = SentenceTransformer("all-MiniLM-L6-v2")

class EmbeddingRequest(BaseModel):
    model: str = "local-embedding"
    input: str | list

class EmbeddingResponse(BaseModel):
    object: str = "list"
    data: list
    model: str = "local-embedding"

@app.get("/health")
async def health():
    return {"status": "healthy", "model": "all-MiniLM-L6-v2", "dimensions": 384}

@app.post("/v1/embeddings")
async def embeddings(req: EmbeddingRequest):
    texts = [req.input] if isinstance(req.input, str) else req.input
    vectors = model.encode(texts, normalize_embeddings=True)
    data = [{"object": "embedding", "index": i, "embedding": v.tolist()} for i, v in enumerate(vectors)]
    return {"object": "list", "data": data, "model": "local-embedding"}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8191, log_level="info")
