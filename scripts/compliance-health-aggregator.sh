#!/bin/bash
# Wheeler Legal/Compliance OS — Health Aggregator
# Aggregates compliance scores from all 8 domains into composite health score.
# Reads score files from $SCORE_DIR, normalizes by domain max, applies weights.
# Output: /root/scripts/aiops-watchdog/compliance-health.json

set -euo pipefail
OUTPUT_FILE="${1:-/root/scripts/aiops-watchdog/compliance-health.json}"
SCORE_DIR="/root/scripts/aiops-watchdog/compliance-scores"
mkdir -p "$SCORE_DIR"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOSTNAME=$(hostname)

# Use Python for correct weighted calculation
python3 << 'PYEOF'
import os, json, subprocess
from datetime import datetime, timezone

SCORE_DIR = "/root/scripts/aiops-watchdog/compliance-scores"
OUTPUT = os.environ.get("OUTPUT_FILE", "/root/scripts/aiops-watchdog/compliance-health.json")

# Domain definitions: (key, max_score, weight_pct, display_name)
domains = [
    ("tcpa",     20, 20, "TCPA/Outreach"),
    ("upl",      20, 20, "UPL Boundaries"),
    ("state",    15, 15, "State Compliance"),
    ("privacy",  15, 15, "Data Privacy"),
    ("attorney", 10, 10, "Attorney Market"),
    ("ai",       10, 10, "AI Governance"),
    ("contract",  5,  5, "Contract Gov"),
    ("audit_trail", 5, 5, "Audit Trail"),
]

def read_score(key, default=0):
    path = os.path.join(SCORE_DIR, f"{key}.score")
    if os.path.exists(path):
        try:
            return int(open(path).read().strip())
        except:
            return default
    return default

def read_gate(key):
    path = os.path.join(SCORE_DIR, f"{key}.gate")
    if os.path.exists(path):
        return open(path).read().strip()
    return "NOT_AUDITED"

# Compute composite
domain_scores = {}
composite = 0.0
for key, max_s, weight_pct, display in domains:
    raw = read_score(key)
    pct = raw / max_s if max_s > 0 else 0
    weighted = pct * weight_pct
    composite += weighted
    domain_scores[key] = {
        "score": raw,
        "max": max_s,
        "pct": round(pct * 100, 1),
        "weight": weight_pct / 100.0,
        "weighted": round(weighted, 2),
        "display": display
    }

composite = round(composite, 1)

if composite >= 95: rating = "A+"
elif composite >= 85: rating = "A"
elif composite >= 70: rating = "B"
else: rating = "CRITICAL"

# Agent/command/deliverable counts
agent_dir = "/root/.claude/agents"
cmd_dir = "/root/.claude/commands"
docs_dir = "/root/legal-compliance-os"

agent_count = len([f for f in os.listdir(agent_dir) if f.endswith('.md')])
cmd_count = len([f for f in os.listdir(cmd_dir) if f.endswith('.md') and 'compliance' in f.lower() or 'tcp' in f.lower() or 'upl' in f.lower() or 'critical' in f.lower() or 'rule54' in f.lower() or 'outside' in f.lower() or 'tier3' in f.lower()])
deliverable_count = len([f for f in os.listdir(docs_dir) if f.endswith('.md')])

# Gate statuses
gates = {
    "tcp_gate": read_gate("tcp"),
    "upl_gate": read_gate("upl"),
    "rule54_gate": read_gate("rule54"),
    "outside_counsel_gate": read_gate("outside_counsel"),
    "tier3_gate": read_gate("tier3"),
}

all_gates_pass = all(v.startswith("PASS") for v in gates.values())

report = {
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostname": os.uname().nodename,
    "compliance_os_version": "1.0.0",
    "composite_score": composite,
    "rating": rating,
    "domain_scores": domain_scores,
    "critical_actions": gates,
    "infrastructure": {
        "agents_deployed": agent_count,
        "agents_target": 30,
        "commands_wired": cmd_count,
        "commands_target": 10,
        "deliverables_produced": deliverable_count,
        "deliverables_target": 13
    },
    "readiness": {
        "agent_army": "DEPLOYED" if agent_count >= 30 else "INCOMPLETE",
        "command_layer": "WIRED" if cmd_count >= 10 else "INCOMPLETE",
        "deliverables": "COMPLETE" if deliverable_count >= 13 else "INCOMPLETE",
        "enforcement_gates": "ALL_CLEAR" if all_gates_pass else "GATES_OPEN",
        "overall": "FULLY_OPERATIONAL" if composite >= 95 else ("OPERATIONAL_WITH_GAPS" if composite >= 70 else "CRITICAL_GAPS")
    }
}

with open(OUTPUT, "w") as f:
    json.dump(report, f, indent=2)

print(f"[compliance-health] Composite={composite}/100 Rating={rating} Agents={agent_count}/30")
print(f"  Gates: TCPA={gates['tcp_gate']} UPL={gates['upl_gate']} Rule54={gates['rule54_gate']} Counsel={gates['outside_counsel_gate']} Tier3={gates['tier3_gate']}")
print(f"  Readiness: {report['readiness']['overall']}")
print(f"  Report: {OUTPUT}")
PYEOF
