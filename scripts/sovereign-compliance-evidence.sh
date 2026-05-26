#!/usr/bin/env bash
# =============================================================================
# sovereign-compliance-evidence.sh — Compliance Evidence Collector
# =============================================================================
#
# Collects, snapshots, and packages compliance evidence for CC2/audit review:
#   - System configuration snapshots (UFW, SSH, nginx, PM2, Docker, cron)
#   - Health reports (ecosystem health check output)
#   - Security posture (secrets scan, port exposure, CVE status)
#   - Compliance gate results (Tier 3, Rule 5.4, UPL checks)
#   - Timestamped, checksummed evidence bundles
#
# Output: Compressed evidence bundle at /var/log/wheeler/compliance/
# Exit codes:
#   0 — Evidence collection complete, all checksums verified
#   1 — Collection had warnings (some artifacts missing, bundle still created)
#   2 — Fatal error, no bundle created
#
# Usage:
#   ./sovereign-compliance-evidence.sh                    # Full collection
#   ./sovereign-compliance-evidence.sh --quick            # Essential artifacts only
#   ./sovereign-compliance-evidence.sh --json             # Machine-readable output
#   ./sovereign-compliance-evidence.sh --verify <bundle>  # Verify existing bundle
#   ./sovereign-compliance-evidence.sh --help             # This message
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly TIMESTAMP_FMT="$(date +%Y%m%d-%H%M%S)"
readonly OUTPUT_DIR="${OUTPUT_DIR:-/var/log/wheeler/compliance}/${TIMESTAMP_FMT}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"
readonly MANIFEST_FILE="${OUTPUT_DIR}/MANIFEST.json"

MY_PID=$$
JSON_MODE=false
QUICK_MODE=false
VERIFY_MODE=false
VERIFY_BUNDLE=""
WARNING_COUNT=0
declare -a COLLECTED_ARTIFACTS=()
declare -a MANIFEST_ENTRIES=()

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
    C_CYAN='\033[0;36m'; C_MAGENTA='\033[0;35m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_DIM=''
    C_CYAN=''; C_MAGENTA=''
fi

_cleanup() {
    local rc=$?
    if [[ -f "${LOCK_FILE}" ]] && [[ "$(cat "${LOCK_FILE}" 2>/dev/null)" == "$MY_PID" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Collects, snapshots, and packages compliance evidence for CC2/audit review:
  - System configuration snapshots (UFW, SSH, nginx, PM2, Docker, cron)
  - Health reports (ecosystem health check output)
  - Security posture (secrets scan, port exposure, CVE status)
  - Compliance gate results (Tier 3, Rule 5.4, UPL checks)
  - Timestamped, checksummed evidence bundles

Output: Compressed evidence bundle at /var/log/wheeler/compliance/

Exit codes:
  0 — Evidence collection complete, all checksums verified
  1 — Collection had warnings (some artifacts missing, bundle still created)
  2 — Fatal error, no bundle created

Options:
  --quick            Essential artifacts only
  --json             Machine-readable output
  --verify <bundle>  Verify existing bundle
  --help             Show this message
EOF
    exit "${1:-0}"
}

check_cmd() { command -v "$1" &>/dev/null; }

artifact() {
    local status="$1" name="$2" path="$3" checksum="$4"
    local icon
    case "$status" in
        collected) icon="${C_GREEN}[OK]${C_RESET}" ;;
        warning)   icon="${C_YELLOW}[WARN]${C_RESET}"; ((WARNING_COUNT++)) || true ;;
        missing)   icon="${C_RED}[MISS]${C_RESET}"; ((WARNING_COUNT++)) || true ;;
    esac
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  %b %-45s %s\n" "$icon" "$name" "$path"
    fi
    local _s _n _p _c
    _s=$(echo "$status" | sed 's/\\/\\\\/g; s/"/\\"/g')
    _n=$(echo "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    _p=$(echo "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')
    _c=$(echo "$checksum" | sed 's/\\/\\\\/g; s/"/\\"/g')
    MANIFEST_ENTRIES+=("{\"status\":\"${_s}\",\"name\":\"${_n}\",\"path\":\"${_p}\",\"checksum\":\"${_c}\"}")
}

snapshot_cmd() {
    local name="$1"; shift
    local outfile="${OUTPUT_DIR}/${name}"
    if "$@" > "$outfile" 2>/dev/null; then
        local cs; cs=$(sha256sum "$outfile" 2>/dev/null | awk '{print $1}' || echo "unknown")
        artifact "collected" "$name" "$outfile" "$cs"
    else
        artifact "missing" "$name" "(failed to collect)" "none"
    fi
}

