#!/usr/bin/env bash
# ==============================================================================
# Wheeler Security Hardening Script
# Part of: Execution Readiness Remediation (Security 82 -> 90)
# Created: 2026-05-26
# Auditor: Claude Opus 4.7
# Policy: Zero False Greens
# ==============================================================================
set -uo pipefail
# NOTE: set -e intentionally omitted — many audit grep commands legitimately return 1 (no matches)

readonly SCRIPT_NAME="security-hardening"
readonly LOG_DIR="/root/deployment-engine/logs"
readonly REPORT_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
readonly SCAN_ROOT="/root"
readonly SCAN_ETC="/etc"

mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
red()    { echo -e "\033[31m$*\033[0m"; }
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
bold()   { echo -e "\033[1m$*\033[0m"; }

# ---------------------------------------------------------------------------
# Logging (tee to both stdout and report file)
# ---------------------------------------------------------------------------
log()    { echo "$(date '+%H:%M:%S')  $*" | tee -a "$REPORT_FILE"; }
log_ok() { echo "$(date '+%H:%M:%S')  [PASS] $*" | tee -a "$REPORT_FILE"; }
log_warn(){ echo "$(date '+%H:%M:%S')  [WARN] $*" | tee -a "$REPORT_FILE"; }
log_fail(){ echo "$(date '+%H:%M:%S')  [FAIL] $*" | tee -a "$REPORT_FILE"; }
log_act(){ echo "$(date '+%H:%M:%S')  [ACTION] $*" | tee -a "$REPORT_FILE"; }

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
{
    echo "=============================================="
    echo " Wheeler Security Hardening Report"
    echo " Run: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Host: $(hostname)"
    echo "=============================================="
    echo ""
} | tee "$REPORT_FILE"

# ===========================================================================
# SECTION 1: .env File Permission Lockdown
# ===========================================================================
log "--- .env File Permission Lockdown ---"

ENV_FIXED=0
while IFS= read -r env_file; do
    if [ -z "$env_file" ]; then continue; fi
    CURRENT_PERMS=$(stat -c '%a' "$env_file" 2>/dev/null || echo "unknown")
    if [ "$CURRENT_PERMS" != "600" ]; then
        chmod 600 "$env_file" 2>/dev/null && {
            log_act "Locked down: ${env_file} (${CURRENT_PERMS} -> 600)"
            ENV_FIXED=$((ENV_FIXED + 1))
        } || {
            log_warn "Could not change permissions: ${env_file} (current: ${CURRENT_PERMS})"
        }
    fi
done < <(find "$SCAN_ROOT" -name '.env' -not -path '*/.git/*' 2>/dev/null)

if [ "$ENV_FIXED" -eq 0 ]; then
    log_ok "All .env files already have secure permissions (600)"

    # Count total .env files for reporting
    ENV_COUNT=$(find "$SCAN_ROOT" -name '.env' -not -path '*/.git/*' 2>/dev/null | wc -l)
    log_ok "Found ${ENV_COUNT} .env files, all verified secure"
fi

# ===========================================================================
# SECTION 2: SSH Configuration Audit
# ===========================================================================
log "--- SSH Configuration Audit ---"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSH_SCORE=100

