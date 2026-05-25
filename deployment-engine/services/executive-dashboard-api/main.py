"""Executive Dashboard API — Wheeler Financial OS v2.0. Live data from Docker, PM2, LiteLLM, /proc."""
import os, json, subprocess, time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Wheeler Financial OS Dashboard", version="2.0.0")

DATA_DIR = Path("/opt/apps/executive-dashboard-api/data")
DATA_DIR.mkdir(parents=True, exist_ok=True)

class KpiMetric(BaseModel):
    label: str; value: float; unit: str; change_pct: float; trend: str

def run(cmd, timeout=5):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except: return ""

def get_docker_stats():
    containers = []
    try:
        out = run("docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}'")
        for line in out.split("\n"):
            parts = line.split("\t")
            if len(parts) >= 6:
                containers.append({"name":parts[0],"cpu":parts[1],"mem_pct":parts[2],"mem_usage":parts[3],"net_io":parts[4],"block_io":parts[5]})
    except: pass
    return containers

def get_docker_count():
    try:
        out = run("docker ps -q | wc -l")
        return int(out) if out else 0
    except: return 0

def get_docker_healthy():
    try:
        out = run("docker ps --filter 'health=healthy' -q | wc -l")
        return int(out) if out else 0
    except: return 0

def get_docker_unhealthy():
    """Only containers with explicit failing health checks, not containers missing HEALTHCHECK."""
    try:
        out = run("docker ps --filter 'health=unhealthy' -q | wc -l")
        return int(out) if out else 0
    except: return 0

def get_docker_no_healthcheck():
    """Containers running without HEALTHCHECK defined (informational, not an alert)."""
    try:
        all_ids = run("docker ps -q").strip().split()
        healthy_ids = run("docker ps --filter 'health=healthy' -q").strip().split()
        unhealthy_ids = run("docker ps --filter 'health=unhealthy' -q").strip().split()
        checked = set(healthy_ids + unhealthy_ids)
        return len([i for i in all_ids if i and i not in checked])
    except: return 0

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
    except: pass
    return processes

def get_pm2_counts():
    try:
        out = run("pm2 jlist")
        data = json.loads(out)
        online = sum(1 for p in data if p.get("pm2_env",{}).get("status")=="online")
        return {"online": online, "total": len(data)}
    except: return {"online": 0, "total": 0}

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
    except: return {"total_spend_24h": 0.0, "by_model": {}}

def get_litellm_health():
    try:
        start = time.time()
        out = run("curl -s http://127.0.0.1:4049/health 2>/dev/null")
        latency = round((time.time() - start) * 1000, 1)
        return {"status": "healthy" if out else "unreachable", "latency_ms": latency}
    except: return {"status": "unreachable", "latency_ms": 0}

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
    except: return {}

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
    except:
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
    return get_litellm_spend(hours)

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
    except: pass

    memory = {}
    try:
        out = run("curl -s http://127.0.0.1:8160/api/v1/memory/stats 2>/dev/null")
        memory = json.loads(out)
    except: pass

    domains = []
    try:
        out = run("curl -s http://127.0.0.1:8160/api/v1/graph/domains 2>/dev/null")
        domains = json.loads(out).get("domains", [])
    except: pass

    pm2 = get_pm2_counts()
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

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8180, log_level="info")
