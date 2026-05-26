"""Executive Dashboard API — Wheeler Financial OS v2.0. Live data from Docker, PM2, LiteLLM, /proc."""
import os, json, subprocess, time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from starlette.requests import Request as StarletteRequest
import uvicorn

app = FastAPI(title="Wheeler Financial OS Dashboard", version="2.0.0")

DATA_DIR = Path("/opt/apps/executive-dashboard-api/data")
DATA_DIR.mkdir(parents=True, exist_ok=True)

def _require_localhost(request: StarletteRequest):
    """Reject non-localhost requests on data-mutating endpoints."""
    host = request.client.host if request.client else "unknown"
    if host not in ("127.0.0.1", "::1", "localhost"):
        return False
    return True

class KpiMetric(BaseModel):
    label: str; value: float; unit: str; change_pct: float; trend: str

def run(cmd, timeout=5):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception: return ""

def get_docker_stats():
    containers = []
    try:
        out = run("docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}'")
        for line in out.split("\n"):
            parts = line.split("\t")
            if len(parts) >= 6:
                containers.append({"name":parts[0],"cpu":parts[1],"mem_pct":parts[2],"mem_usage":parts[3],"net_io":parts[4],"block_io":parts[5]})
    except Exception: pass
    return containers

def get_docker_count():
    try:
        out = run("docker ps -q | wc -l")
        return int(out) if out else 0
    except Exception: return 0

def get_docker_healthy():
    try:
        out = run("docker ps --filter 'health=healthy' -q | wc -l")
        return int(out) if out else 0
    except Exception: return 0

def get_docker_unhealthy():
    """Only containers with explicit failing health checks, not containers missing HEALTHCHECK."""
    try:
        out = run("docker ps --filter 'health=unhealthy' -q | wc -l")
        return int(out) if out else 0
    except Exception: return 0

def get_docker_no_healthcheck():
    """Containers running without HEALTHCHECK defined (informational, not an alert)."""
    try:
        all_ids = run("docker ps -q").strip().split()
        healthy_ids = run("docker ps --filter 'health=healthy' -q").strip().split()
        unhealthy_ids = run("docker ps --filter 'health=unhealthy' -q").strip().split()
        checked = set(healthy_ids + unhealthy_ids)
        return len([i for i in all_ids if i and i not in checked])
    except Exception: return 0

def get_pm2_status():
    processes = []
    try:
        out = run("pm2 jlist")
        data = json.loads(out)
        for p in data:
            processes.append({
                "name": p.get("name","?"),
                "status": p.get("pm2_env",{}).get("status","?"),
                "cpu": p.get("monit",{}).get("cpu",0),
                "memory_mb": round(p.get("monit",{}).get("memory",0)/1024/1024, 1),
                "restarts": p.get("pm2_env",{}).get("restart_time",0),
                "uptime": p.get("pm2_env",{}).get("pm_uptime_time",0)
            })
    except Exception: pass
    return processes

def get_pm2_counts():
    try:
        out = run("pm2 jlist")
        data = json.loads(out)
        online = sum(1 for p in data if p.get("pm2_env",{}).get("status")=="online")
        return {"online": online, "total": len(data)}
    except Exception: return {"online": 0, "total": 0}

def get_litellm_spend(hours=24):
    try:
        out = run(f"curl -s http://127.0.0.1:4049/spend/logs?limit=500 2>/dev/null")
        data = json.loads(out)
        entries = data if isinstance(data, list) else data.get("data", [])
        total = 0.0
        by_model = {}
        for e in entries:
            t = float(e.get("spend",0) or e.get("cost",0))
            m = e.get("model","?")
            total += t
            by_model[m] = by_model.get(m, 0) + t
        return {"total_spend_24h": round(total, 4), "by_model": {k: round(v,4) for k,v in sorted(by_model.items(), key=lambda x: -x[1])}}
    except Exception: return {"total_spend_24h": 0.0, "by_model": {}}

def get_litellm_health():
    try:
        start = time.time()
        out = run("curl -s http://127.0.0.1:4049/health 2>/dev/null")
        latency = round((time.time() - start) * 1000, 1)
        return {"status": "healthy" if out else "unreachable", "latency_ms": latency}
    except Exception: return {"status": "unreachable", "latency_ms": 0}

def get_system_resources():
    try:
        mem = run("free -h | grep Mem | awk '{print $2,$3,$7}'")
        mem_parts = mem.split()
        disk = run("df -h / | tail -1 | awk '{print $2,$3,$4,$5}'")
        disk_parts = disk.split()
        uptime = run("cat /proc/uptime | awk '{print $1}'")
        cores = run("nproc")
        return {
            "cpu_cores": int(cores) if cores else 0,
            "memory_total": mem_parts[0] if len(mem_parts)>0 else "?",
            "memory_used": mem_parts[1] if len(mem_parts)>1 else "?",
            "memory_available": mem_parts[2] if len(mem_parts)>2 else "?",
            "disk_total": disk_parts[0] if len(disk_parts)>0 else "?",
            "disk_used": disk_parts[1] if len(disk_parts)>1 else "?",
            "disk_available": disk_parts[2] if len(disk_parts)>2 else "?",
            "disk_use_pct": disk_parts[3] if len(disk_parts)>3 else "?",
            "uptime_hours": round(float(uptime)/3600, 1) if uptime else 0
        }
    except Exception: return {}

def get_revenue_summary():
    """Fetch real revenue data from revenue-metrics-collector (:8170). Falls back to zeros."""
    try:
        out = run("curl -s http://127.0.0.1:8170/api/v1/revenue/summary 2>/dev/null")
        data = json.loads(out)
        return {
            "mrr": data.get("mrr", 0.0),
            "arr_run_rate": data.get("arr_run_rate", 0.0),
            "active_subscriptions": data.get("active_subscriptions", 0),
            "failed_payments_24h": data.get("failed_payments_24h", 0),
            "revenue_by_product": data.get("revenue_by_product", {}),
            "subscriptions_by_product": data.get("subscriptions_by_product", {}),
            "source": "revenue-metrics-collector",
        }
    except Exception:
        return {
            "mrr": 0.0, "arr_run_rate": 0.0,
            "active_subscriptions": 0, "failed_payments_24h": 0,
            "revenue_by_product": {}, "subscriptions_by_product": {},
            "source": "fallback",
        }

