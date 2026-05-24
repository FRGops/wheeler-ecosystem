#!/usr/bin/env bash
# =============================================================================
# Security Scorecard — Both Servers (Hetzner & Hostinger)
# =============================================================================
#
# Runs the comprehensive audit (audit-existing.sh) and produces a scored
# security report from 0-100. Designed for:
#   - CI/CD pipeline integration (non-zero exit on low score)
#   - Weekly security reviews
#   - Post-configuration validation
#   - Compliance reporting
#
# Scoring breakdown:
#   Firewall (UFW):        20 points
#   SSH Hardening:         15 points
#   Docker Security:       20 points
#   Fail2ban/CrowdSec:     15 points
#   Kernel Hardening:      15 points
#   Container Security:    15 points
#   ─────────────────────
#   Total:                100 points
#
# Grade thresholds:
#   A+ (90-100): Excellent — fully hardened
#   A  (80-89):  Good — minor improvements
#   B  (70-79):  Adequate — improvements recommended
#   C  (60-69):  Below average — action required
#   F  (0-59):   Critical — immediate action needed
#
# Usage:
#   sudo ./security-scorecard.sh              # Full scorecard with report
#   sudo ./security-scorecard.sh --json        # JSON output (for CI)
#   sudo ./security-scorecard.sh --passing=70  # Exit 1 if score < 70
#   sudo ./security-scorecard.sh --email       # Send report via email
#   sudo ./security-scorecard.sh --ci          # CI mode (JSON + non-zero if < 80)
#
# Idempotent: YES (read-only — runs audit, does not modify anything)
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

OUTPUT_MODE="standard"
PASSING_THRESHOLD=0  # Default: don't fail
CI_MODE=false
SEND_EMAIL=false
EMAIL_RECIPIENT="${SCORE_EMAIL:-root@localhost}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_SCRIPT="${SCRIPT_DIR}/audit-existing.sh"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

usage() {
    cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --passing=N   Exit with code 1 if score is below N (default: no threshold)
  --json        Output in JSON format
  --email       Send scorecard report via email
  --ci          CI mode (JSON output + exit 1 if score < 80)
  --help        Show this help message

Examples:
  sudo $0                     # Full scorecard
  sudo $0 --json              # JSON output
  sudo $0 --passing=70        # Fail if score < 70
  sudo $0 --ci                # CI pipeline check (threshold: 80)
USAGE
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

parse_args() {
    for arg in "$@"; do
        case "${arg}" in
            --passing=*)
                PASSING_THRESHOLD="${arg#*=}"
                if ! [ "${PASSING_THRESHOLD}" -ge 0 -a "${PASSING_THRESHOLD}" -le 100 ] 2>/dev/null; then
                    error "Invalid passing threshold: ${PASSING_THRESHOLD} (must be 0-100)"
                fi
                ;;
            --json)
                OUTPUT_MODE="json"
                ;;
            --email)
                SEND_EMAIL=true
                ;;
            --ci)
                CI_MODE=true
                OUTPUT_MODE="json"
                PASSING_THRESHOLD=80
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                warn "Unknown option: ${arg}"
                usage
                exit 1
                ;;
        esac
    done
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN SCORECARD
# ═════════════════════════════════════════════════════════════════════════════