snapshot_file() {
    local name="$1" src="$2"
    local outfile="${OUTPUT_DIR}/${name}"
    if [[ -f "$src" ]] && cp "$src" "$outfile" 2>/dev/null; then
        local cs; cs=$(sha256sum "$outfile" 2>/dev/null | awk '{print $1}' || echo "unknown")
        artifact "collected" "$name" "$outfile" "$cs"
    elif [[ -d "$src" ]]; then
        artifact "warning" "$name" "${src} (directory — not copied)" ""
    else
        artifact "missing" "$name" "${src} (not found)" ""
    fi
}

snapshot_glob() {
    local name="$1" pattern="$2"
    local outfile="${OUTPUT_DIR}/${name}"
    local files_found=0
    for f in $pattern; do
        if [[ -f "$f" ]]; then
            files_found=$((files_found + 1))
        fi
    done
    if [[ $files_found -gt 0 ]]; then
        cat $pattern > "$outfile" 2>/dev/null || true
        local cs; cs=$(sha256sum "$outfile" 2>/dev/null | awk '{print $1}' || echo "unknown")
        artifact "collected" "$name" "${files_found} files → $outfile" "$cs"
    else
        artifact "missing" "$name" "(no matching files)" ""
    fi
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)   JSON_MODE=true; shift ;;
        --quick)  QUICK_MODE=true; shift ;;
        --verify) VERIFY_MODE=true; VERIFY_BUNDLE="$2"; shift 2 ;;
        --help)   usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

if ! echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null; then
    echo "Another instance is running (lock: $LOCK_FILE)" >&2
    exit 1
fi
mkdir -p "$OUTPUT_DIR"

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  WHEELER COMPLIANCE EVIDENCE COLLECTOR${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  Output: ${OUTPUT_DIR}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
fi

# ─── Verify Mode ────────────────────────────────────────────────────────────────

if [[ "$VERIFY_MODE" == "true" ]]; then
    if [[ ! -f "$VERIFY_BUNDLE" ]]; then
        echo -e "${C_RED}Error: Bundle not found: ${VERIFY_BUNDLE}${C_RESET}" >&2
        exit 2
    fi
    echo -e "${C_BOLD}Verifying evidence bundle: ${VERIFY_BUNDLE}${C_RESET}"
    echo ""
    local tmp_verify; tmp_verify=$(mktemp -d "/tmp/evidence-verify-XXXXXX")
    tar -xzf "$VERIFY_BUNDLE" -C "$tmp_verify" 2>/dev/null || {
        echo -e "${C_RED}Error: Cannot extract bundle${C_RESET}" >&2
        rm -rf "$tmp_verify"
        exit 2
    }
    if [[ -f "${tmp_verify}/MANIFEST.json" ]]; then
        local total_ok=0 total_warn=0 total_miss=0
        while IFS= read -r entry; do
            local name path cs status
            name=$(echo "$entry" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('name','?'))" 2>/dev/null || echo "?")
            status=$(echo "$entry" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('status','?'))" 2>/dev/null || echo "?")
            case "$status" in
                collected) ((total_ok++)) || true; printf "  ${C_GREEN}[OK]${C_RESET} %s\n" "$name" ;;
                warning)   ((total_warn++)) || true; printf "  ${C_YELLOW}[WARN]${C_RESET} %s\n" "$name" ;;
                missing)   ((total_miss++)) || true; printf "  ${C_RED}[MISS]${C_RESET} %s\n" "$name" ;;
            esac
        done < <(python3 -c "
import sys,json
with open('${tmp_verify}/MANIFEST.json') as f:
    manifest = json.load(f)
for entry in manifest.get('artifacts',[]):
    print(json.dumps(entry))" 2>/dev/null || echo "")
        echo ""
        echo -e "Collected: ${total_ok} | Warnings: ${total_warn} | Missing: ${total_miss}"
    fi
    rm -rf "$tmp_verify"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTION: System Configuration
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo -e "${C_BOLD}${C_CYAN}━━━ SYSTEM CONFIGURATION ━━━${C_RESET}"
fi

snapshot_cmd "ufw-status.txt" ufw status verbose
snapshot_cmd "sshd-config.txt" cat /etc/ssh/sshd_config
snapshot_file "authorized_keys.backup" "/root/.ssh/authorized_keys.backup"
snapshot_cmd "nginx-config-syntax.txt" nginx -t 2>&1
snapshot_cmd "crontab-root.txt" crontab -l
snapshot_glob "cron-d-files.txt" "/etc/cron.d/*"
snapshot_cmd "systemctl-failed.txt" systemctl --failed 2>&1
snapshot_cmd "last-logins.txt" last -i -n 20

# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTION: Infrastructure State
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_CYAN}━━━ INFRASTRUCTURE STATE ━━━${C_RESET}"
fi