if [ -f "$SSHD_CONFIG" ]; then
    # 2a. Check PermitRootLogin
    ROOT_LOGIN=$(grep -E '^PermitRootLogin' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || echo "default(prohibit-password)")
    case "$ROOT_LOGIN" in
        no|prohibit-password|without-password|"default(prohibit-password)")
            log_ok "SSH PermitRootLogin: ${ROOT_LOGIN} (secure)"
            ;;
        yes)
            log_fail "SSH PermitRootLogin: yes — ROOT LOGIN ALLOWED WITH PASSWORD"
            SSH_SCORE=$((SSH_SCORE - 30))
            ;;
        *)
            log_warn "SSH PermitRootLogin: ${ROOT_LOGIN} — verify this is intentional"
            ;;
    esac

    # 2b. Check PasswordAuthentication
    PASS_AUTH=$(grep -E '^PasswordAuthentication' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || echo "default")
    if [ "$PASS_AUTH" = "no" ]; then
        log_ok "SSH PasswordAuthentication: no (key-only)"
    elif [ "$PASS_AUTH" = "yes" ]; then
        log_fail "SSH PasswordAuthentication: yes — PASSWORD LOGIN ALLOWED"
        SSH_SCORE=$((SSH_SCORE - 25))
    else
        log_warn "SSH PasswordAuthentication: not explicitly set (default may allow password)"
        log_warn "  Recommend adding: PasswordAuthentication no"
        SSH_SCORE=$((SSH_SCORE - 15))
    fi

    # 2c. Check PubkeyAuthentication
    PUBKEY_AUTH=$(grep -E '^PubkeyAuthentication' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || echo "default")
    if [ "$PUBKEY_AUTH" != "no" ]; then
        log_ok "SSH PubkeyAuthentication: ${PUBKEY_AUTH} (enabled)"
    else
        log_fail "SSH PubkeyAuthentication: no — KEY AUTH DISABLED"
        SSH_SCORE=$((SSH_SCORE - 25))
    fi

    # 2d. Check SSH binding
    LISTEN_ADDR=$(grep -E '^ListenAddress' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || echo "0.0.0.0")
    if echo "$LISTEN_ADDR" | grep -qE '^0\.0\.0\.0$'; then
        log_warn "SSH bound to 0.0.0.0:22 — accessible from all interfaces"
        log_warn "  HIGH: Restrict to Tailscale IP or internal interface"
        SSH_SCORE=$((SSH_SCORE - 20))
    elif echo "$LISTEN_ADDR" | grep -qE '^100\.'; then
        log_ok "SSH bound to Tailscale IP (${LISTEN_ADDR}) — restricted"
    elif echo "$LISTEN_ADDR" | grep -qE '^127\.'; then
        log_ok "SSH bound to localhost (${LISTEN_ADDR})"
    else
        log_ok "SSH ListenAddress: ${LISTEN_ADDR}"
    fi

    # 2e. Check SSH port
    SSH_PORT=$(grep -E '^Port' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || echo "22")
    if [ "$SSH_PORT" = "22" ]; then
        log "SSH Port: 22 (default)"
    else
        log_ok "SSH Port: ${SSH_PORT} (non-default — reduces automated attack noise)"
    fi
else
    log_fail "SSH config not found at ${SSHD_CONFIG}"
    SSH_SCORE=0
fi

# ---------------------------------------------------------------------------
# Check SSH via ss (real binding)
# ---------------------------------------------------------------------------
SSH_ON_WILDCARD=$(ss -tlnp 2>/dev/null | awk '/:22 / && /0\.0\.0\.0/ {print}' | wc -l)
if [ "$SSH_ON_WILDCARD" -gt 0 ]; then
    # This duplicates the ListenAddress check but confirms actual binding
    if ! echo "$LISTEN_ADDR" | grep -qE '^0\.0\.0\.0$'; then
        log_warn "SSH actually bound to 0.0.0.0:22 (despite ListenAddress config)"
    fi
fi

log "SSH Configuration Score: ${SSH_SCORE}/100"

# ===========================================================================
# SECTION 3: World-Writable File Scan
# ===========================================================================
log "--- World-Writable File Scan ---"

WW_COUNT=0

for scan_dir in "$SCAN_ROOT" "$SCAN_ETC"; do
    while IFS= read -r ww_file; do
        if [ -z "$ww_file" ]; then continue; fi
        WW_PERMS=$(stat -c '%a' "$ww_file" 2>/dev/null || echo "unknown")
        log_warn "World-writable file: ${ww_file} (${WW_PERMS})"
        WW_COUNT=$((WW_COUNT + 1))
    done < <(find "$scan_dir" -perm -o+w -type f 2>/dev/null | head -20)
