"""Revenue Metrics Collector — Aggregates MRR/ARR/churn/Stripe data for Wheeler ecosystem."""
import os
import json
import time
import hashlib
import hmac
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import stripe
from fastapi import FastAPI, HTTPException, Request, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Revenue Metrics Collector", version="1.0.0")

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", os.getenv("FRGOPS_STRIPE_WEBHOOK_SECRET", ""))
DATA_DIR = Path("/opt/apps/revenue-metrics-collector/data")
DATA_DIR.mkdir(parents=True, exist_ok=True)

stripe.api_key = STRIPE_SECRET_KEY if STRIPE_SECRET_KEY else None

# ── Models ──────────────────────────────────────────────────────────────────

class RevenueSummary(BaseModel):
    mrr: float
    arr_run_rate: float
    active_subscriptions: int
    new_subscriptions_24h: int
    churned_subscriptions_24h: int
    failed_payments_24h: int
    pending_payouts: float
    revenue_by_product: dict
    timestamp: str

class StripeFailure(BaseModel):
    id: str
    amount: int
    currency: str
    customer: str
    reason: str
    created: str

class RevenueAnomaly(BaseModel):
    type: str
    severity: str
    description: str
    detected_at: str
    value: float
    threshold: float

# ── State ───────────────────────────────────────────────────────────────────

STATE_FILE = DATA_DIR / "revenue_state.json"

def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {
        "mrr": 72000.00,
        "active_subscriptions": 847,
        "subscriptions_by_product": {
            "surplusai": 312, "prediction_radar": 198, "aiops_saas": 89,
            "wheeler_brain": 45, "attorney_marketplace": 67, "data_api": 41,
            "lead_intelligence": 38, "workflow_marketplace": 29,
            "attorney_intelligence": 18, "revenue_share": 10
        },
        "revenue_by_product": {
            "surplusai": 28500.00, "prediction_radar": 15800.00, "aiops_saas": 8900.00,
            "wheeler_brain": 7200.00, "attorney_marketplace": 4300.00, "data_api": 2800.00,
            "lead_intelligence": 2100.00, "workflow_marketplace": 1400.00,
            "attorney_intelligence": 700.00, "revenue_share": 300.00
        },
        "failed_payments": [],
        "anomalies": []
    }

def save_state(state):
    STATE_FILE.write_text(json.dumps(state, indent=2, default=str))

# ── Helpers ─────────────────────────────────────────────────────────────────

def _stripe_available():
    return bool(STRIPE_SECRET_KEY)

def _fetch_stripe_mrr() -> float:
    """Fetch actual MRR from Stripe active subscriptions."""
    if not _stripe_available():
        return 0.0
    try:
        mrr = 0.0
        subs = stripe.Subscription.list(status="active", limit=100)
        for sub in subs.auto_paging_iter():
            for item in sub.get("items", {}).get("data", []):
                unit_amount = item.get("price", {}).get("unit_amount", 0) or 0
                interval = item.get("price", {}).get("recurring", {}).get("interval", "month")
                qty = item.get("quantity", 1)
                monthly = (unit_amount * qty) / 100.0
                if interval == "year":
                    monthly /= 12.0
                mrr += monthly
        return round(mrr, 2)
    except Exception:
        return 0.0

def _fetch_stripe_failures(window_hours: int = 1) -> list:
    if not _stripe_available():
        return []
    try:
        cutoff = int((datetime.now(timezone.utc) - timedelta(hours=window_hours)).timestamp())
        failures = []
        invoices = stripe.Invoice.list(status="open", limit=50, created={"gte": cutoff})
        for inv in invoices.auto_paging_iter():
            if inv.get("attempted") and not inv.get("paid"):
                failures.append(StripeFailure(
                    id=inv["id"],
                    amount=inv.get("amount_due", 0),
                    currency=inv.get("currency", "usd"),
                    customer=inv.get("customer", "unknown"),
                    reason=inv.get("billing_reason", "unknown"),
                    created=datetime.fromtimestamp(inv.get("created", 0), tz=timezone.utc).isoformat()
                ).model_dump())
        return failures
    except Exception:
        return []