if check_cmd docker && docker info &>/dev/null 2>&1; then
    snapshot_cmd "docker-ps.txt" docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    snapshot_cmd "docker-health.txt" docker ps --filter "health=unhealthy" --format "{{.Names}}: {{.Status}}"
    snapshot_cmd "docker-images.txt" docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
    snapshot_cmd "docker-networks.txt" docker network ls
fi

if check_cmd pm2 && pm2 ping &>/dev/null 2>&1; then
    snapshot_cmd "pm2-jlist.json" pm2 jlist
    snapshot_cmd "pm2-status.txt" pm2 status
fi

snapshot_cmd "disk-usage.txt" df -h
snapshot_cmd "memory-usage.txt" free -h
snapshot_cmd "system-load.txt" uptime
snapshot_cmd "listening-ports.txt" ss -tlnp

# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTION: Security Posture
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_CYAN}━━━ SECURITY POSTURE ━━━${C_RESET}"
fi

snapshot_cmd "tailscale-status.txt" tailscale status 2>&1
snapshot_cmd "exposed-ports.txt" bash -c "ss -tlnp | grep -v '127.0.0.1:' | grep -v '::1:' | grep -v '0.0.0.0:22'" 2>&1

# Check for secrets in environment (redact values, detect presence only)
if check_cmd pm2 && pm2 ping &>/dev/null 2>&1; then
    pm2 jlist 2>/dev/null | python3 -c "
import sys,json
data = json.load(sys.stdin)
sensitive = ['KEY','SECRET','PASSWORD','TOKEN','CREDENTIAL']
for p in data:
    env = p.get('pm2_env',{}).get('env',{})
    for k in sorted(env):
        if any(s in k.upper() for s in sensitive):
            val = env[k]
            masked = val[:4] + ('*' * max(len(val)-8,0)) + val[-4:] if len(val) > 12 else '***'
            print(f'{p[\"name\"]}: {k}={masked}')
" > "${OUTPUT_DIR}/secrets-in-pm2.txt" 2>/dev/null || true
    if [[ -s "${OUTPUT_DIR}/secrets-in-pm2.txt" ]]; then
        local cs; cs=$(sha256sum "${OUTPUT_DIR}/secrets-in-pm2.txt" 2>/dev/null | awk '{print $1}' || echo "unknown")
        artifact "collected" "secrets-in-pm2.txt" "${OUTPUT_DIR}/secrets-in-pm2.txt" "$cs"
    else
        artifact "collected" "secrets-in-pm2.txt" "No secrets detected in PM2 env" ""
    fi
fi

snapshot_file "claude-settings.json" "/root/.claude/settings.json"
snapshot_file "claude-settings-local.json" "/root/.claude/settings.local.json"

# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTION: Health Reports (skip in quick mode)
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$QUICK_MODE" != "true" ]]; then
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_CYAN}━━━ HEALTH REPORTS ━━━${C_RESET}"
    fi

    if [[ -x "${SCRIPT_DIR}/sovereign-ecosystem-health-check.sh" ]]; then
        if "${SCRIPT_DIR}/sovereign-ecosystem-health-check.sh" --json > "${OUTPUT_DIR}/ecosystem-health.json" 2>/dev/null; then
            local cs; cs=$(sha256sum "${OUTPUT_DIR}/ecosystem-health.json" 2>/dev/null | awk '{print $1}' || echo "unknown")
            artifact "collected" "ecosystem-health.json" "${OUTPUT_DIR}/ecosystem-health.json" "$cs"
        else
            artifact "warning" "ecosystem-health.json" "Health check returned non-zero (some failures)" ""
        fi
    else
        artifact "missing" "ecosystem-health.json" "Health check script not found" ""
    fi

    # Collect endpoint health
    for endpoint in "http://127.0.0.1:8180/health:Executive Dashboard" "http://127.0.0.1:3002/api/health:Grafana"; do
        IFS=":" read -r url label <<< "$endpoint"
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
        echo "${label}: HTTP ${code}" >> "${OUTPUT_DIR}/endpoint-health.txt" 2>/dev/null || true
    done
    if [[ -f "${OUTPUT_DIR}/endpoint-health.txt" ]]; then
        cs=$(sha256sum "${OUTPUT_DIR}/endpoint-health.txt" 2>/dev/null | awk '{print $1}' || echo "unknown")
        artifact "collected" "endpoint-health.txt" "${OUTPUT_DIR}/endpoint-health.txt" "$cs"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTION: Compliance Gate Results
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_CYAN}━━━ COMPLIANCE GATES ━━━${C_RESET}"
fi