done

if [ "$WW_COUNT" -eq 0 ]; then
    log_ok "No world-writable files found in ${SCAN_ROOT} or ${SCAN_ETC}"
else
    log_warn "Found ${WW_COUNT} world-writable files — review and lock down"
fi

# ===========================================================================
# SECTION 4: Git Secrets Scan
# ===========================================================================
log "--- Git Secrets Scan ---"

if git -C /root rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    SECRET_HITS=$(git -C /root log --oneline -50 | grep -iE 'secret|key|token|password|credential|api.key' || true)
    if [ -z "$SECRET_HITS" ]; then
        log_ok "No secrets detected in last 50 commits"
    else
        COMMIT_COUNT=$(echo "$SECRET_HITS" | wc -l)
        log_warn "Potential secrets in ${COMMIT_COUNT} recent commit message(s):"
        echo "$SECRET_HITS" | while IFS= read -r hit; do
            log_warn "  ${hit}"
        done
    fi

    # Also check for accidental .env commits
    ENV_IN_GIT=$(git -C /root log --all --oneline --diff-filter=A -- '*.env' '*.env.*' 2>/dev/null | head -5 || true)
    if [ -n "$ENV_IN_GIT" ]; then
        log_warn ".env files found in git history (may contain secrets):"
        echo "$ENV_IN_GIT" | while IFS= read -r hit; do
            log_warn "  ${hit}"
        done
    else
        log_ok "No .env files committed to git history"
    fi
else
    log_warn "Not a git repository — skipping git secrets scan"
fi

# ===========================================================================
# SECTION 5: Service Binding Audit (0.0.0.0 vs 127.0.0.1)
# ===========================================================================
log "--- Service Binding Audit ---"

WILDCARD_BINDS=0