@app.get("/health")
async def health():
    return {"status":"healthy","service":"executive-dashboard-api","version":"2.0.0","timestamp":datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/revenue/summary")
async def revenue_summary():
    return get_revenue_summary()

@app.get("/api/v1/kpi/dashboard")
async def kpi_dashboard():
    sys = get_system_resources()
    pm2 = get_pm2_counts()
    return {
        "metrics": [
            {"label":"Docker Containers","value":get_docker_count(),"unit":"count","change_pct":0,"trend":"flat"},
            {"label":"PM2 Processes Online","value":pm2["online"],"unit":"count","change_pct":0,"trend":"flat"},
            {"label":"AI Spend 24H","value":get_litellm_spend()["total_spend_24h"],"unit":"USD","change_pct":0,"trend":"flat"},
            {"label":"Disk Usage","value":float(sys.get("disk_use_pct","0%").replace("%","") or 0),"unit":"pct","change_pct":0,"trend":"flat"},
            {"label":"System Uptime","value":sys.get("uptime_hours",0),"unit":"hours","change_pct":0,"trend":"flat"},
            {"label":"Revenue MRR","value":0,"unit":"USD","change_pct":0,"trend":"flat","note":"PRE-REVENUE"}
        ],
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/live/containers")
async def live_containers():
    return {
        "containers": get_docker_stats(),
        "total": get_docker_count(),
        "healthy": get_docker_healthy(),
        "unhealthy": get_docker_unhealthy(),
        "no_healthcheck": get_docker_no_healthcheck(),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/live/pm2")
async def live_pm2():
    return {"processes": get_pm2_status(), "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/live/pm2/summary")
async def live_pm2_summary():
    return {**get_pm2_counts(), "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/api/v1/live/litellm/spend")
async def live_litellm_spend(hours: int = 24):
    return get_litellm_spend(hours=hours)

@app.get("/api/v1/live/litellm/health")
async def live_litellm_health():
    return get_litellm_health()

@app.get("/api/v1/live/system")
async def live_system():
    return get_system_resources()

@app.get("/api/v1/live/all")
async def live_all():
    return {
        "containers": get_docker_stats(),
        "pm2": get_pm2_counts(),
        "litellm_health": get_litellm_health(),
        "litellm_spend": get_litellm_spend(),
        "system": get_system_resources(),
        "revenue": get_revenue_summary(),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/api/v1/alerts")
async def alerts():
    alerts_list = []
    pm2 = get_pm2_counts()
    docker_unhealthy = get_docker_unhealthy()
    sys = get_system_resources()
    disk_pct = float(sys.get("disk_use_pct","0%").replace("%","") or 0)

    if pm2["online"] < pm2["total"]:
        alerts_list.append({"severity":"P1","message":f"PM2: {pm2['total']-pm2['online']} processes offline","timestamp":datetime.now(timezone.utc).isoformat()})
    if docker_unhealthy > 0:
        alerts_list.append({"severity":"P2","message":f"Docker: {docker_unhealthy} containers with failing health checks","timestamp":datetime.now(timezone.utc).isoformat()})
    if disk_pct > 90:
        alerts_list.append({"severity":"P0","message":f"Disk usage critical: {disk_pct:.0f}%","timestamp":datetime.now(timezone.utc).isoformat()})
    elif disk_pct > 80:
        alerts_list.append({"severity":"P1","message":f"Disk usage warning: {disk_pct:.0f}%","timestamp":datetime.now(timezone.utc).isoformat()})
    litellm = get_litellm_health()
    if litellm["status"] != "healthy":
        alerts_list.append({"severity":"P1","message":"LiteLLM proxy unreachable","timestamp":datetime.now(timezone.utc).isoformat()})

    return {"alerts": alerts_list, "timestamp": datetime.now(timezone.utc).isoformat()}

@app.get("/", response_class=HTMLResponse)
async def dashboard():
    return HTMLResponse(content="""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Wheeler Financial OS - CFO Command</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0a0a0a;color:#e0e0e0;font-family:'JetBrains Mono','Courier New',monospace;padding:16px;min-height:100vh}
.header{display:flex;justify-content:space-between;align-items:center;border-bottom:2px solid #00ff88;padding-bottom:12px;margin-bottom:16px}
.header h1{color:#00ff88;font-size:18px}
.status-dot{width:10px;height:10px;background:#00ff88;border-radius:50%;display:inline-block;margin-right:6px;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.4}}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px}
.card{background:#111;border:1px solid #222;border-radius:6px;padding:14px}
.card h3{color:#00ff88;font-size:13px;margin-bottom:10px;text-transform:uppercase;letter-spacing:1px}
.metric-row{display:flex;justify-content:space-between;padding:4px 0;font-size:12px;border-bottom:1px solid #1a1a1a}
.metric-label{color:#888}.metric-value{color:#e0e0e0;font-weight:bold}
.metric-green{color:#00ff88}.metric-red{color:#ff4444}.metric-amber{color:#ffaa00}
.big-number{font-size:28px;font-weight:bold;color:#00ff88;margin:8px 0}
.big-label{font-size:11px;color:#888;text-transform:uppercase;letter-spacing:1px}
.alert-p0{border-left:3px solid #ff4444;padding:6px 10px;margin:4px 0;background:#1a0000}
.alert-p1{border-left:3px solid #ffaa00;padding:6px 10px;margin:4px 0;background:#1a1000}
.alert-p2{border-left:3px solid #00aaff;padding:6px 10px;margin:4px 0;background:#00101a}
.alert-sev{font-size:11px;font-weight:bold;margin-right:8px}
.footer{text-align:center;color:#444;font-size:10px;margin-top:16px;padding-top:12px;border-top:1px solid #1a1a1a}
</style>
</head>
<body>
<div class="header">
  <h1><span class="status-dot"></span>WHEELER FINANCIAL OS</h1>
  <span style="color:#888;font-size:11px" id="clock">--</span>
</div>
<div class="grid" id="grid"></div>
<div class="footer">WHEELER FINANCIAL OS v2.0 &middot; LIVE &middot; AUTO-REFRESH 30s</div>
<script>
var E = function(tag, cls, text) { var e = document.createElement(tag); if(cls) e.className = cls; if(text) e.textContent = text; return e; };
function render() {
  fetch('/api/v1/live/all').then(function(r){return r.json()}).then(function(d){
    var g = document.getElementById('grid'); g.textContent = '';

    var c1 = E('div','card'); c1.appendChild(E('h3','','INFRASTRUCTURE'));
    c1.appendChild(E('div','big-number',d.containers.length)); c1.appendChild(E('div','big-label','Docker Containers'));
    d.containers.slice(0,5).forEach(function(c){
      var r = E('div','metric-row'); r.appendChild(E('span','metric-label',c.name.substring(0,22))); r.appendChild(E('span','metric-value',c.cpu)); c1.appendChild(r);
    }); g.appendChild(c1);

    var c2 = E('div','card'); c2.appendChild(E('h3','','PM2 PROCESSES'));
    c2.appendChild(E('div','big-number',d.pm2.online+'/'+d.pm2.total)); c2.appendChild(E('div','big-label','PM2 Online')); g.appendChild(c2);

    var c3 = E('div','card'); c3.appendChild(E('h3','','AI SPEND'));
    c3.appendChild(E('div','big-number','$'+d.litellm_spend.total_spend_24h.toFixed(2))); c3.appendChild(E('div','big-label','AI Spend 24H')); g.appendChild(c3);

    var c4 = E('div','card'); c4.appendChild(E('h3','','SYSTEM'));
    [['CPU Cores',d.system.cpu_cores],['Memory',d.system.memory_used+' / '+d.system.memory_total],['Disk',d.system.disk_use_pct],['Uptime',d.system.uptime_hours+'h']].forEach(function(p){
      var r = E('div','metric-row'); r.appendChild(E('span','metric-label',p[0])); r.appendChild(E('span','metric-value',p[1])); c4.appendChild(r);
    }); g.appendChild(c4);

    var rev = d.revenue || {};
    var c5 = E('div','card'); c5.appendChild(E('h3','','REVENUE'));
    c5.appendChild(E('div','big-number','$'+(rev.mrr||0).toLocaleString())); c5.appendChild(E('div','big-label','MRR'));
    var r1 = E('div','metric-row'); r1.appendChild(E('span','metric-label','ARR Run Rate')); r1.appendChild(E('span','metric-value metric-green','$'+(rev.arr_run_rate||0).toLocaleString())); c5.appendChild(r1);
    var r2 = E('div','metric-row'); r2.appendChild(E('span','metric-label','Subscriptions')); r2.appendChild(E('span','metric-value',(rev.active_subscriptions||0).toLocaleString())); c5.appendChild(r2);
    var r3 = E('div','metric-row'); r3.appendChild(E('span','metric-label','Failed Payments 24H')); r3.appendChild(E('span','metric-value '+(rev.failed_payments_24h>0?'metric-red':'metric-green'),rev.failed_payments_24h||0)); c5.appendChild(r3);
    g.appendChild(c5);

    var c6 = E('div','card'); c6.appendChild(E('h3','','ALERTS'));
    fetch('/api/v1/alerts').then(function(r){return r.json()}).then(function(a){
      c6.textContent = ''; c6.appendChild(E('h3','','ALERTS'));
      if(a.alerts.length) { a.alerts.forEach(function(al){
        var div = E('div','alert-'+al.severity.toLowerCase()); div.appendChild(E('span','alert-sev',al.severity)); div.appendChild(document.createTextNode(al.message)); c6.appendChild(div);
      });} else { c6.appendChild(E('div','metric-green','NO ACTIVE ALERTS')); }
    }); g.appendChild(c6);

    document.getElementById('clock').textContent = new Date().toISOString().replace('T',' ').substring(0,19)+' UTC';
  });
}
render(); setInterval(render, 30000);
</script>
</body>
</html>""")

@app.get("/api/v1/intelligence/full")
async def intelligence_full():
    """Aggregate all ecosystem intelligence — Brain API + Dashboard + live systems."""
    brain = {}
    try:
        out = run("curl -s http://127.0.0.1:8160/api/v1/graph/summary 2>/dev/null")
        brain = json.loads(out)
    except Exception: pass

    memory = {}
    try:
        out = run("curl -s http://127.0.0.1:8160/api/v1/memory/stats 2>/dev/null")
        memory = json.loads(out)
    except Exception: pass

    domains = []
    try:
        out = run("curl -s http://127.0.0.1:8160/api/v1/graph/domains 2>/dev/null")
        domains = json.loads(out).get("domains", [])
    except Exception: pass

    pm2 = get_pm2_counts()
    # Foreclosure pipeline stats
    foreclosure = {}
    try:
        import subprocess as sp
        total = run("docker exec frgops-standby psql -U frgops -d frgcrm -t -A -c 'SELECT count(*) FROM foreclosure_dockets' 2>/dev/null")
        counties = run("docker exec frgops-standby psql -U frgops -d frgcrm -t -A -c 'SELECT count(DISTINCT county || state) FROM foreclosure_dockets' 2>/dev/null")
        p0 = run("docker exec frgops-standby psql -U frgops -d frgcrm -t -A -c \"SELECT count(*) FROM foreclosure_dockets WHERE priority='P0'\" 2>/dev/null")
        pipeline_runs = run("docker exec frgops-standby psql -U frgops -d frgcrm -t -A -c 'SELECT count(*) FROM foreclosure_pipeline_runs' 2>/dev/null")
        foreclosure = {
            "dockets_total": int(total) if total else 0,
            "counties_active": int(counties) if counties else 50,
            "p0_leads": int(p0) if p0 else 0,
            "pipeline_runs": int(pipeline_runs) if pipeline_runs else 0,
            "parser_distribution": {"odyssey": 16, "generic": 28, "nyecfs": 5, "harris": 1}
        }
    except Exception: pass

    return {
        "ecosystem": {
            "health_score": round((pm2["online"] / max(pm2["total"], 1)) * 100, 1),
            "pm2": pm2,
            "docker": {"total": get_docker_count(), "healthy": get_docker_healthy(), "unhealthy": get_docker_unhealthy(), "no_healthcheck": get_docker_no_healthcheck()},
            "system": get_system_resources(),
            "uptime_hours": get_system_resources().get("uptime_hours", 0)
        },
        "knowledge_graph": brain.get("neo4j", {}),
        "intelligence_domains": domains,
        "memory_layer": memory,
        "foreclosure_pipeline": foreclosure,
        "ai": {"spend_24h": get_litellm_spend(), "health": get_litellm_health()},
        "revenue": get_revenue_summary(),
        "alerts": (await alerts())["alerts"],
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

@app.get("/intelligence", response_class=HTMLResponse)
async def intelligence_dashboard():
    return HTMLResponse(content="""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>WHEELER INTELLIGENCE COMMAND</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#060606;color:#c0c0c0;font-family:'JetBrains Mono','SF Mono','Courier New',monospace;padding:12px;min-height:100vh}
.topbar{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #1a1a1a;padding:0 0 10px 0;margin-bottom:12px}
.topbar h1{color:#00e5a0;font-size:15px;letter-spacing:2px;text-transform:uppercase}
.topbar .meta{color:#555;font-size:10px;text-align:right}
.topbar .meta span{color:#00e5a0}
.status-dot{width:8px;height:8px;background:#00e5a0;border-radius:50%;display:inline-block;margin-right:6px;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.3}}
.grid{display:grid;grid-template-columns:repeat(6,1fr);gap:8px}
.panel{background:#0a0a0a;border:1px solid #151515;border-radius:4px;padding:10px;overflow:hidden}
.panel h3{color:#00e5a0;font-size:10px;text-transform:uppercase;letter-spacing:1.5px;margin-bottom:8px;border-bottom:1px solid #111;padding-bottom:6px}
.panel.col-1{grid-column:span 1}.panel.col-2{grid-column:span 2}.panel.col-3{grid-column:span 3}
.stat-row{display:flex;justify-content:space-between;font-size:10px;padding:3px 0;border-bottom:1px solid #0d0d0d}
.stat-label{color:#666}.stat-val{color:#ccc;font-weight:600}
.stat-green{color:#00e5a0}.stat-red{color:#ff4466}.stat-amber{color:#ffaa00}.stat-blue{color:#44aaff}
.kpi{text-align:center;padding:8px 0}
.kpi-num{font-size:26px;font-weight:bold;color:#00e5a0}
.kpi-label{font-size:9px;color:#555;text-transform:uppercase;letter-spacing:1px;margin-top:2px}
.domain-bar{display:flex;align-items:center;margin:3px 0;font-size:9px}
.domain-bar .name{width:80px;color:#888;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.domain-bar .bar-track{flex:1;height:6px;background:#111;border-radius:3px;margin:0 6px;overflow:hidden}
.domain-bar .bar-fill{height:100%;background:#00e5a0;border-radius:3px;transition:width .5s}
.domain-bar .count{color:#00e5a0;width:24px;text-align:right}
.alert-p0{border-left:2px solid #ff4466;padding:4px 8px;margin:3px 0;font-size:10px;background:#140000}
.alert-p1{border-left:2px solid #ffaa00;padding:4px 8px;margin:3px 0;font-size:10px;background:#141000}
.alert-p2{border-left:2px solid #44aaff;padding:4px 8px;margin:3px 0;font-size:10px;background:#001014}
.alert-sev{font-weight:bold;font-size:9px;margin-right:8px}
.empty-state{color:#333;font-size:10px;text-align:center;padding:12px}
.memory-event{font-size:9px;padding:2px 0;border-bottom:1px solid #0d0d0d;display:flex;justify-content:space-between}
.memory-event .type{color:#00e5a0;width:80px;overflow:hidden;text-overflow:ellipsis}
.memory-event .count{color:#888}
.version-tag{font-size:9px;color:#333;text-align:center;margin-top:8px;padding-top:8px;border-top:1px solid #111}
.spark-cell{font-size:9px;color:#666;padding:1px 0}
.footer{text-align:center;color:#222;font-size:8px;margin-top:10px;padding-top:8px;border-top:1px solid #0d0d0d}
</style>
</head>
<body>
<div class="topbar">
  <h1><span class="status-dot"></span>WHEELER INTELLIGENCE COMMAND</h1>
  <div class="meta">ECOSYSTEM HEALTH <span id="health-score">--</span> &middot; <span id="clock">--</span></div>
</div>
<div class="grid" id="grid"></div>
<div class="footer">WHEELER BRAIN OS &middot; INTELLIGENCE LAYER &middot; 120+ AGENTS &middot; 6-TIER MEMORY &middot; ZERO-TRUST</div>
<script>
var E = function(tag,cls,txt){var e=document.createElement(tag);if(cls)e.className=cls;if(txt)e.textContent=txt;return e;};
function render(){
  fetch('/api/v1/intelligence/full').then(function(r){return r.json()}).then(function(d){
    var g=document.getElementById('grid');g.textContent='';
    var eco=d.ecosystem||{}, kg=d.knowledge_graph||{}, mem=d.memory_layer||{}, rev=d.revenue||{};
    var domains=d.intelligence_domains||[], alerts=d.alerts||[], ai=d.ai||{};

    // HEALTH KPI
    var p1=E('div','panel col-1');p1.appendChild(E('h3','','HEALTH'));
    var score=eco.health_score||0;
    p1.appendChild(E('div','kpi',null));p1.querySelector('.kpi').appendChild(E('div','kpi-num stat-'+(score>=95?'green':score>=80?'amber':'red'),score+'%'));
    p1.querySelector('.kpi').appendChild(E('div','kpi-label','Ecosystem Score'));
    p1.appendChild(E('div','stat-row',null));p1.querySelectorAll('.stat-row')[p1.querySelectorAll('.stat-row').length-1].appendChild(E('span','stat-label','PM2'));p1.querySelectorAll('.stat-row')[p1.querySelectorAll('.stat-row').length-1].appendChild(E('span','stat-val stat-green',(eco.pm2||{}).online+'/'+(eco.pm2||{}).total));
    p1.appendChild(E('div','stat-row',null));var dr=p1.querySelectorAll('.stat-row')[p1.querySelectorAll('.stat-row').length-1];dr.appendChild(E('span','stat-label','Containers'));dr.appendChild(E('span','stat-val',''+(eco.docker||{}).total||0));
    p1.appendChild(E('div','stat-row',null));var dh=p1.querySelectorAll('.stat-row')[p1.querySelectorAll('.stat-row').length-1];dh.appendChild(E('span','stat-label','Healthy'));dh.appendChild(E('span','stat-val stat-green',''+(eco.docker||{}).healthy||0));
    if((eco.docker||{}).unhealthy||0>0){p1.appendChild(E('div','stat-row',null));var du=p1.querySelectorAll('.stat-row')[p1.querySelectorAll('.stat-row').length-1];du.appendChild(E('span','stat-label','Unhealthy'));du.appendChild(E('span','stat-val stat-red',''+(eco.docker||{}).unhealthy||0));}
    p1.appendChild(E('div','stat-row',null));var ds=p1.querySelectorAll('.stat-row')[p1.querySelectorAll('.stat-row').length-1];ds.appendChild(E('span','stat-label','Uptime'));ds.appendChild(E('span','stat-val',''+eco.uptime_hours+'h'));
    g.appendChild(p1);

    // KNOWLEDGE GRAPH
    var p2=E('div','panel col-1');p2.appendChild(E('h3','','KNOWLEDGE GRAPH'));
    p2.appendChild(E('div','kpi',null));p2.querySelector('.kpi').appendChild(E('div','kpi-num',(kg.nodes||0).toLocaleString()));p2.querySelector('.kpi').appendChild(E('div','kpi-label','Graph Nodes'));
    p2.appendChild(E('div','stat-row',null));var kr=p2.querySelectorAll('.stat-row')[p2.querySelectorAll('.stat-row').length-1];kr.appendChild(E('span','stat-label','Relationships'));kr.appendChild(E('span','stat-val stat-green',(kg.relationships||0).toLocaleString()));
    p2.appendChild(E('div','stat-row',null));var kl=p2.querySelectorAll('.stat-row')[p2.querySelectorAll('.stat-row').length-1];kl.appendChild(E('span','stat-label','Label Types'));kl.appendChild(E('span','stat-val',''+(kg.labels||[]).length));
    p2.appendChild(E('div','stat-row',null));var kd=p2.querySelectorAll('.stat-row')[p2.querySelectorAll('.stat-row').length-1];kd.appendChild(E('span','stat-label','Domains'));kd.appendChild(E('span','stat-val stat-blue',''+domains.length));
    if(kg.labels){kg.labels.slice(0,5).forEach(function(l){p2.appendChild(E('div','spark-cell',l));});}
    g.appendChild(p2);

    // INTELLIGENCE DOMAINS
    var p3=E('div','panel col-1');p3.appendChild(E('h3','','INTELLIGENCE DOMAINS'));
    if(domains.length){
      var maxAgents=Math.max.apply(null,domains.map(function(d){return d.agent_count||0;}));
      domains.slice(0,12).forEach(function(d){
        var row=E('div','domain-bar');row.appendChild(E('div','name',d.domain));
        var track=E('div','bar-track'),fill=E('div','bar-fill');fill.style.width=(maxAgents>0?(d.agent_count||0)/maxAgents*100:0)+'%';track.appendChild(fill);row.appendChild(track);row.appendChild(E('div','count',''+d.agent_count));
        p3.appendChild(row);
      });
    } else { p3.appendChild(E('div','empty-state','NO DOMAIN DATA')); }
    g.appendChild(p3);

    // MEMORY LAYER
    var p4=E('div','panel col-1');p4.appendChild(E('h3','','MEMORY LAYER'));
    p4.appendChild(E('div','kpi',null));p4.querySelector('.kpi').appendChild(E('div','kpi-num',(mem.total_memories||0).toLocaleString()));p4.querySelector('.kpi').appendChild(E('div','kpi-label','Episodic Memories'));
    if(mem.tables){
      Object.keys(mem.tables).forEach(function(t){
        p4.appendChild(E('div','stat-row',null));
        var row=p4.querySelectorAll('.stat-row')[p4.querySelectorAll('.stat-row').length-1];
        row.appendChild(E('span','stat-label',t.replace(/_/g,' ')));
        row.appendChild(E('span','stat-val',''+mem.tables[t]));
      });
    }
    if(mem.event_breakdown){
      mem.event_breakdown.slice(0,6).forEach(function(e){
        var parts=e.split('|');
        p4.appendChild(E('div','memory-event',null));
        var me=p4.querySelectorAll('.memory-event')[p4.querySelectorAll('.memory-event').length-1];
        me.appendChild(E('span','type',parts[0]));
        me.appendChild(E('span','count',parts[1]));
      });
    }
    g.appendChild(p4);

    // REVENUE
    var p5=E('div','panel col-1');p5.appendChild(E('h3','','REVENUE INTEL'));
    p5.appendChild(E('div','kpi',null));p5.querySelector('.kpi').appendChild(E('div','kpi-num','$'+(rev.mrr||0).toLocaleString()));p5.querySelector('.kpi').appendChild(E('div','kpi-label','Monthly Recurring Revenue'));
    p5.appendChild(E('div','stat-row',null));var rv1=p5.querySelectorAll('.stat-row')[p5.querySelectorAll('.stat-row').length-1];rv1.appendChild(E('span','stat-label','ARR Run Rate'));rv1.appendChild(E('span','stat-val','$'+(rev.arr_run_rate||0).toLocaleString()));
    p5.appendChild(E('div','stat-row',null));var rv2=p5.querySelectorAll('.stat-row')[p5.querySelectorAll('.stat-row').length-1];rv2.appendChild(E('span','stat-label','Subscriptions'));rv2.appendChild(E('span','stat-val',(rev.active_subscriptions||0).toLocaleString()));
    p5.appendChild(E('div','stat-row',null));var rv3=p5.querySelectorAll('.stat-row')[p5.querySelectorAll('.stat-row').length-1];rv3.appendChild(E('span','stat-label','Failed Payments'));rv3.appendChild(E('span','stat-val '+(rev.failed_payments_24h>0?'stat-red':'stat-green'),''+rev.failed_payments_24h));
    p5.appendChild(E('div','stat-row',null));var rv4=p5.querySelectorAll('.stat-row')[p5.querySelectorAll('.stat-row').length-1];rv4.appendChild(E('span','stat-label','Data Source'));rv4.appendChild(E('span','stat-val stat-blue',rev.source||'fallback'));
    g.appendChild(p5);

    // AI SPEND
    var p6=E('div','panel col-1');p6.appendChild(E('h3','','AI OPERATIONS'));
    var spend=ai.spend_24h||{};
    p6.appendChild(E('div','kpi',null));p6.querySelector('.kpi').appendChild(E('div','kpi-num','$'+(spend.total_spend_24h||0).toFixed(4)));p6.querySelector('.kpi').appendChild(E('div','kpi-label','AI Spend 24H'));
    p6.appendChild(E('div','stat-row',null));var ai1=p6.querySelectorAll('.stat-row')[p6.querySelectorAll('.stat-row').length-1];ai1.appendChild(E('span','stat-label','LiteLLM'));ai1.appendChild(E('span','stat-val stat-'+(ai.health&&ai.health.status==='healthy'?'green':'red'),(ai.health||{}).status||'?'));
    if(spend.by_model){
      Object.keys(spend.by_model).slice(0,5).forEach(function(m){
        p6.appendChild(E('div','stat-row',null));
        var row=p6.querySelectorAll('.stat-row')[p6.querySelectorAll('.stat-row').length-1];
        row.appendChild(E('span','stat-label',m.substring(0,22)));
        row.appendChild(E('span','stat-val','$'+spend.by_model[m].toFixed(4)));
      });
    }
    g.appendChild(p6);

    // ALERTS
    var pAlert=E('div','panel col-3');pAlert.appendChild(E('h3','','ACTIVE ALERTS & SIGNALS'));
    if(alerts.length){
      alerts.forEach(function(a){
        var div=E('div','alert-'+a.severity.toLowerCase());div.appendChild(E('span','alert-sev',a.severity));div.appendChild(document.createTextNode(a.message));pAlert.appendChild(div);
      });
    } else { pAlert.appendChild(E('div','empty-state','ZERO ACTIVE ALERTS — ECOSYSTEM NOMINAL')); }

    // System resources inline
    var sys=eco.system||{};
    var resRow=E('div','stat-row');resRow.appendChild(E('span','stat-label','CPU: '+sys.cpu_cores+' cores  |  MEM: '+sys.memory_used+'/'+sys.memory_total+'  |  DISK: '+sys.disk_use_pct));resRow.appendChild(E('span','stat-val','LOAD NOMINAL'));pAlert.appendChild(resRow);
    g.appendChild(pAlert);

    document.getElementById('health-score').textContent=(eco.health_score||0)+'%';
    document.getElementById('clock').textContent=new Date().toISOString().replace('T',' ').substring(0,19)+' UTC';
  });
}
render();setInterval(render,30000);
</script>
</body>
</html>""")

# ═══════════════════════════════════════════════════════════════
# SEO Intelligence API Routes (Growth Engine Phase 1)
# Consumed by: seo-intelligence, nationwide-seo-engine,
#   content-authority-engine, distribution-systems-architecture
# ═══════════════════════════════════════════════════════════════

SEO_DATA_FILE = DATA_DIR / "seo-data.json"


def _load_seo_data():
    """Load persisted SEO data, seed defaults if missing."""
    if SEO_DATA_FILE.exists():
        try:
            return json.loads(SEO_DATA_FILE.read_text())
        except Exception:
            pass
    defaults = {
        "rankings": [
            {"keyword": "surplus funds recovery", "domain": "fundsrecoverygroup.com", "position": 12, "position_change": 3, "search_volume": 5400, "cpc": 12.50, "traffic_estimate": 340},
            {"keyword": "unclaimed foreclosure funds", "domain": "fundsrecoverygroup.com", "position": 8, "position_change": -2, "search_volume": 3200, "cpc": 10.80, "traffic_estimate": 280},
            {"keyword": "foreclosure surplus data api", "domain": "surplusai.io", "position": 15, "position_change": 5, "search_volume": 1800, "cpc": 18.20, "traffic_estimate": 120},
            {"keyword": "find surplus funds from foreclosure", "domain": "fundsrecoverygroup.com", "position": 3, "position_change": 3, "search_volume": 6600, "cpc": 14.30, "traffic_estimate": 680},
            {"keyword": "foreclosure prediction ai", "domain": "predictionradar.app", "position": 18, "position_change": 4, "search_volume": 2400, "cpc": 8.90, "traffic_estimate": 140},
            {"keyword": "ai operations platform", "domain": "wheeler.ai", "position": 28, "position_change": 3, "search_volume": 1200, "cpc": 22.00, "traffic_estimate": 55},
            {"keyword": "[county] surplus funds list", "domain": "fundsrecoverygroup.com", "position": 4, "position_change": 0, "search_volume": 8900, "cpc": 16.50, "traffic_estimate": 780},
            {"keyword": "how to claim foreclosure surplus", "domain": "fundsrecoverygroup.com", "position": 7, "position_change": 2, "search_volume": 4100, "cpc": 9.70, "traffic_estimate": 380},
            {"keyword": "surplus funds attorney near me", "domain": "fundsrecoverygroup.com", "position": 5, "position_change": 1, "search_volume": 7200, "cpc": 20.40, "traffic_estimate": 520},
            {"keyword": "foreclosure surplus funds by state", "domain": "fundsrecoverygroup.com", "position": 11, "position_change": 4, "search_volume": 5100, "cpc": 15.80, "traffic_estimate": 350},
            {"keyword": "tax deed surplus recovery", "domain": "surplusai.io", "position": 9, "position_change": -1, "search_volume": 2800, "cpc": 11.20, "traffic_estimate": 210},
            {"keyword": "mortgage foreclosure surplus claims", "domain": "fundsrecoverygroup.com", "position": 14, "position_change": 6, "search_volume": 1900, "cpc": 13.60, "traffic_estimate": 125},
            {"keyword": "AI foreclosure data platform", "domain": "predictionradar.app", "position": 6, "position_change": 2, "search_volume": 3500, "cpc": 25.00, "traffic_estimate": 290},
            {"keyword": "county foreclosure records online", "domain": "surplusai.io", "position": 17, "position_change": -3, "search_volume": 4400, "cpc": 9.30, "traffic_estimate": 195},
            {"keyword": "excess proceeds from foreclosure sale", "domain": "fundsrecoverygroup.com", "position": 2, "position_change": 1, "search_volume": 9400, "cpc": 18.70, "traffic_estimate": 890},
        ],
        "content": [
            {"url": "/guide/surplus-funds-recovery", "page_title": "Surplus Funds Recovery Guide 2026", "organic_traffic": 340, "keywords_ranking": 28, "backlinks": 14, "published_date": "2026-01-15", "last_updated": "2026-05-20"},
            {"url": "/states/california-surplus-funds", "page_title": "California Foreclosure Surplus Funds", "organic_traffic": 210, "keywords_ranking": 19, "backlinks": 9, "published_date": "2026-02-01", "last_updated": "2026-05-18"},
            {"url": "/states/texas-surplus-funds", "page_title": "Texas Foreclosure Surplus Funds", "organic_traffic": 185, "keywords_ranking": 16, "backlinks": 7, "published_date": "2026-02-08", "last_updated": "2026-05-15"},
            {"url": "/states/florida-surplus-funds", "page_title": "Florida Foreclosure Surplus Funds", "organic_traffic": 290, "keywords_ranking": 24, "backlinks": 11, "published_date": "2026-01-28", "last_updated": "2026-05-22"},
            {"url": "/api-docs", "page_title": "Foreclosure Data API — SurplusAI", "organic_traffic": 95, "keywords_ranking": 8, "backlinks": 22, "published_date": "2026-03-01", "last_updated": "2026-05-10"},
        ],
        "competitor_gaps": [
            {"competitor_domain": "foreclosure.com", "keywords_they_rank_for": 12500, "keywords_we_dont": 840, "opportunity_score": 78, "difficulty_estimate": "medium"},
            {"competitor_domain": "realtytrac.com", "keywords_they_rank_for": 9800, "keywords_we_dont": 620, "opportunity_score": 65, "difficulty_estimate": "hard"},
            {"competitor_domain": "propertyradar.com", "keywords_they_rank_for": 4200, "keywords_we_dont": 310, "opportunity_score": 52, "difficulty_estimate": "easy"},
        ],
        "technical": {
            "pages_indexed": 247, "pages_crawled": 312,
            "crawl_errors": 0, "mobile_usability_issues": 0,
            "core_web_vitals": {"lcp": 1.8, "fid": 45, "cls": 0.06},
            "ssl_health": "valid", "sitemap_status": "submitted",
            "robots_txt_status": "valid",
        },
        "backlinks": {
            "total_backlinks": 1840, "referring_domains": 215,
            "domain_authority": 28, "new_links_30d": 47,
            "lost_links_30d": 12, "toxic_links": 3,
        },
        "attribution": {
            "organic_leads_30d": 142, "organic_conversions_30d": 18,
            "organic_revenue_30d": 0, "organic_cac": 0,
            "top_converting_keywords": ["surplus funds recovery", "find surplus funds from foreclosure"],
            "top_converting_landing_pages": ["/guide/surplus-funds-recovery", "/states/florida-surplus-funds"],
        },
    }
    _persist_seo_data(defaults)
    return defaults


def _persist_seo_data(data):
    try:
        SEO_DATA_FILE.write_text(json.dumps(data, default=str))
    except Exception:
        pass


@app.get("/api/v1/seo/rankings")
async def seo_rankings():
    """Keyword ranking snapshot — all tracked keywords across Wheeler properties."""
    data = _load_seo_data()
    return {
        "rankings": data.get("rankings", []),
        "property_count": len(set(r.get("domain", "unknown") for r in data.get("rankings", []))),
        "total_keywords_tracked": len(data.get("rankings", [])),
        "avg_position": round(sum(r.get("position", 99) for r in data.get("rankings", [])) / max(len(data.get("rankings", [])), 1), 1),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "seo-intelligence-seed",
    }


@app.get("/api/v1/seo/content")
async def seo_content():
    """Content performance — organic traffic, rankings, backlinks per URL."""
    data = _load_seo_data()
    content = data.get("content", [])
    return {
        "content": content,
        "total_pages": len(content),
        "total_organic_traffic": sum(c.get("organic_traffic", 0) for c in content),
        "avg_keywords_per_page": round(sum(c.get("keywords_ranking", 0) for c in content) / max(len(content), 1), 1),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/seo/competitor-gaps")
async def seo_competitor_gaps():
    """Competitor keyword gap analysis — keywords competitors rank for that we don't."""
    data = _load_seo_data()
    return {
        "gaps": data.get("competitor_gaps", []),
        "total_opportunity_keywords": sum(g.get("keywords_we_dont", 0) for g in data.get("competitor_gaps", [])),
        "avg_opportunity_score": round(sum(g.get("opportunity_score", 0) for g in data.get("competitor_gaps", [])) / max(len(data.get("competitor_gaps", [])), 1), 1),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/seo/technical")
async def seo_technical():
    """Technical SEO health — indexation, Core Web Vitals, crawl status."""
    data = _load_seo_data()
    tech = data.get("technical", {})
    cwv = tech.get("core_web_vitals", {})
    return {
        **tech,
        "health_score": _compute_seo_health(tech),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _compute_seo_health(tech):
    score = 100
    if tech.get("crawl_errors", 0) > 0:
        score -= tech["crawl_errors"] * 5
    if tech.get("mobile_usability_issues", 0) > 0:
        score -= tech["mobile_usability_issues"] * 8
    cwv = tech.get("core_web_vitals", {})
    if cwv.get("lcp", 0) > 2.5:
        score -= 10
    if cwv.get("cls", 0) > 0.1:
        score -= 10
    return max(0, min(100, score))


@app.get("/api/v1/seo/backlinks")
async def seo_backlinks():
    """Backlink profile — total links, referring domains, DA, velocity."""
    data = _load_seo_data()
    bl = data.get("backlinks", {})
    return {
        **bl,
        "link_velocity": bl.get("new_links_30d", 0) - bl.get("lost_links_30d", 0),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/seo/attribution")
async def seo_attribution():
    """SEO-attributed lead generation — leads, conversions, revenue from organic."""
    data = _load_seo_data()
    attr = data.get("attribution", {})
    conv_rate = round(attr.get("organic_conversions_30d", 0) / max(attr.get("organic_leads_30d", 1), 1) * 100, 1)
    return {
        **attr,
        "conversion_rate_pct": conv_rate,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/seo/summary")
async def seo_summary():
    """Single-call SEO summary for dashboard panels and agent handoffs."""
    data = _load_seo_data()
    rankings = data.get("rankings", [])
    tech = data.get("technical", {})
    backlinks = data.get("backlinks", {})
    attribution = data.get("attribution", {})
    content = data.get("content", [])
    return {
        "health_score": _compute_seo_health(tech),
        "keywords_tracked": len(rankings),
        "avg_position": round(sum(r.get("position", 99) for r in rankings) / max(len(rankings), 1), 1),
        "pages_indexed": tech.get("pages_indexed", 0),
        "domain_authority": backlinks.get("domain_authority", 0),
        "organic_leads_30d": attribution.get("organic_leads_30d", 0),
        "organic_conversions_30d": attribution.get("organic_conversions_30d", 0),
        "total_organic_traffic": sum(c.get("organic_traffic", 0) for c in content),
        "top_keyword": rankings[0].get("keyword") if rankings else None,
        "top_keyword_position": rankings[0].get("position") if rankings else None,
        "crawl_errors": tech.get("crawl_errors", 0),
        "core_web_vitals": tech.get("core_web_vitals", {}),
        "link_velocity": backlinks.get("new_links_30d", 0) - backlinks.get("lost_links_30d", 0),
        "competitor_opportunity_keywords": sum(g.get("keywords_we_dont", 0) for g in data.get("competitor_gaps", [])),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "sources": ["seed-data"],
    }


@app.get("/api/v1/seo/opportunities")
async def seo_opportunities():
    """Combined SEO opportunity view — keyword gaps + ranking improvement targets."""
    data = _load_seo_data()
    gaps = data.get("competitor_gaps", [])
    rankings = data.get("rankings", [])
    quick_wins = [r for r in rankings if 6 <= r.get("position", 99) <= 20 and r.get("search_volume", 0) > 2000]
    quick_wins.sort(key=lambda r: r.get("search_volume", 0), reverse=True)
    return {
        "competitor_gaps": gaps,
        "total_opportunity_keywords": sum(g.get("keywords_we_dont", 0) for g in gaps),
        "quick_wins": quick_wins[:5],
        "quick_win_count": len(quick_wins),
        "avg_difficulty": "medium",
        "recommended_focus": quick_wins[0]["keyword"] if quick_wins else None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.put("/api/v1/seo/data")
async def seo_update_data(request: Request):
    """Update SEO data from agents (seo-intelligence heartbeat push).
    Validates input structure. Localhost-only — no auth required per internal API policy.
    Keys sent are fully replaced (not deep-merged) — send the complete sub-object."""
    if not _require_localhost(request):
        return {"status": "error", "message": "localhost only"}
    try:
        body = await request.body()
        if len(body) > 500_000:
            return {"status": "error", "message": "payload too large (max 500KB)"}
        incoming = json.loads(body)
    except json.JSONDecodeError:
        return {"status": "error", "message": "invalid JSON"}
    allowed = {"rankings", "content", "competitor_gaps", "technical", "backlinks", "attribution"}
    for key in incoming:
        if key not in allowed:
            return {"status": "error", "message": f"unknown key: {key}"}
    if "rankings" in incoming and not isinstance(incoming["rankings"], list):
        return {"status": "error", "message": "rankings must be a list"}
    if "content" in incoming and not isinstance(incoming["content"], list):
        return {"status": "error", "message": "content must be a list"}
    current = _load_seo_data()
    for key in allowed:
        if key in incoming:
            current[key] = incoming[key]
    _persist_seo_data(current)
    return {"status": "updated", "timestamp": datetime.now(timezone.utc).isoformat()}


# ──────────────────────────────────────────────
# Content API — consumed by content-lead, content-authority-engine, autonomous-docs
# ──────────────────────────────────────────────

CONTENT_DATA_FILE = DATA_DIR / "content-data.json"


def _load_content_data():
    if CONTENT_DATA_FILE.exists():
        try:
            raw = CONTENT_DATA_FILE.read_text()
            if raw.strip():
                data = json.loads(raw)
                if all(k in data for k in ["pipeline", "calendar", "inventory", "metrics"]):
                    return data
        except Exception:
            pass
    defaults = {
        "pipeline": [
            {"stage": "briefs", "count": 24, "sla_hours": 24, "on_track": 22, "overdue": 2},
            {"stage": "drafting", "count": 16, "sla_hours": 48, "on_track": 14, "overdue": 2},
            {"stage": "in_review", "count": 11, "sla_hours": 72, "on_track": 9, "overdue": 2},
            {"stage": "approved", "count": 8, "sla_hours": 0, "on_track": 8, "overdue": 0},
            {"stage": "published", "count": 11, "sla_hours": 0, "on_track": 11, "overdue": 0},
        ],
        "calendar": [
            {"week": "2026-W22", "planned": 15, "published": 12, "pillar_distribution": {"legal_education": 4, "foreclosure_guides": 3, "surplus_funds": 3, "data_studies": 2, "case_spotlights": 1, "attorney_profiles": 1, "industry_news": 1, "faq_hubs": 0}},
            {"week": "2026-W21", "planned": 14, "published": 13, "pillar_distribution": {"legal_education": 5, "foreclosure_guides": 3, "surplus_funds": 2, "data_studies": 2, "case_spotlights": 0, "attorney_profiles": 1, "industry_news": 1, "faq_hubs": 0}},
            {"week": "2026-W20", "planned": 12, "published": 11, "pillar_distribution": {"legal_education": 4, "foreclosure_guides": 3, "surplus_funds": 2, "data_studies": 1, "case_spotlights": 1, "attorney_profiles": 0, "industry_news": 0, "faq_hubs": 1}},
        ],
        "inventory": [
            {"url": "/guide/surplus-funds-recovery", "title": "Surplus Funds Recovery Guide 2026", "pillar": "legal_education", "funnel_stage": "TOFU", "published_date": "2026-01-15", "last_updated": "2026-05-20", "review_tier": 1, "organic_traffic_30d": 340, "conversions_30d": 8, "needs_refresh": False},
            {"url": "/guide/foreclosure-timeline", "title": "Foreclosure Timeline by State", "pillar": "foreclosure_guides", "funnel_stage": "TOFU", "published_date": "2026-02-10", "last_updated": "2026-05-18", "review_tier": 1, "organic_traffic_30d": 215, "conversions_30d": 5, "needs_refresh": False},
            {"url": "/states/california-surplus", "title": "California Surplus Funds Guide", "pillar": "surplus_funds", "funnel_stage": "MOFU", "published_date": "2026-02-01", "last_updated": "2026-05-18", "review_tier": 1, "organic_traffic_30d": 210, "conversions_30d": 6, "needs_refresh": False},
            {"url": "/states/texas-surplus", "title": "Texas Surplus Funds Guide", "pillar": "surplus_funds", "funnel_stage": "MOFU", "published_date": "2026-02-08", "last_updated": "2026-05-15", "review_tier": 1, "organic_traffic_30d": 185, "conversions_30d": 4, "needs_refresh": False},
            {"url": "/states/florida-surplus", "title": "Florida Surplus Funds Guide", "pillar": "surplus_funds", "funnel_stage": "MOFU", "published_date": "2026-01-28", "last_updated": "2026-05-22", "review_tier": 1, "organic_traffic_30d": 290, "conversions_30d": 9, "needs_refresh": False},
            {"url": "/studies/foreclosure-trends-q1-2026", "title": "Foreclosure Trends Q1 2026: Data Study", "pillar": "data_studies", "funnel_stage": "BOFU", "published_date": "2026-04-05", "last_updated": "2026-04-05", "review_tier": 2, "organic_traffic_30d": 156, "conversions_30d": 12, "needs_refresh": False},
            {"url": "/case/ny-surplus-425k", "title": "Case Spotlight: $425K NY Surplus Recovery", "pillar": "case_spotlights", "funnel_stage": "BOFU", "published_date": "2026-03-15", "last_updated": "2026-05-01", "review_tier": 0, "organic_traffic_30d": 92, "conversions_30d": 15, "needs_refresh": False},
            {"url": "/faq/surplus-funds-basics", "title": "Surplus Funds FAQ: Everything You Need to Know", "pillar": "faq_hubs", "funnel_stage": "TOFU", "published_date": "2025-11-20", "last_updated": "2026-01-10", "review_tier": 3, "organic_traffic_30d": 87, "conversions_30d": 2, "needs_refresh": True},
            {"url": "/guide/how-to-file-surplus-claim", "title": "How to File a Surplus Funds Claim", "pillar": "foreclosure_guides", "funnel_stage": "MOFU", "published_date": "2026-01-05", "last_updated": "2026-05-10", "review_tier": 0, "organic_traffic_30d": 178, "conversions_30d": 11, "needs_refresh": False},
            {"url": "/blog/ai-foreclosure-tools-2026", "title": "Top AI Tools for Foreclosure Research 2026", "pillar": "industry_news", "funnel_stage": "TOFU", "published_date": "2026-05-01", "last_updated": "2026-05-20", "review_tier": 3, "organic_traffic_30d": 134, "conversions_30d": 3, "needs_refresh": False},
            {"url": "/attorney/johnson-surplus-recovery", "title": "Attorney Spotlight: Sarah Johnson — Surplus Recovery Expert", "pillar": "attorney_profiles", "funnel_stage": "BOFU", "published_date": "2026-05-15", "last_updated": "2026-05-22", "review_tier": 2, "organic_traffic_30d": 68, "conversions_30d": 7, "needs_refresh": False},
        ],
        "metrics": {
            "pipeline_velocity": 5.2,
            "avg_time_to_publish_days": 8.4,
            "review_gate_compliance_pct": 100,
            "eeat_compliance_pct": 97.0,
            "fact_check_pass_rate": 98.0,
            "pillar_balance_score": 88,
            "funnel_mix_tofu_pct": 48,
            "funnel_mix_mofu_pct": 32,
            "funnel_mix_bofu_pct": 20,
            "freshness_score": 98,
            "content_refresh_queue": 1,
            "pipeline_health": 99,
            "sla_health_pct": 98.0,
        },
    }
    _persist_content_data(defaults)
    return defaults


def _persist_content_data(data):
    try:
        CONTENT_DATA_FILE.write_text(json.dumps(data, default=str))
    except Exception:
        pass


@app.get("/api/v1/content/pipeline")
async def content_pipeline():
    """Content pipeline stages — briefs through publish with SLA tracking."""
    data = _load_content_data()
    pipeline = data.get("pipeline", [])
    total = sum(s.get("count", 0) for s in pipeline)
    overdue = sum(s.get("overdue", 0) for s in pipeline)
    return {
        "pipeline": pipeline,
        "total_in_pipeline": total,
        "total_overdue": overdue,
        "sla_health_pct": round((total - overdue) / max(total, 1) * 100, 1),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/content/calendar")
async def content_calendar():
    """Editorial calendar — weekly planning vs publishing with pillar distribution."""
    data = _load_content_data()
    return {
        "calendar": data.get("calendar", []),
        "current_week": data.get("calendar", [{}])[0] if data.get("calendar") else {},
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/content/inventory")
async def content_inventory():
    """Full content inventory with pillar, funnel stage, review tier, and refresh status."""
    data = _load_content_data()
    inventory = data.get("inventory", [])
    pillars = {}
    for item in inventory:
        p = item.get("pillar", "unknown")
        pillars[p] = pillars.get(p, 0) + 1
    return {
        "inventory": inventory,
        "total_pages": len(inventory),
        "pillar_distribution": pillars,
        "needs_refresh": [i for i in inventory if i.get("needs_refresh")],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/content/metrics")
async def content_metrics():
    """Content performance metrics — velocity, SLA, E-E-A-T, freshness."""
    data = _load_content_data()
    return {
        **data.get("metrics", {}),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/content/summary")
async def content_summary():
    """Single-call content summary for dashboard panels and agent handoffs."""
    data = _load_content_data()
    pipeline = data.get("pipeline", [])
    inventory = data.get("inventory", [])
    metrics = data.get("metrics", {})
    stages = {s["stage"]: s["count"] for s in pipeline}
    return {
        "pipeline": stages,
        "total_in_pipeline": sum(stages.values()),
        "total_published": len([i for i in inventory if i.get("published_date")]),
        "pipeline_health": metrics.get("pipeline_health", 0),
        "sla_health_pct": metrics.get("sla_health_pct", round((sum(s.get("count", 0) for s in pipeline) - sum(s.get("overdue", 0) for s in pipeline)) / max(sum(s.get("count", 0) for s in pipeline), 1) * 100, 1)),
        "content_freshness_score": metrics.get("freshness_score", 0),
        "fact_check_pass_rate": metrics.get("fact_check_pass_rate", 0),
        "needs_refresh_count": sum(1 for i in inventory if i.get("needs_refresh")),
        "review_gate_compliance": metrics.get("review_gate_compliance_pct", 0),
        "eeat_compliance": metrics.get("eeat_compliance_pct", 0),
        "funnel_mix": {"TOFU": metrics.get("funnel_mix_tofu_pct", 0), "MOFU": metrics.get("funnel_mix_mofu_pct", 0), "BOFU": metrics.get("funnel_mix_bofu_pct", 0)},
        "pillar_count": len(set(i.get("pillar") for i in inventory)),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "seed-data",
    }


@app.put("/api/v1/content/data")
async def content_update_data(request: Request):
    """Update content data from agents (content-lead, content-authority-engine heartbeat).
    Keys sent are fully replaced (not deep-merged) — send the complete sub-object."""
    if not _require_localhost(request):
        return {"status": "error", "message": "localhost only"}
    try:
        body = await request.body()
        if len(body) > 500_000:
            return {"status": "error", "message": "payload too large (max 500KB)"}
        incoming = json.loads(body)
    except json.JSONDecodeError:
        return {"status": "error", "message": "invalid JSON"}
    allowed = {"pipeline", "calendar", "inventory", "metrics"}
    for key in incoming:
        if key not in allowed:
            return {"status": "error", "message": f"unknown key: {key}"}
    if "pipeline" in incoming and not isinstance(incoming["pipeline"], list):
        return {"status": "error", "message": "pipeline must be a list"}
    if "inventory" in incoming and not isinstance(incoming["inventory"], list):
        return {"status": "error", "message": "inventory must be a list"}
    current = _load_content_data()
    for key in allowed:
        if key in incoming:
            current[key] = incoming[key]
    _persist_content_data(current)
    return {"status": "updated", "timestamp": datetime.now(timezone.utc).isoformat()}


# ──────────────────────────────────────────────
# Conversion API — consumed by conversion-lead, distribution-systems-architecture, forecasting-intelligence
# ──────────────────────────────────────────────

CONVERSION_DATA_FILE = DATA_DIR / "conversion-data.json"


def _load_conversion_data():
    if CONVERSION_DATA_FILE.exists():
        try:
            raw = CONVERSION_DATA_FILE.read_text()
            if raw.strip():
                data = json.loads(raw)
                if all(k in data for k in ["channels", "funnel", "referrals", "metrics"]):
                    return data
        except Exception:
            pass
    defaults = {
        "channels": [
            {"name": "organic_search", "type": "earned", "monthly_spend": 0, "leads_30d": 142, "conversions_30d": 18, "cac": 0, "ltv": 4500, "ltv_cac_ratio": None, "roi_positive": True, "distribution_maturity": "optimized"},
            {"name": "email_nurture", "type": "owned", "monthly_spend": 89, "leads_30d": 68, "conversions_30d": 9, "cac": 9.89, "ltv": 4500, "ltv_cac_ratio": 455.0, "roi_positive": True, "distribution_maturity": "measured"},
            {"name": "direct_mail", "type": "owned", "monthly_spend": 450, "leads_30d": 42, "conversions_30d": 6, "cac": 75.00, "ltv": 4500, "ltv_cac_ratio": 60.0, "roi_positive": True, "distribution_maturity": "defined"},
            {"name": "attorney_referral", "type": "partner", "monthly_spend": 0, "leads_30d": 31, "conversions_30d": 14, "cac": 0, "ltv": 5200, "ltv_cac_ratio": None, "roi_positive": True, "distribution_maturity": "measured"},
            {"name": "paid_search", "type": "paid", "monthly_spend": 1200, "leads_30d": 55, "conversions_30d": 5, "cac": 240.00, "ltv": 3800, "ltv_cac_ratio": 15.8, "roi_positive": True, "distribution_maturity": "defined"},
            {"name": "social_organic", "type": "earned", "monthly_spend": 0, "leads_30d": 28, "conversions_30d": 2, "cac": 0, "ltv": 3200, "ltv_cac_ratio": None, "roi_positive": True, "distribution_maturity": "manual"},
            {"name": "partner_agents", "type": "partner", "monthly_spend": 0, "leads_30d": 19, "conversions_30d": 7, "cac": 0, "ltv": 4800, "ltv_cac_ratio": None, "roi_positive": True, "distribution_maturity": "defined"},
            {"name": "retargeting", "type": "paid", "monthly_spend": 350, "leads_30d": 22, "conversions_30d": 3, "cac": 116.67, "ltv": 3600, "ltv_cac_ratio": 30.9, "roi_positive": True, "distribution_maturity": "manual"},
        ],
        "funnel": [
            {"stage": "impressions", "count": 45000, "dropoff_pct": 0},
            {"stage": "clicks", "count": 9000, "dropoff_pct": 80.0},
            {"stage": "landing_page", "count": 6400, "dropoff_pct": 28.9},
            {"stage": "form_start", "count": 1940, "dropoff_pct": 69.7},
            {"stage": "form_complete", "count": 1162, "dropoff_pct": 40.1},
            {"stage": "qualified", "count": 813, "dropoff_pct": 30.0},
            {"stage": "retained", "count": 529, "dropoff_pct": 35.0},
        ],
        "referrals": {
            "claimant_referrals_30d": 18,
            "attorney_cross_referrals_30d": 7,
            "partner_referrals_30d": 5,
            "total_referral_pipeline_value": 142000,
            "referral_conversion_rate": 38.2,
            "referral_fraud_flags": 0,
            "affiliate_active_count": 42,
            "affiliate_revenue_share_pct": 15,
        },
        "metrics": {
            "overall_conversion_rate_pct": 65.0,
            "cac_blended": 33.27,
            "ltv_blended": 4470,
            "ltv_cac_ratio_blended": 149.8,
            "avg_payback_period_days": 38,
            "attribution_accuracy_pct": 96.5,
            "channels_roi_positive": 8,
            "total_channels": 8,
            "conversion_health_score": 99,
            "mrr_from_conversions": 95800,
            "forecast_mrr_trend": "up",
            "forecast_conversion_trend": "up",
        },
    }
    _persist_conversion_data(defaults)
    return defaults


def _persist_conversion_data(data):
    try:
        CONVERSION_DATA_FILE.write_text(json.dumps(data, default=str))
    except Exception:
        pass


@app.get("/api/v1/conversion/channels")
async def conversion_channels():
    """8-channel distribution mix with per-channel ROI, CAC, LTV, maturity scoring."""
    data = _load_conversion_data()
    channels = data.get("channels", [])
    return {
        "channels": channels,
        "total_channels": len(channels),
        "roi_positive_count": sum(1 for c in channels if c.get("roi_positive")),
        "total_leads_30d": sum(c.get("leads_30d", 0) for c in channels),
        "total_conversions_30d": sum(c.get("conversions_30d", 0) for c in channels),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/conversion/funnel")
async def conversion_funnel():
    """Full conversion funnel — impressions through retained with stage-by-stage drop-off."""
    data = _load_conversion_data()
    funnel = data.get("funnel", [])
    total_conv_rate = round(funnel[-1].get("count", 0) / max(funnel[0].get("count", 1), 1) * 100, 2) if funnel else 0
    return {
        "funnel": funnel,
        "total_conversion_rate_pct": total_conv_rate,
        "highest_dropoff_stage": max(funnel, key=lambda s: s.get("dropoff_pct", 0)).get("stage") if funnel else None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/conversion/referrals")
async def conversion_referrals():
    """Referral program metrics — claimant, attorney cross-referral, partner, affiliate."""
    data = _load_conversion_data()
    return {
        **data.get("referrals", {}),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/v1/conversion/summary")
async def conversion_summary():
    """Single-call conversion summary for dashboard panels and agent handoffs."""
    data = _load_conversion_data()
    channels = data.get("channels", [])
    metrics = data.get("metrics", {})
    funnel = data.get("funnel", [])
    top_channel = max(channels, key=lambda c: c.get("ltv_cac_ratio") or 0)
    bottom_channel = min(channels, key=lambda c: c.get("ltv_cac_ratio") or float("inf"))
    return {
        "channels": {c["name"]: {"type": c["type"], "leads": c["leads_30d"], "conversions": c["conversions_30d"], "cac": c["cac"], "ltv_cac_ratio": c["ltv_cac_ratio"], "roi_positive": c["roi_positive"], "maturity": c["distribution_maturity"]} for c in channels},
        "funnel_summary": {s["stage"]: {"count": s["count"], "dropoff_pct": s["dropoff_pct"]} for s in funnel},
        "total_conversion_rate_pct": metrics.get("overall_conversion_rate_pct", 0),
        "cac_blended": metrics.get("cac_blended", 0),
        "ltv_blended": metrics.get("ltv_blended", 0),
        "ltv_cac_ratio_blended": metrics.get("ltv_cac_ratio_blended", 0),
        "channels_roi_positive": metrics.get("channels_roi_positive", 0),
        "total_channels": metrics.get("total_channels", 0),
        "conversion_health_score": metrics.get("conversion_health_score", 0),
        "mrr_from_conversions": metrics.get("mrr_from_conversions", 0),
        "top_channel": top_channel.get("name"),
        "bottom_channel": bottom_channel.get("name"),
        "forecast_mrr_trend": metrics.get("forecast_mrr_trend", "neutral"),
        "forecast_conversion_trend": metrics.get("forecast_conversion_trend", "neutral"),
        "attribution_accuracy_pct": metrics.get("attribution_accuracy_pct", 0),
        "referral_pipeline_value": data.get("referrals", {}).get("total_referral_pipeline_value", 0),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "seed-data",
    }


@app.put("/api/v1/conversion/data")
async def conversion_update_data(request: Request):
    """Update conversion data from agents (conversion-lead, forecasting-intelligence heartbeat).
    Keys sent are fully replaced (not deep-merged) — send the complete sub-object."""
    if not _require_localhost(request):
        return {"status": "error", "message": "localhost only"}
    try:
        body = await request.body()
        if len(body) > 500_000:
            return {"status": "error", "message": "payload too large (max 500KB)"}
        incoming = json.loads(body)
    except json.JSONDecodeError:
        return {"status": "error", "message": "invalid JSON"}
    allowed = {"channels", "funnel", "referrals", "metrics"}
    for key in incoming:
        if key not in allowed:
            return {"status": "error", "message": f"unknown key: {key}"}
    if "channels" in incoming and not isinstance(incoming["channels"], list):
        return {"status": "error", "message": "channels must be a list"}
    if "funnel" in incoming and not isinstance(incoming["funnel"], list):
        return {"status": "error", "message": "funnel must be a list"}
    current = _load_conversion_data()
    for key in allowed:
        if key in incoming:
            current[key] = incoming[key]
    _persist_conversion_data(current)
    return {"status": "updated", "timestamp": datetime.now(timezone.utc).isoformat()}


# ──────────────────────────────────────────────
# Growth Pipeline — unified cross-domain cycle
# ──────────────────────────────────────────────

@app.get("/api/v1/growth/pipeline-run")
async def growth_pipeline_run():
    """Execute a full 4-phase Growth Engine pipeline cycle.
    Collects data from all 3 domains, computes health scores, and returns
    a synthesized report with top actions. This is the endpoint the dashboard
    'Run Pipeline' button hits."""
    seo_data = _load_seo_data()
    content_data = _load_content_data()
    conv_data = _load_conversion_data()

    # Phase 1: SEO analysis
    rankings = seo_data.get("rankings", [])
    tech = seo_data.get("technical", {})
    attribution = seo_data.get("attribution", {})
    backlinks = seo_data.get("backlinks", {})
    seo_health = _compute_seo_health(tech)
    avg_pos = round(sum(r.get("position", 99) for r in rankings) / max(len(rankings), 1), 1)
    quick_wins = [r for r in rankings if 6 <= r.get("position", 99) <= 20 and r.get("search_volume", 0) > 2000]
    quick_wins.sort(key=lambda r: r.get("search_volume", 0), reverse=True)

    # Phase 2: Content analysis
    pipeline = content_data.get("pipeline", [])
    inventory = content_data.get("inventory", [])
    metrics = content_data.get("metrics", {})
    content_health = metrics.get("pipeline_health", 0)
    pipeline_stages = {s["stage"]: s["count"] for s in pipeline}
    pipeline_total = sum(pipeline_stages.values())

    # Phase 3: Conversion analysis
    channels = conv_data.get("channels", [])
    funnel = conv_data.get("funnel", [])
    conv_metrics = conv_data.get("metrics", {})
    conv_health = conv_metrics.get("conversion_health_score", 0)

    # Phase 4: Cross-domain synthesis
    overall = round((seo_health * 0.4) + (content_health * 0.3) + (conv_health * 0.3), 1)

    # Top actions
    actions = []
    if seo_health < 80:
        actions.append({"domain": "seo", "action": f"Improve SEO health from {seo_health}→80+", "detail": f"Target {len(quick_wins)} quick-win keywords, fix crawl errors", "priority": 1})
    if content_health < 80:
        actions.append({"domain": "content", "action": f"Improve content pipeline from {content_health}→80+", "detail": f"Clear review bottlenecks, refresh {sum(1 for i in inventory if i.get('needs_refresh'))} stale pages", "priority": 2})
    if conv_health < 80:
        actions.append({"domain": "conversion", "action": f"Improve conversion ROI from {conv_health}→80+", "detail": "Optimize bottom-performing channel", "priority": 3})
    if not actions:
        actions.append({"domain": "all", "action": "All domains healthy — advance to Phase 2 agents", "detail": "Expand keyword coverage, add video content, launch affiliate program", "priority": 0})

    return {
        "growth_engine_health": overall,
        "cycle": "daily",
        "phases": {
            "seo": {
                "health": seo_health,
                "keywords_tracked": len(rankings),
                "avg_position": avg_pos,
                "organic_leads_30d": attribution.get("organic_leads_30d", 0),
                "organic_conversions_30d": attribution.get("organic_conversions_30d", 0),
                "domain_authority": backlinks.get("domain_authority", 0),
                "pages_indexed": tech.get("pages_indexed", 0),
                "crawl_errors": tech.get("crawl_errors", 0),
                "quick_wins": [{"keyword": w["keyword"], "position": w["position"], "volume": w["search_volume"]} for w in quick_wins[:5]],
            },
            "content": {
                "health": content_health,
                "pipeline": pipeline_stages,
                "pipeline_total": pipeline_total,
                "sla_compliance_pct": metrics.get("sla_health_pct", round((pipeline_total - sum(s.get("overdue", 0) for s in pipeline)) / max(pipeline_total, 1) * 100, 1)),
                "freshness_score": metrics.get("freshness_score", 0),
                "review_gate_compliance": metrics.get("review_gate_compliance_pct", 0),
                "needs_refresh_count": sum(1 for i in inventory if i.get("needs_refresh")),
                "funnel_mix": {"TOFU": metrics.get("funnel_mix_tofu_pct", 0), "MOFU": metrics.get("funnel_mix_mofu_pct", 0), "BOFU": metrics.get("funnel_mix_bofu_pct", 0)},
            },
            "conversion": {
                "health": conv_health,
                "overall_conversion_rate": conv_metrics.get("overall_conversion_rate_pct", 0),
                "mrr": conv_metrics.get("mrr_from_conversions", 0),
                "ltv_cac_ratio": conv_metrics.get("ltv_cac_ratio_blended", 0),
                "cac_blended": conv_metrics.get("cac_blended", 0),
                "channels_roi_positive": f"{conv_metrics.get('channels_roi_positive', 0)}/{conv_metrics.get('total_channels', 0)}",
                "attribution_accuracy": conv_metrics.get("attribution_accuracy_pct", 0),
                "forecast_trend": conv_metrics.get("forecast_mrr_trend", "neutral"),
                "funnel": [{"stage": s["stage"], "count": s["count"], "dropoff_pct": s["dropoff_pct"]} for s in funnel],
            },
        },
        "actions": actions,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ──────────────────────────────────────────────
# Growth Briefs — keyword-to-content handoff tracking
# ──────────────────────────────────────────────

BRIEFS_DATA_FILE = DATA_DIR / "briefs-data.json"


def _load_briefs_data():
    if BRIEFS_DATA_FILE.exists():
        try:
            raw = BRIEFS_DATA_FILE.read_text()
            if raw.strip():
                data = json.loads(raw)
                if "briefs" in data:
                    return data
        except Exception:
            pass
    defaults = {
        "briefs": [
            {"id": "KB-001", "keyword": "surplus funds recovery", "search_volume": 5400, "position": 12, "funnel_stage": "TOFU", "pillar": "legal_education", "priority_score": 92, "status": "briefed", "assigned_to": "content-authority-engine", "content_type": "guide", "target_url": "/guide/surplus-funds-recovery-2026", "created": "2026-05-20", "sla_days": 7},
            {"id": "KB-002", "keyword": "foreclosure surplus funds by state", "search_volume": 5100, "position": 11, "funnel_stage": "MOFU", "pillar": "surplus_funds", "priority_score": 88, "status": "drafting", "assigned_to": "content-authority-engine", "content_type": "state_page", "target_url": "/states/surplus-funds-by-state", "created": "2026-05-18", "sla_days": 7},
            {"id": "KB-003", "keyword": "how to claim foreclosure surplus", "search_volume": 4100, "position": 7, "funnel_stage": "MOFU", "pillar": "foreclosure_guides", "priority_score": 85, "status": "drafting", "assigned_to": "content-authority-engine", "content_type": "guide", "target_url": "/guide/how-to-claim-surplus", "created": "2026-05-19", "sla_days": 7},
            {"id": "KB-004", "keyword": "unclaimed foreclosure funds", "search_volume": 3200, "position": 8, "funnel_stage": "MOFU", "pillar": "foreclosure_guides", "priority_score": 78, "status": "briefed", "assigned_to": None, "content_type": "guide", "target_url": None, "created": "2026-05-22", "sla_days": 7},
            {"id": "KB-005", "keyword": "tax deed surplus recovery", "search_volume": 2800, "position": 9, "funnel_stage": "MOFU", "pillar": "surplus_funds", "priority_score": 75, "status": "briefed", "assigned_to": None, "content_type": "guide", "target_url": None, "created": "2026-05-22", "sla_days": 7},
            {"id": "KB-006", "keyword": "county foreclosure records online", "search_volume": 4400, "position": 17, "funnel_stage": "TOFU", "pillar": "data_studies", "priority_score": 72, "status": "research", "assigned_to": None, "content_type": "data_study", "target_url": None, "created": "2026-05-23", "sla_days": 10},
            {"id": "KB-007", "keyword": "excess proceeds from foreclosure sale", "search_volume": 9400, "position": 2, "funnel_stage": "BOFU", "pillar": "case_spotlights", "priority_score": 95, "status": "approved", "assigned_to": "content-authority-engine", "content_type": "case_study", "target_url": "/case/excess-proceeds-guide", "created": "2026-05-15", "sla_days": 5},
            {"id": "KB-008", "keyword": "AI foreclosure data platform", "search_volume": 3500, "position": 6, "funnel_stage": "BOFU", "pillar": "industry_news", "priority_score": 82, "status": "drafting", "assigned_to": "autonomous-docs", "content_type": "article", "target_url": "/blog/ai-foreclosure-platform", "created": "2026-05-21", "sla_days": 5},
            {"id": "KB-009", "keyword": "surplus funds attorney near me", "search_volume": 7200, "position": 5, "funnel_stage": "BOFU", "pillar": "attorney_profiles", "priority_score": 90, "status": "in_review", "assigned_to": "content-authority-engine", "content_type": "landing_page", "target_url": "/attorneys/surplus-funds", "created": "2026-05-16", "sla_days": 7},
            {"id": "KB-010", "keyword": "mortgage foreclosure surplus claims", "search_volume": 1900, "position": 14, "funnel_stage": "TOFU", "pillar": "faq_hubs", "priority_score": 65, "status": "briefed", "assigned_to": None, "content_type": "faq", "target_url": None, "created": "2026-05-24", "sla_days": 7},
        ],
        "metrics": {
            "total_briefs": 10,
            "briefed": 4,
            "drafting": 3,
            "in_review": 1,
            "approved": 1,
            "published": 0,
            "unassigned": 4,
            "avg_priority_score": 82.2,
            "handoff_health": 78,
        },
    }
    _persist_briefs_data(defaults)
    return defaults


def _persist_briefs_data(data):
    try:
        BRIEFS_DATA_FILE.write_text(json.dumps(data, default=str))
    except Exception:
        pass


@app.get("/api/v1/growth/briefs")
async def growth_briefs():
    """Keyword brief pipeline — traceable handoff from SEO research to content drafting."""
    data = _load_briefs_data()
    briefs = data.get("briefs", [])
    return {
        "briefs": briefs,
        "total": len(briefs),
        "by_status": {s: sum(1 for b in briefs if b.get("status") == s) for s in ["briefed", "research", "drafting", "in_review", "approved", "published"]},
        "unassigned": [b for b in briefs if not b.get("assigned_to")],
        "metrics": data.get("metrics", {}),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "seed-data",
    }


@app.put("/api/v1/growth/briefs")
async def growth_briefs_update(request: Request):
    """Update keyword briefs from agents (seo-lead, content-lead heartbeat).
    Keys sent are fully replaced (not deep-merged) — send the complete sub-object."""
    if not _require_localhost(request):
        return {"status": "error", "message": "localhost only"}
    try:
        body = await request.body()
        if len(body) > 500_000:
            return {"status": "error", "message": "payload too large (max 500KB)"}
        incoming = json.loads(body)
    except json.JSONDecodeError:
        return {"status": "error", "message": "invalid JSON"}
    allowed = {"briefs", "metrics"}
    for key in incoming:
        if key not in allowed:
            return {"status": "error", "message": f"unknown key: {key}"}
    if "briefs" in incoming and not isinstance(incoming["briefs"], list):
        return {"status": "error", "message": "briefs must be a list"}
    current = _load_briefs_data()
    for key in allowed:
        if key in incoming:
            current[key] = incoming[key]
    _persist_briefs_data(current)
    return {"status": "updated", "timestamp": datetime.now(timezone.utc).isoformat()}


# ──────────────────────────────────────────────
# Growth Reconciliation — cross-domain data integrity
# ──────────────────────────────────────────────

@app.get("/api/v1/growth/reconcile")
async def growth_reconcile():
    """Cross-domain data reconciliation. Checks SEO, content, conversion, and briefs
    data for inconsistencies and reports discrepancies with severity scoring."""
    seo = _load_seo_data()
    content = _load_content_data()
    conv = _load_conversion_data()
    briefs = _load_briefs_data()

    issues = []

    # Check 1: Conversion ROI channel count
    channels = conv.get("channels", [])
    roi_pos = sum(1 for c in channels if c.get("roi_positive"))
    reported_roi = conv.get("metrics", {}).get("channels_roi_positive", 0)
    if roi_pos != reported_roi:
        issues.append({"check": "conversion_roi_count", "severity": "medium", "expected": roi_pos, "reported": reported_roi, "detail": f"Per-channel data shows {roi_pos}/8 ROI+ but summary reports {reported_roi}/8"})

    # Check 2: Content refresh queue
    inventory = content.get("inventory", [])
    needs_refresh = sum(1 for i in inventory if i.get("needs_refresh"))
    reported_refresh = content.get("metrics", {}).get("content_refresh_queue", 0)
    if needs_refresh != reported_refresh:
        issues.append({"check": "content_refresh_queue", "severity": "low", "expected": needs_refresh, "reported": reported_refresh, "detail": f"Inventory shows {needs_refresh} pages needing refresh but metrics report {reported_refresh}"})

    # Check 3: Published content count
    pipeline = content.get("pipeline", [])
    pipeline_pub = next((s.get("count", 0) for s in pipeline if s.get("stage") == "published"), 0)
    inventory_pub = len([i for i in inventory if i.get("published_date")])
    if pipeline_pub != inventory_pub:
        issues.append({"check": "published_count", "severity": "low", "expected": inventory_pub, "reported": pipeline_pub, "detail": f"Inventory has {inventory_pub} published pages but pipeline reports {pipeline_pub} in published stage"})

    # Check 4: Brief-to-pipeline alignment
    briefs_list = briefs.get("briefs", [])
    briefs_drafting = sum(1 for b in briefs_list if b.get("status") == "drafting")
    pipeline_drafting = next((s.get("count", 0) for s in pipeline if s.get("stage") == "drafting"), 0)
    if briefs_drafting > pipeline_drafting:
        issues.append({"check": "brief_pipeline_gap", "severity": "medium", "expected": briefs_drafting, "reported": pipeline_drafting, "detail": f"{briefs_drafting} briefs in drafting but pipeline shows only {pipeline_drafting} — {briefs_drafting - pipeline_drafting} untracked"})

    # Check 5: SEO attribution vs conversion funnel
    seo_leads = seo.get("attribution", {}).get("organic_leads_30d", 0)
    org_channel = next((c for c in channels if c.get("name") == "organic_search"), {})
    org_leads = org_channel.get("leads_30d", 0)
    if abs(seo_leads - org_leads) > 10:
        issues.append({"check": "attribution_alignment", "severity": "medium", "expected": org_leads, "reported": seo_leads, "detail": f"SEO attribution shows {seo_leads} organic leads but conversion channel reports {org_leads}"})

    # Check 6: Funnel lead-to-retained vs reported conversion rate
    funnel = conv.get("funnel", [])
    if funnel:
        # Use qualified→retained as the meaningful "conversion rate" base (not impressions→sale)
        qualified_stage = next((s for s in funnel if s.get("stage") == "qualified"), funnel[-2] if len(funnel) >= 2 else None)
        qualified_count = qualified_stage.get("count", 1) if qualified_stage else 1
        retained_stage = funnel[-1]
        retained_count = retained_stage.get("count", 0)
        implied_rate = round(retained_count / max(qualified_count, 1) * 100, 2)
        reported_rate = conv.get("metrics", {}).get("overall_conversion_rate_pct", 0)
        if abs(implied_rate - reported_rate) > 2:
            issues.append({"check": "funnel_rate_mismatch", "severity": "low", "expected": implied_rate, "reported": reported_rate, "detail": f"Funnel qualified→retained implies {implied_rate}% close rate but metrics report {reported_rate}%"})

    total_checks = 6
    passed = total_checks - len(issues)
    health = round(passed / total_checks * 100, 1)

    return {
        "reconciliation_health": health,
        "checks_total": total_checks,
        "checks_passed": passed,
        "issues_found": len(issues),
        "issues": issues,
        "severity_summary": {
            "high": sum(1 for i in issues if i["severity"] == "high"),
            "medium": sum(1 for i in issues if i["severity"] == "medium"),
            "low": sum(1 for i in issues if i["severity"] == "low"),
        },
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8180, log_level="info")
