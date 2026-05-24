#!/usr/bin/env bash
#===============================================================================
# port-watchdog.sh
# Wheeler Autonomous AI Ops Platform - Network Port Bind Monitor
#
# Monitors all listening ports for:
#   - 0.0.0.0 binds (flags all except SSH:22)
#   - New listeners not in known baseline
#   - Missing expected listeners from baseline
#
# Usage:
#   ./port-watchdog.sh                              # Alerts for any drift
#   ./port-watchdog.sh --baseline /path/to/baseline # Custom baseline file
#   ./port-watchdog.sh --help                       # This help text
#
# Output: Alerts to stdout for any port drift detected
# Severity levels: INFO, WARN, HIGH, CRITICAL
#===============================================================================
set -euo pipefail

# ---- Constants ----
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_BASELINE="${SCRIPT_DIR}/port-baseline.txt"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ALERTS=()

# ---- Known exceptions ----
# Processes that are allowed to bind 0.0.0.0 (beyond SSH)
ALLOWED_0_0_0_0_PROCS=(
    "sshd"
    "dockerd"
    "systemd-resolve"
    "tailscaled"
    "nginx"
)

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Output helpers ----
alert() {
    local severity="$1"
    local message="$2"
    local entry="[${severity}] [${TIMESTAMP}] [port-watchdog] ${message}"
    ALERTS+=("${entry}")
    echo "${entry}" >&2
}

is_allowed_0_0_0_0() {
    local proc_name="$1"
    local port="$2"

    # SSH on port 22 is always allowed
    if [[ "${port}" == "22" ]]; then
        return 0
    fi

    for allowed in "${ALLOWED_0_0_0_0_PROCS[@]}"; do
        if echo "${proc_name}" | grep -qi "${allowed}"; then
            return 0
        fi
    done

    return 1
}

# ---- Main ----
main() {
    local baseline_file="${DEFAULT_BASELINE}"
    for arg in "$@"; do
        case "${arg}" in
            --help|-h) show_help ;;
            --baseline)
                # Next arg is baseline path - handled below
                ;;
            --baseline=*)
                baseline_file="${arg#*=}"
                ;;
        esac
    done

    # Handle --baseline with separate value argument
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[$i]}" == "--baseline" && $((i+1)) -lt ${#args[@]} ]]; then
            baseline_file="${args[$((i+1))]}"
        fi
    done

    if [[ ! -f "${baseline_file}" ]]; then
        echo "ERROR: Baseline file not found: ${baseline_file}" >&2
        echo "Generate one by capturing known-good state." >&2
        exit 1
    fi

    # Load baseline into associative array: address:port -> description
    declare -A BASELINE
    while IFS= read -r line; do
        # Strip comments
        line="${line%%#*}"
        # Strip leading/trailing whitespace
        line="$(echo "${line}" | xargs)"
        [[ -z "${line}" ]] && continue
        # Format: "address:port   description"
        local addr_port="${line%% *}"
        local desc="${line#* }"
        if [[ -n "${addr_port}" ]]; then
            BASELINE["${addr_port}"]="${desc}"
        fi
    done < "${baseline_file}"

    # Gather current listening ports
    local ss_output
    ss_output="$(ss -tlnp 2>/dev/null)" || {
        alert "CRITICAL" "Cannot run ss -tlnp (permission denied or missing)"
        exit 1
    }

    declare -A CURRENT_BINDS
    declare -A CURRENT_PROCS

    while IFS= read -r line; do
        line="$(echo "${line}" | xargs)"
        [[ -z "${line}" ]] && continue
        # Parse ss output format: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
        local addr_port proc_info
        addr_port="$(echo "${line}" | awk '{print $4}')"
        proc_info="$(echo "${line}" | awk '{print $6}' | sed 's/users:((//' | sed 's/))//' | cut -d',' -f1 | cut -d'"' -f2)"
        [[ -z "${addr_port}" ]] && continue

        CURRENT_BINDS["${addr_port}"]=1
        CURRENT_PROCS["${addr_port}"]="${proc_info}"
    done <<< "${ss_output}"

    # === Check 1: Flag 0.0.0.0 binds (except allowed) ===
    local flagged_count=0
    for bind in "${!CURRENT_BINDS[@]}"; do
        local addr="${bind%:*}"
        local port="${bind##*:}"
        local proc="${CURRENT_PROCS[${bind}]:-unknown}"

        if [[ "${addr}" == "0.0.0.0" ]]; then
            if ! is_allowed_0_0_0_0 "${proc}" "${port}"; then
                alert "HIGH" "0.0.0.0 bind detected: ${bind} (process: ${proc})"
                ((flagged_count++))
            fi
        fi
    done

    # === Check 2: New listeners not in baseline ===
    local new_count=0
    for bind in "${!CURRENT_BINDS[@]}"; do
        # Skip ephemeral/internal system binds
        local port="${bind##*:}"
        local addr="${bind%:*}"

        # Skip tailscale dynamic ports
        if [[ "${addr}" == "100."*".28" && "${port}" -gt 32768 ]]; then
            continue
        fi

        if [[ ! -v BASELINE["${bind}"] ]]; then
            # Check if the port itself is in baseline with different IP
            local port_only="${bind##*:}"
            local matched=false
            for b in "${!BASELINE[@]}"; do
                if [[ "${b##*:}" == "${port_only}" ]]; then
                    matched=true
                    break
                fi
            done

            if ! ${matched}; then
                local proc="${CURRENT_PROCS[${bind}]:-unknown}"
                alert "WARN" "New listener not in baseline: ${bind} (process: ${proc})"
                ((new_count++))
            fi
        fi
    done

    # === Check 3: Expected listeners from baseline not currently listening ===
    local missing_count=0
    for bind in "${!BASELINE[@]}"; do
        # Skip comment lines and special entries
        local addr="${bind%:*}"
        local port="${bind##*:}"

        # Skip wildcard entries that are expected but not ss-visible
        if [[ "${addr}" == "0.0.0.0" ]]; then
            continue
        fi

        if [[ ! -v CURRENT_BINDS["${bind}"] ]]; then
            alert "WARN" "Missing expected listener: ${bind} (${BASELINE[${bind}]})"
            ((missing_count++))
        fi
    done

    # === Summary ===
    if [[ ${#ALERTS[@]} -eq 0 ]]; then
        echo "PASS: Port baseline matches current state (${#CURRENT_BINDS[@]} listeners checked)"
    else
        echo "ISSUES: ${flagged_count} 0.0.0.0 binds, ${new_count} new listeners, ${missing_count} missing listeners" >&2
    fi

    [[ "${flagged_count}" -eq 0 && "${new_count}" -eq 0 && "${missing_count}" -eq 0 ]]
}

main "$@"