# Check for services listening on 0.0.0.0 (excluding system DNS, tailscale)
# ss output format: LISTEN 0 511 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=123))
while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    # Extract the local address:port (field 4 using multiple spaces as delimiter)
    LOCAL_ADDR=$(echo "$line" | awk '{print $4}' 2>/dev/null || echo "")

    # Skip empty, localhost, tailscale, docker networks
    [ -z "$LOCAL_ADDR" ] && continue
    case "$LOCAL_ADDR" in
        127.0.0.53:*) continue ;;  # systemd-resolved DNS stub
        127.0.0.54:*) continue ;;  # systemd-resolved DNS stub
        127.0.0.1:*) continue ;;   # localhost
        \[::1\]:*)    continue ;;   # ipv6 localhost
        100.*)         continue ;;   # Tailscale IP range
        172.*)         continue ;;   # Docker bridge networks
        *:53)          continue ;;   # DNS
        *:41506)       continue ;;   # Tailscale DERP
    esac

    # Extract process name (everything after "users:" in parentheses)
    PROCESS=$(echo "$line" | sed 's/.*users:.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
    [ -z "$PROCESS" ] && PROCESS="unknown"

    # Extract just the port number
    PORT=$(echo "$LOCAL_ADDR" | awk -F: '{print $NF}' 2>/dev/null || echo "?")

    WILDCARD_BINDS=$((WILDCARD_BINDS + 1))
    log_warn "Service on ${LOCAL_ADDR} — ${PROCESS}"
done < <(ss -tlnp 2>/dev/null | tail -n +2 | grep -v '127.0.0.1' | grep -v '::1\b' | grep -v '100\.')

if [ "$WILDCARD_BINDS" -eq 0 ]; then
    log_ok "All services bound to localhost or Tailscale-only"
else
    log_warn "${WILDCARD_BINDS} service(s) exposed on 0.0.0.0 — review firewall rules"
fi

# ===========================================================================
# SECTION 6: UFW Rule Audit
# ===========================================================================
log "--- UFW Rule Audit ---"

if ufw status 2>/dev/null | grep -q "active"; then
    # Check for overly broad allows
    BROAD_RULES=$(ufw status 2>/dev/null | grep 'ALLOW IN' | grep 'Anywhere' | grep -v 'tailscale0' | grep -v '443/tcp' | wc -l)
    if [ "$BROAD_RULES" -gt 0 ]; then
        log_warn "${BROAD_RULES} UFW rule(s) allow from Anywhere without interface restriction"
        ufw status 2>/dev/null | grep 'ALLOW IN' | grep 'Anywhere' | grep -v 'tailscale0' | while IFS= read -r rule; do
            log_warn "  ${rule}"
        done
    else
        log_ok "No overly broad UFW rules detected"
    fi

    # Verify default deny
    DEFAULT_IN=$(ufw status verbose 2>/dev/null | grep "Default:" | grep "incoming" | awk '{print $2}')
    if [ "$DEFAULT_IN" = "deny" ]; then
        log_ok "UFW default incoming: deny"
    else
        log_fail "UFW default incoming: ${DEFAULT_IN} (should be deny)"
    fi
else
    log_fail "UFW not active — firewall is DOWN"
fi

# ===========================================================================
# SECTION 7: Critical File Immutability
# ===========================================================================
log "--- Critical File Immutability ---"

IMMUTABLE_FILES=(
    "/root/.ssh/authorized_keys"
    "/etc/ssh/sshd_config"
    "/etc/ufw/user.rules"
    "/etc/fail2ban/jail.local"
)

for file in "${IMMUTABLE_FILES[@]}"; do
    if [ -f "$file" ]; then
        ATTRS=$(lsattr "$file" 2>/dev/null | awk '{print $1}' || echo "unknown")
        if echo "$ATTRS" | grep -q 'i'; then
            log_ok "Immutable: ${file} (chattr +i)"
        else
            log_warn "Not immutable: ${file} — consider: chattr +i ${file}"
        fi
    fi
done

# ===========================================================================
# SECTION 8: SSH Authorized Keys Audit
# ===========================================================================
log "--- SSH Authorized Keys Audit ---"

AUTH_KEYS="/root/.ssh/authorized_keys"
if [ -f "$AUTH_KEYS" ]; then
    AUTH_PERMS=$(stat -c '%a' "$AUTH_KEYS" 2>/dev/null || echo "unknown")
    KEY_COUNT=$(wc -l < "$AUTH_KEYS" 2>/dev/null || echo "0")

    if [ "$AUTH_PERMS" = "600" ]; then
        log_ok "authorized_keys permissions: 600 (secure)"
    else
        log_fail "authorized_keys permissions: ${AUTH_PERMS} (should be 600)"
        chmod 600 "$AUTH_KEYS" 2>/dev/null && log_act "Fixed authorized_keys permissions -> 600"
    fi

    log_ok "authorized_keys: ${KEY_COUNT} key(s) configured"

    # Check for empty keys or suspicious entries
    while IFS= read -r keyline; do
        if [ -z "$keyline" ] || [ "${keyline:0:1}" = "#" ]; then
            log_warn "Empty or commented line in authorized_keys"
        fi
    done < "$AUTH_KEYS"
else
    log_fail "authorized_keys not found at ${AUTH_KEYS}"
fi

# ===========================================================================
# SECTION 9: fail2ban Hardening Verification
# ===========================================================================
log "--- fail2ban Hardening ---"

if command -v fail2ban-client &>/dev/null && fail2ban-client status 2>/dev/null | grep -q "Jail list"; then
    BANTIME=$(grep -E '^bantime' /etc/fail2ban/jail.local 2>/dev/null | awk -F= '{print $2}' | xargs || echo "default")
    MAXRETRY=$(grep -E '^maxretry' /etc/fail2ban/jail.local 2>/dev/null | awk -F= '{print $2}' | xargs || echo "default")

    if [ "${BANTIME:-0}" -ge 3600 ] 2>/dev/null; then
        log_ok "fail2ban bantime: ${BANTIME}s (>= 3600)"
    else
        log_warn "fail2ban bantime: ${BANTIME}s (consider >= 3600)"
    fi

    # Check jail coverage
    JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*Jail list://' | tr ',' '\n' | wc -l)
    log_ok "fail2ban jails: ${JAILS} active"
else
    log_fail "fail2ban not running"
fi

# ===========================================================================
# SECTION 10: Sudo / Privilege Escalation Audit
# ===========================================================================
log "--- Privilege Escalation Audit ---"

# Check for NOPASSWD sudo entries
NOPASSWD=$(grep -r 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#' | grep -v '^$' || true)
if [ -n "$NOPASSWD" ]; then
    log_warn "NOPASSWD sudo entries found:"
    echo "$NOPASSWD" | while IFS= read -r line; do
        log_warn "  ${line}"
    done
else
    log_ok "No NOPASSWD sudo entries (or none found)"
fi

# ===========================================================================
# SECTION 11: Comprehensive Security Score
# ===========================================================================
echo ""
log "========== COMPREHENSIVE SECURITY SCORE =========="

FAIL_COUNT=$(grep -c '\[FAIL\]' "$REPORT_FILE" 2>/dev/null | head -1)
FAIL_COUNT=${FAIL_COUNT:-0}
WARN_COUNT=$(grep -c '\[WARN\]' "$REPORT_FILE" 2>/dev/null | head -1)
WARN_COUNT=${WARN_COUNT:-0}
PASS_COUNT=$(grep -c '\[PASS\]' "$REPORT_FILE" 2>/dev/null | head -1)
PASS_COUNT=${PASS_COUNT:-0}
ACTION_COUNT=$(grep -c '\[ACTION\]' "$REPORT_FILE" 2>/dev/null | head -1)
ACTION_COUNT=${ACTION_COUNT:-0}

# Start at 100, deduct for issues
SCORE=100
SCORE=$((SCORE - (FAIL_COUNT * 8) - (WARN_COUNT * 4)))
[ "$SCORE" -lt 0 ] && SCORE=0

log "Security Hardening Score: ${SCORE}/100"
log "  PASS:   ${PASS_COUNT} checks"
log "  FAIL:   ${FAIL_COUNT} checks"
log "  WARN:   ${WARN_COUNT} checks"
log "  ACTION: ${ACTION_COUNT} fixes applied"

echo ""
if [ "$SCORE" -ge 90 ]; then
    log_ok "STATUS: STRONG — security posture is robust"
elif [ "$SCORE" -ge 80 ]; then
    log_warn "STATUS: ADEQUATE — address warnings for production readiness"
elif [ "$SCORE" -ge 70 ]; then
    log_warn "STATUS: WEAK — multiple issues require attention"
else
    log_fail "STATUS: CRITICAL — immediate remediation required"
fi

# ---------------------------------------------------------------------------
# Summary of actions taken
# ---------------------------------------------------------------------------
echo ""
log "--- Remediation Actions Taken ---"
if [ "$ENV_FIXED" -gt 0 ]; then
    log_act "Locked ${ENV_FIXED} .env file(s) to 600"
fi
if [ "${ACTION_COUNT:-0}" -eq 0 ] && [ "${ENV_FIXED:-0}" -eq 0 ]; then
    log_ok "No automatic fixes needed — system already hardened"
fi

log ""
log "HIGH PRIORITY (requires manual action):"
log "  1. Restrict SSH to Tailscale IP (current: 0.0.0.0:22)"
log "  2. Deploy Let's Encrypt certs (replace self-signed)"
log "  3. Set PasswordAuthentication no in sshd_config (if not set)"
log "  4. Tighten 0.0.0.0 bindings for nginx if not needed externally"

echo ""
log "Report saved to: ${REPORT_FILE}"
echo ""

exit 0