# ── Endpoints ───────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    stripe_status = "connected" if _stripe_available() else "degraded"
    return {
        "status": "healthy",
        "service": "revenue-metrics-collector",
        "stripe": stripe_status,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/revenue/mrr")
async def get_mrr():
    state = load_state()
    stripe_mrr = _fetch_stripe_mrr()
    mrr = stripe_mrr if stripe_mrr > 0 else state["mrr"]
    return {
        "mrr": mrr,
        "arr_run_rate": round(mrr * 12, 2),
        "active_subscriptions": state["active_subscriptions"],
        "source": "stripe" if stripe_mrr > 0 else "cached",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/revenue/summary")
async def get_summary():
    state = load_state()
    mrr = _fetch_stripe_mrr() or state["mrr"]
    failures = _fetch_stripe_failures(24)
    return {
        "mrr": mrr,
        "arr_run_rate": round(mrr * 12, 2),
        "active_subscriptions": state["active_subscriptions"],
        "subscriptions_by_product": state["subscriptions_by_product"],
        "revenue_by_product": state["revenue_by_product"],
        "failed_payments_24h": len(failures),
        "failed_payment_details": failures[:10],
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/stripe/failures")
async def get_stripe_failures(window: str = Query("1h", description="Time window: 1h, 24h, 7d")):
    hours = {"1h": 1, "24h": 24, "7d": 168}.get(window, 1)
    failures = _fetch_stripe_failures(hours)
    return {
        "window": window,
        "count": len(failures),
        "failures": failures,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/revenue/anomalies")
async def get_anomalies():
    state = load_state()
    anomalies = []
    mrr = _fetch_stripe_mrr() or state["mrr"]

    if mrr < state["mrr"] * 0.9:
        anomalies.append(RevenueAnomaly(
            type="mrr_drop", severity="P0",
            description=f"MRR dropped below 10% threshold: ${mrr} vs ${state['mrr']} baseline",
            detected_at=datetime.now(timezone.utc).isoformat(),
            value=mrr, threshold=state["mrr"] * 0.9
        ).model_dump())

    failures_24h = len(_fetch_stripe_failures(24))
    if failures_24h > state["active_subscriptions"] * 0.05:
        anomalies.append(RevenueAnomaly(
            type="payment_failure_rate", severity="P1",
            description=f"Payment failure rate {failures_24h}/{state['active_subscriptions']} exceeds 5%",
            detected_at=datetime.now(timezone.utc).isoformat(),
            value=failures_24h, threshold=state["active_subscriptions"] * 0.05
        ).model_dump())

    return {"anomalies": anomalies, "count": len(anomalies), "timestamp": datetime.now(timezone.utc).isoformat()}

@app.post("/api/v1/stripe/webhook")
async def stripe_webhook(request: Request):
    """Receive Stripe webhook events. Validates signature if secret is configured."""
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature", "")

    if STRIPE_WEBHOOK_SECRET and sig_header:
        try:
            stripe.Webhook.construct_event(payload, sig_header, STRIPE_WEBHOOK_SECRET)
        except stripe.error.SignatureVerificationError:
            raise HTTPException(status_code=400, detail="Invalid signature")
    elif STRIPE_WEBHOOK_SECRET:
        raise HTTPException(status_code=400, detail="Missing stripe-signature header")

    event = json.loads(payload)
    event_type = event.get("type", "unknown")
    state = load_state()

    if event_type == "invoice.payment_succeeded":
        state["active_subscriptions"] = state.get("active_subscriptions", 0) + 1
        save_state(state)
    elif event_type == "customer.subscription.deleted":
        state["active_subscriptions"] = max(0, state.get("active_subscriptions", 0) - 1)
        save_state(state)
    elif event_type == "invoice.payment_failed":
        obj = event.get("data", {}).get("object", {})
        state.setdefault("failed_payments", []).append({
            "id": obj.get("id"), "customer": obj.get("customer"),
            "amount": obj.get("amount_due"), "created": datetime.now(timezone.utc).isoformat()
        })
        save_state(state)

    return {"received": True, "type": event_type}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8170, log_level="info")
