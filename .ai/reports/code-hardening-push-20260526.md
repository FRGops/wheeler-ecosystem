# Code Hardening Push — 2026-05-26

**Target**: `/root/deployment-engine/services/executive-dashboard-api/main.py`
**Deployed**: `/opt/apps/executive-dashboard-api/main.py`
**Verification**: `curl -s http://localhost:8180/health` → `{"status":"healthy","service":"executive-dashboard-api","version":"2.0.0","timestamp":"2026-05-26T08:19:25.289356+00:00"}`

## Fix 1: Localhost-only enforcement on PUT endpoints

- Added `_require_localhost(request)` helper after app creation
- Imported `starlette.requests.Request as StarletteRequest`
- Applied check to all 4 PUT endpoints: `seo_update_data`, `content_update_data`, `conversion_update_data`, `growth_briefs_update`
- Each returns `{"status": "error", "message": "localhost only"}` for non-localhost callers

## Fix 2: Bare excepts replaced with except Exception

- Replaced all 16 bare `except:` clauses with `except Exception:` throughout the file
- Affected functions: `run()`, `get_docker_stats()`, `get_docker_count()`, `get_docker_healthy()`, `get_docker_unhealthy()`, `get_docker_no_healthcheck()`, `get_pm2_status()`, `get_pm2_counts()`, `get_litellm_spend()`, `get_litellm_health()`, `get_system_resources()`, `get_revenue_summary()`, `intelligence_full()` (4x)

## Fix 3: Guard funnel[-2] IndexError in growth_reconcile

- Line 1392: Changed `funnel[-2]` fallback to `funnel[-2] if len(funnel) >= 2 else None`
- Prevents `IndexError` when funnel list has fewer than 2 elements

## Fix 4: PUT endpoint docstrings updated

- Added "Keys sent are fully replaced (not deep-merged) — send the complete sub-object." to all 4 PUT endpoint docstrings

## Fix 5: Keyword argument in live_litellm_spend

- Changed `get_litellm_spend(hours)` to `get_litellm_spend(hours=hours)` on line 209

## Post-Deploy Verification

```json
{"status":"healthy","service":"executive-dashboard-api","version":"2.0.0","timestamp":"2026-05-26T08:19:25.289356+00:00"}
```

PM2 status: `online`, PID 1819875, 0 restarts since deploy.