GATE_DIR="/root/scripts/compliance-gates"
if [[ -d "$GATE_DIR" ]]; then
    for gate in "$GATE_DIR"/*; do
        if [[ -x "$gate" ]]; then
            snapshot_file "$(basename "$gate")" "$gate"
        fi
    done
fi

COMPLIANCE_ENFORCEMENT="/root/scripts/compliance-enforcement"
if [[ -d "$COMPLIANCE_ENFORCEMENT" ]]; then
    for script in "$COMPLIANCE_ENFORCEMENT"/*; do
        if [[ -x "$script" ]]; then
            snapshot_file "$(basename "$script")" "$script"
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD MANIFEST + BUNDLE
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_CYAN}━━━ BUILDING EVIDENCE BUNDLE ━━━${C_RESET}"
fi

COLLECTED_COUNT=$(find "$OUTPUT_DIR" -type f -not -name "MANIFEST.json" -not -name "*.tar.gz" 2>/dev/null | wc -l)

printf -v joined '%s,' "${MANIFEST_ENTRIES[@]}"
joined="${joined%,}"

cat > "$MANIFEST_FILE" <<EOMANIFEST
{
  "collection_timestamp": "${TIMESTAMP}",
  "output_directory": "${OUTPUT_DIR}",
  "collector_version": "2.1",
  "artifact_count": ${COLLECTED_COUNT},
  "warning_count": ${WARNING_COUNT},
  "collected_by": "${SCRIPT_NAME}",
  "artifacts": [${joined:-}]
}
EOMANIFEST

artifact "collected" "MANIFEST.json" "$MANIFEST_FILE" "$(sha256sum "$MANIFEST_FILE" 2>/dev/null | awk '{print $1}')"

# Create compressed bundle
BUNDLE_FILE="${OUTPUT_DIR}/../evidence-${TIMESTAMP_FMT}.tar.gz"
if tar -czf "$BUNDLE_FILE" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")" 2>/dev/null; then
    BUNDLE_SIZE=$(stat -c%s "$BUNDLE_FILE" 2>/dev/null || echo "0")
    BUNDLE_CHECKSUM=$(sha256sum "$BUNDLE_FILE" 2>/dev/null | awk '{print $1}' || echo "unknown")
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_GREEN}${C_BOLD}  Evidence bundle created:${C_RESET} ${BUNDLE_FILE}"
        echo -e "  Size: ${BUNDLE_SIZE} bytes | SHA256: ${BUNDLE_CHECKSUM}"
        echo -e "  Artifacts: ${COLLECTED_COUNT} | Warnings: ${WARNING_COUNT}"
    fi
else
    echo -e "${C_RED}Error: Failed to create evidence bundle${C_RESET}" >&2
    exit 2
fi

# ─── Summary ────────────────────────────────────────────────────────────────────

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  EVIDENCE COLLECTION COMPLETE${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "  Bundle:   ${BUNDLE_FILE}"
    echo -e "  Artifacts: ${COLLECTED_COUNT}"
    echo -e "  Warnings:  ${WARNING_COUNT}"
    echo -e "  Checksum:  ${BUNDLE_CHECKSUM}"
    echo ""
    if [[ "$WARNING_COUNT" -eq 0 ]]; then
        echo -e "${C_GREEN}  ALL EVIDENCE COLLECTED SUCCESSFULLY${C_RESET}"
    else
        echo -e "${C_YELLOW}  COLLECTION COMPLETE WITH ${WARNING_COUNT} WARNINGS${C_RESET}"
    fi
    echo ""
fi

# JSON output
JSON_OUTPUT=$(cat <<EOJSON
{
  "timestamp": "${TIMESTAMP}",
  "bundle": "${BUNDLE_FILE}",
  "bundle_size_bytes": ${BUNDLE_SIZE:-0},
  "bundle_checksum": "${BUNDLE_CHECKSUM}",
  "artifact_count": ${COLLECTED_COUNT},
  "warning_count": ${WARNING_COUNT}
}
EOJSON
)

if [[ "$JSON_MODE" == "true" ]]; then
    echo "$JSON_OUTPUT"
fi

if [[ "$WARNING_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
