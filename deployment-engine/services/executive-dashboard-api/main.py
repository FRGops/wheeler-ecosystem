"""Executive Dashboard API — Institutional-grade dashboards for Wheeler ecosystem."""
import os
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Executive Dashboard API", version="1.0.0")

DATA_DIR = Path("/opt/apps/executive-dashboard-api/data")
DATA_DIR.mkdir(parents=True, exist_ok=True)

# ── Models ──────────────────────────────────────────────────────────────────

class ReportRequest(BaseModel):
    period: str = "current_month"
    format: str = "dashboard"

class KpiMetric(BaseModel):
    label: str
    value: float
    unit: str
    change_pct: float
    trend: str  # "up", "down", "flat"

class TenantSummary(BaseModel):
    tier: str
    count: int
    mrr: float
    capacity: int

class ServiceHealth(BaseModel):
    name: str
    port: int
    status: str
    latency_ms: float
    uptime_pct: float

# ── Demo data (replaced by real sources when available) ─────────────────────

DEMO_REVENUE = {
    "mrr": 84320.00,
    "mrr_change_24h": 1240.00,
    "arr_run_rate": 1011840.00,
    "active_subscriptions": 847,
    "new_subscriptions_24h": 14,
    "churned_subscriptions_24h": 3,
    "failed_payments_24h": 2,
    "pending_payouts": 12450.00,
    "pending_payouts_attorneys": 32,
    "pending_payouts_partners": 8,
    "ai_cost_allocation": {
        "surplusai": 45.20, "prediction_radar": 32.80, "aiops_saas": 18.50,
        "wheeler_brain": 22.30, "attorney_marketplace": 12.40
    },
    "revenue_by_product": {
        "SurplusAI Enterprise SaaS": 28500.00,
        "Prediction Radar SaaS": 15800.00,
        "AI Ops Infrastructure": 8900.00,
        "Wheeler Brain Enterprise": 7200.00,
        "Attorney Marketplace": 4300.00,
        "Data API / Intelligence Feeds": 2800.00,
        "Lead Intelligence Platform": 2100.00,
        "Attorney Intelligence": 700.00,
        "Workflow / Agent Marketplace": 1400.00,
        "Revenue Share Operations": 300.00
    },
    "subscriptions_by_tier": {
        "starter": 412, "pro": 298, "enterprise": 112, "agency": 25
    }
}

DEMO_SERVICES = [
    ServiceHealth(name="surplusai-portal-api", port=8103, status="healthy", latency_ms=45, uptime_pct=99.95),
    ServiceHealth(name="attorney-marketplace-api", port=8120, status="healthy", latency_ms=62, uptime_pct=99.91),
    ServiceHealth(name="aiops-saas-api", port=8150, status="healthy", latency_ms=38, uptime_pct=99.97),
    ServiceHealth(name="wheeler-brain-api", port=8160, status="healthy", latency_ms=55, uptime_pct=99.93),
    ServiceHealth(name="revenue-metrics-collector", port=8170, status="healthy", latency_ms=12, uptime_pct=99.99),
    ServiceHealth(name="executive-dashboard-api", port=8180, status="healthy", latency_ms=8, uptime_pct=99.99),
]

DEMO_TENANTS = [
    TenantSummary(tier="starter", count=412, mrr=40788.00, capacity=500),
    TenantSummary(tier="pro", count=298, mrr=148702.00, capacity=350),
    TenantSummary(tier="enterprise", count=112, mrr=223888.00, capacity=150),
    TenantSummary(tier="agency", count=25, mrr=99975.00, capacity=30),
]

# ── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "executive-dashboard-api",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/revenue/summary")
async def revenue_summary():
    return {**DEMO_REVENUE, "timestamp": datetime.now(timezone.utc).isoformat()}

@app.post("/api/v1/reports/generate")
async def generate_report(req: ReportRequest):
    report_id = f"rpt-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    return {
        "report_id": report_id,
        "period": req.period,
        "format": req.format,
        "status": "generated",
        "data": DEMO_REVENUE,
        "generated_at": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/kpi/dashboard")
async def kpi_dashboard():
    return {
        "metrics": [
            KpiMetric(label="MRR", value=84320, unit="USD", change_pct=1.5, trend="up").model_dump(),
            KpiMetric(label="ARR Run Rate", value=1011840, unit="USD", change_pct=18.3, trend="up").model_dump(),
            KpiMetric(label="Active Subscriptions", value=847, unit="count", change_pct=2.1, trend="up").model_dump(),
            KpiMetric(label="Churn Rate", value=1.8, unit="pct", change_pct=-0.3, trend="down").model_dump(),
            KpiMetric(label="Failed Payments", value=2, unit="count", change_pct=-33.3, trend="down").model_dump(),
            KpiMetric(label="LTV:CAC Ratio", value=28.5, unit="ratio", change_pct=5.2, trend="up").model_dump(),
        ],
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/tenants/summary")
async def tenant_summary():
    return {
        "tenants": [t.model_dump() for t in DEMO_TENANTS],
        "total_tenants": sum(t.count for t in DEMO_TENANTS),
        "total_mrr": sum(t.mrr for t in DEMO_TENANTS),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/services/health")
async def service_health():
    return {
        "services": [s.model_dump() for s in DEMO_SERVICES],
        "healthy": sum(1 for s in DEMO_SERVICES if s.status == "healthy"),
        "degraded": 0,
        "down": 0,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8180, log_level="info")