run_scorecard() {
    local audit_args=""

    if [ "${OUTPUT_MODE}" = "json" ]; then
        audit_args="--json"
    else
        audit_args="--quiet"
    fi

    # Run the audit script and capture output
    if [ ! -f "${AUDIT_SCRIPT}" ]; then
        error "Audit script not found: ${AUDIT_SCRIPT}"
    fi

    if [ ! -x "${AUDIT_SCRIPT}" ]; then
        chmod +x "${AUDIT_SCRIPT}"
    fi

    info "Running security audit..."
    local audit_output
    audit_output=$("${AUDIT_SCRIPT}" ${audit_args} 2>&1)
    local audit_exit=$?

    if [ "${audit_exit}" -ne 0 ]; then
        warn "Audit script exited with code ${audit_exit}"
        echo "${audit_output}"
    fi

    # Parse scores from audit output
    local firewall_score=0 ssh_score=0 docker_score=0 fail2ban_score=0 kernel_score=0 container_score=0

    if [ "${OUTPUT_MODE}" = "json" ]; then
        # JSON output — parse with python3
        local json_data
        json_data=$(echo "${audit_output}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['scores']['firewall']['score'])
    print(data['scores']['ssh']['score'])
    print(data['scores']['docker']['score'])
    print(data['scores']['fail2ban_crowdsec']['score'])
    print(data['scores']['kernel']['score'])
    print(data['scores']['containers']['score'])
    print(data['total_score'])
except (json.JSONDecodeError, KeyError) as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>/dev/null || true)

        local scores
        IFS=$'\n' read -r -d '' -a scores <<< "${json_data}" || true
        if [ "${#scores[@]}" -ge 7 ]; then
            firewall_score="${scores[0]}"
            ssh_score="${scores[1]}"
            docker_score="${scores[2]}"
            fail2ban_score="${scores[3]}"
            kernel_score="${scores[4]}"
            container_score="${scores[5]}"
            total_score="${scores[6]}"
        else
            warn "Failed to parse JSON scores. Audit output:"
            echo "${audit_output}"
            return 1
        fi
    else
        # Parse scores from quiet mode output
        firewall_score=$(echo "${audit_output}" | grep "^FIREWALL_SCORE=" | cut -d= -f2)
        ssh_score=$(echo "${audit_output}" | grep "^SSH_SCORE=" | cut -d= -f2)
        docker_score=$(echo "${audit_output}" | grep "^DOCKER_SCORE=" | cut -d= -f2)
        fail2ban_score=$(echo "${audit_output}" | grep "^FAIL2BAN_SCORE=" | cut -d= -f2)
        kernel_score=$(echo "${audit_output}" | grep "^KERNEL_SCORE=" | cut -d= -f2)
        container_score=$(echo "${audit_output}" | grep "^CONTAINER_SCORE=" | cut -d= -f2)

        # Provide defaults if parsing failed
        firewall_score="${firewall_score:-0}"
        ssh_score="${ssh_score:-0}"
        docker_score="${docker_score:-0}"
        fail2ban_score="${fail2ban_score:-0}"
        kernel_score="${kernel_score:-0}"
        container_score="${container_score:-0}"
        total_score=$((firewall_score + ssh_score + docker_score + fail2ban_score + kernel_score + container_score))
    fi

    # ─── Display Scorecard ───────────────────────────────────────────

    if [ "${OUTPUT_MODE}" != "json" ]; then
        display_scorecard "${firewall_score}" "${ssh_score}" "${docker_score}" \
            "${fail2ban_score}" "${kernel_score}" "${container_score}" "${total_score}"
    else
        # Output JSON
        python3 -c "
import json
print(json.dumps({
    'hostname': '$(hostname)',
    'date': '$(date -Iseconds)',
    'server_role': '$(hostname | grep -qi 'hetzner' && echo 'hetzner' || echo 'hostinger')',
    'scores': {
        'firewall': {'score': ${firewall_score}, 'max': 20},
        'ssh': {'score': ${ssh_score}, 'max': 15},
        'docker': {'score': ${docker_score}, 'max': 20},
        'fail2ban_crowdsec': {'score': ${fail2ban_score}, 'max': 15},
        'kernel': {'score': ${kernel_score}, 'max': 15},
        'containers': {'score': ${container_score}, 'max': 15}
    },
    'total_score': ${total_score},
    'max_score': 100,
    'grade': '$(grade ${total_score})',
    'passed': ${PASSING_THRESHOLD} == 0 || ${total_score} >= ${PASSING_THRESHOLD}
}, indent=2))
"
    fi

    # ─── Email Report (Optional) ─────────────────────────────────────
    if [ "${SEND_EMAIL}" = "true" ]; then
        send_email "${firewall_score}" "${ssh_score}" "${docker_score}" \
            "${fail2ban_score}" "${kernel_score}" "${container_score}" "${total_score}"
    fi

    # ─── Threshold Check ─────────────────────────────────────────────
    if [ "${PASSING_THRESHOLD}" -gt 0 ] && [ "${total_score}" -lt "${PASSING_THRESHOLD}" ]; then
        warn ""
        warn "════════════════════════════════════════════════════════"
        warn "  SECURITY SCORECARD FAILED"
        warn "  Score: ${total_score}/100 — below threshold: ${PASSING_THRESHOLD}"
        warn "  Host: $(hostname)"
        warn "  Action: Review and fix security issues immediately."
        warn "════════════════════════════════════════════════════════"
        return 1
    fi

    return 0
}

# ─── Display ─────────────────────────────────────────────────────────────────

grade() {
    local score="$1"
    if [ "${score}" -ge 90 ]; then echo "A+"
    elif [ "${score}" -ge 80 ]; then echo "A"
    elif [ "${score}" -ge 70 ]; then echo "B"
    elif [ "${score}" -ge 60 ]; then echo "C"
    else echo "F"
    fi
}

