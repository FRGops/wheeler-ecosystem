"""AI Ops SaaS API — Multi-tenant platform for infrastructure management."""
import os
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="AI Ops SaaS API", version="1.0.0")

TENANTS_DIR = Path("/opt/aiops-saas/tenants")
TENANTS_DIR.mkdir(parents=True, exist_ok=True)
TENANTS_FILE = TENANTS_DIR / "tenants.json"

TIER_LIMITS = {"starter": 8, "pro": 4, "enterprise": 2, "agency": 1}
TIER_PRICES = {"starter": 99, "pro": 499, "enterprise": 1999, "agency": 3999}

# ── Models ──────────────────────────────────────────────────────────────────

class TenantCreate(BaseModel):
    tenant_id: str
    tier: str  # starter | pro | enterprise | agency
    email: str

class TenantStatus(BaseModel):
    tenant_id: str
    tier: str
    email: str
    status: str
    created_at: str
    provisioned_at: Optional[str] = None

# ── Tenant store ────────────────────────────────────────────────────────────

def load_tenants() -> dict:
    if TENANTS_FILE.exists():
        return json.loads(TENANTS_FILE.read_text())
    return {"tenants": {}}

def save_tenants(data: dict):
    TENANTS_FILE.write_text(json.dumps(data, indent=2, default=str))

def seed_demo_tenants():
    """Seed with demo tenants if file doesn't exist."""
    if not TENANTS_FILE.exists():
        now = datetime.now(timezone.utc).isoformat()
        data = {
            "tenants": {
                "demo-starter": {"tenant_id": "demo-starter", "tier": "starter", "email": "demo@example.com", "status": "active", "created_at": now, "provisioned_at": now},
                "acme-corp": {"tenant_id": "acme-corp", "tier": "enterprise", "email": "ops@acme-corp.com", "status": "active", "created_at": now, "provisioned_at": now},
                "agency-one": {"tenant_id": "agency-one", "tier": "agency", "email": "admin@agency-one.com", "status": "active", "created_at": now, "provisioned_at": now},
                "startup-io": {"tenant_id": "startup-io", "tier": "pro", "email": "devs@startup-io.com", "status": "provisioning", "created_at": now, "provisioned_at": None},
            }
        }
        save_tenants(data)

seed_demo_tenants()

# ── Helpers ─────────────────────────────────────────────────────────────────

def _tier_usage(tier: str) -> int:
    data = load_tenants()
    return sum(1 for t in data["tenants"].values() if t["tier"] == tier and t["status"] != "deprovisioned")

def _validate_tier(tier: str) -> bool:
    return tier in TIER_LIMITS

# ── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "aiops-saas-api", "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/tenants")
async def list_tenants():
    data = load_tenants()
    return {"tenants": list(data["tenants"].values()), "count": len(data["tenants"]), "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/tenants/{tenant_id}")
async def get_tenant(tenant_id: str):
    data = load_tenants()
    if tenant_id not in data["tenants"]:
        raise HTTPException(status_code=404, detail=f"Tenant {tenant_id} not found")
    return data["tenants"][tenant_id]

@app.get("/api/v1/tenants/{tenant_id}/status")
async def get_tenant_status(tenant_id: str):
    data = load_tenants()
    if tenant_id not in data["tenants"]:
        raise HTTPException(status_code=404, detail=f"Tenant {tenant_id} not found")
    t = data["tenants"][tenant_id]
    return {"tenant_id": t["tenant_id"], "status": t["status"], "tier": t["tier"], "provisioned_at": t.get("provisioned_at")}

@app.post("/api/v1/tenants")
async def create_tenant(req: TenantCreate):
    if not _validate_tier(req.tier):
        raise HTTPException(status_code=400, detail=f"Invalid tier: {req.tier}. Valid: {list(TIER_LIMITS.keys())}")

    data = load_tenants()
    if req.tenant_id in data["tenants"]:
        existing = data["tenants"][req.tenant_id]
        if existing["status"] != "deprovisioned":
            raise HTTPException(status_code=409, detail=f"Tenant {req.tenant_id} already exists")

    usage = _tier_usage(req.tier)
    limit = TIER_LIMITS[req.tier]
    if usage >= limit:
        raise HTTPException(status_code=429, detail=f"Tier {req.tier} at capacity ({usage}/{limit})")

    now = datetime.now(timezone.utc).isoformat()
    data["tenants"][req.tenant_id] = {
        "tenant_id": req.tenant_id, "tier": req.tier, "email": req.email,
        "status": "provisioning", "created_at": now, "provisioned_at": None
    }
    save_tenants(data)
    return {"tenant_id": req.tenant_id, "status": "provisioning", "message": "Provisioning initiated"}

@app.delete("/api/v1/tenants/{tenant_id}")
async def delete_tenant(tenant_id: str, force: bool = False):
    data = load_tenants()
    if tenant_id not in data["tenants"]:
        raise HTTPException(status_code=404, detail=f"Tenant {tenant_id} not found")
    if not force:
        raise HTTPException(status_code=400, detail="Use ?force=true to confirm deprovisioning")
    data["tenants"][tenant_id]["status"] = "deprovisioned"
    data["tenants"][tenant_id]["deprovisioned_at"] = datetime.now(timezone.utc).isoformat()
    save_tenants(data)
    return {"tenant_id": tenant_id, "status": "deprovisioned"}

@app.get("/api/v1/capacity")
async def get_capacity():
    capacities = {}
    for tier, limit in TIER_LIMITS.items():
        usage = _tier_usage(tier)
        capacities[tier] = {"used": usage, "limit": limit, "available": limit - usage, "price_monthly": TIER_PRICES[tier]}
    return {"tiers": capacities, "timestamp": datetime.now(timezone.utc).isoformat()}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8150, log_level="info")