display_scorecard() {
    local firewall="$1" ssh="$2" docker="$3" fail2ban="$4" kernel="$5" containers="$6" total="$7"
    local grade_str
    grade_str=$(grade "${total}")

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    printf "║  %-56s ║\n" "WHEELER AIOPS SECURITY SCORECARD"
    printf "║  %-56s ║\n" "$(hostname)"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  %-42s %5s/%-5s ║\n" "Firewall (UFW)" "${firewall}" "20"
    printf "║  %-42s %5s/%-5s ║\n" "SSH Hardening" "${ssh}" "15"
    printf "║  %-42s %5s/%-5s ║\n" "Docker Security" "${docker}" "20"
    printf "║  %-42s %5s/%-5s ║\n" "Fail2ban / CrowdSec" "${fail2ban}" "15"
    printf "║  %-42s %5s/%-5s ║\n" "Kernel Hardening" "${kernel}" "15"
    printf "║  %-42s %5s/%-5s ║\n" "Container Security" "${containers}" "15"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  %-42s %5s/%-5s ║\n" "TOTAL" "${total}" "100"
    printf "║  %-42s %9s    ║\n" "GRADE" "${grade_str}"
    echo "╚══════════════════════════════════════════════════════════════╝"

    # Guidance based on score
    echo ""
    if [ "${total}" -ge 90 ]; then
        echo "  STATUS: EXCELLENT — Your server is well-hardened."
        echo "  Continue monitoring: run this scorecard weekly."
    elif [ "${total}" -ge 80 ]; then
        echo "  STATUS: GOOD — Minor improvements recommended."
        echo "  Run the hardening scripts for any low-scoring categories."
    elif [ "${total}" -ge 70 ]; then
        echo "  STATUS: ADEQUATE — Several improvements needed."
        echo "  Prioritize: run security/*.sh scripts for low scores."
    elif [ "${total}" -ge 60 ]; then
        echo "  STATUS: BELOW AVERAGE — Action required."
        echo "  IMMEDIATE: Run all security/*.sh hardening scripts."
    else
        echo "  STATUS: CRITICAL — Immediate action required!"
        echo "  IMMEDIATE: Run ALL security/*.sh hardening scripts NOW."
    fi

    # Specific recommendations
    local recommendations=""
    [ "${firewall}" -lt 15 ] && recommendations="${recommendations}  - Run: ufw-hetzner.sh or ufw-hostinger.sh\n"
    [ "${ssh}" -lt 10 ] && recommendations="${recommendations}  - Run: ssh-hardening.sh\n"
    [ "${docker}" -lt 15 ] && recommendations="${recommendations}  - Run: docker-security.sh\n"
    [ "${fail2ban}" -lt 10 ] && recommendations="${recommendations}  - Run: fail2ban-*.sh or crowdsec-install.sh\n"
    [ "${kernel}" -lt 10 ] && recommendations="${recommendations}  - Apply: sysctl-hardening.conf\n"
    [ "${containers}" -lt 10 ] && recommendations="${recommendations}  - Review: container security audit above\n"

    if [ -n "${recommendations}" ]; then
        echo ""
        echo "  RECOMMENDED ACTIONS:"
        printf "%s" "${recommendations}"
    fi
}

# ─── Email ───────────────────────────────────────────────────────────────────

send_email() {
    local firewall="$1" ssh="$2" docker="$3" fail2ban="$4" kernel="$5" containers="$6" total="$7"

    if ! command -v mail >/dev/null 2>&1; then
        warn "mail command not found. Install: apt-get install mailutils"
        warn "Skipping email notification."
        return
    }

    local subject="Security Scorecard — $(hostname) — ${total}/100 — $(grade ${total})"

    {
        echo "Security Scorecard for $(hostname)"
        echo "Date: $(date)"
        echo ""
        echo "Firewall:             ${firewall}/20"
        echo "SSH Hardening:        ${ssh}/15"
        echo "Docker Security:      ${docker}/20"
        echo "Fail2ban/CrowdSec:    ${fail2ban}/15"
        echo "Kernel Hardening:     ${kernel}/15"
        echo "Container Security:   ${containers}/15"
        echo "───────────────────────────────"
        echo "TOTAL:                ${total}/100"
        echo "GRADE:                $(grade ${total})"
        echo ""
        echo "Run full audit: sudo ${AUDIT_SCRIPT}"
    } | mail -s "${subject}" "${EMAIL_RECIPIENT}"

    info "Scorecard emailed to ${EMAIL_RECIPIENT}"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    parse_args "$@"

    info "Wheeler AIOps Security Scorecard"
    info "Server: $(hostname)"
    info "Date:   $(date)"
    info ""

    # Run the scorecard
    if run_scorecard; then
        local total_score=0
        # We get the total score from the function output, but since it's
        # captured in the function, just rely on the exit code for the threshold
        info ""
        info "Scorecard completed successfully."
        exit 0
    else
        info ""
        warn "Scorecard FAILED (below threshold of ${PASSING_THRESHOLD})."
        exit 1
    fi
}

main "$@"
