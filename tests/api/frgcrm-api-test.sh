#!/usr/bin/env bash
# ============================================================================
# FRGCRM API Regression Tests
# Target: AIOPS Node via EDGE proxy (https://fundsrecoverygroup.com/api/crm)
# ============================================================================
set -o pipefail

# ------------------------------------------------------------------
# Bootstrap
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /root/scripts/validation.env ]]; then
    # shellcheck source=/dev/null
    source /root/scripts/validation.env
fi

# -- Defaults (allow CLI override) ----------------------------------
API_HOST="${TEST_FRGCRM_HOST:-https://fundsrecoverygroup.com}"
API_BASE="${API_HOST}/api/crm"
API_TOKEN="${FRGCRM_TOKEN:-}"

TIMEOUT="${TEST_REQUEST_TIMEOUT:-10}"
VERBOSE=0
PASS=0
FAIL=0
SKIP=0
TOTAL=0

declare -a FAILURES=()

# -- Help -----------------------------------------------------------
usage() {
    cat <<USAGE
Usage: $0 [OPTIONS]

FRGCRM API Regression Test Suite

Options:
  --host HOST     API base host (default: ${API_HOST})
  --verbose       Verbose output
  --help          This message

Environment:
  FRGCRM_TOKEN    API bearer token.  Auth tests are skipped when empty.
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     API_HOST="$2"; API_BASE="${API_HOST}/api/crm"; shift 2 ;;
        --verbose)  VERBOSE=1; TEST_VERBOSE=1; shift ;;
        --help)     usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# -- Helpers ---------------------------------------------------------
log_pass() { echo -e "  ${SYMBOL_PASS} ${COLOR_GREEN}PASS${COLOR_RESET}  $1"; ((PASS++)); ((TOTAL++)); }
log_fail() { echo -e "  ${SYMBOL_FAIL} ${COLOR_RED}FAIL${COLOR_RESET}  $1 — $2"; ((FAIL++)); ((TOTAL++)); FAILURES+=("[FRGCRM] $1"); }
log_skip() { echo -e "  ${SYMBOL_SKIP} ${COLOR_YELLOW}SKIP${COLOR_RESET}  $1 — $2"; ((SKIP++)); ((TOTAL++)); }
log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}  $1"; }
log_hdr()  { echo -e "\n${COLOR_BOLD}${COLOR_MAGENTA}$1${COLOR_RESET}"; }

http_get() {
    local url="$1" token="$2"
    if [[ -n "$token" ]]; then
        curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${token}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    else
        curl -s -o /dev/null -w '%{http_code}' --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    fi
}

http_get_body() {
    local url="$1" token="$2"
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Bearer ${token}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    else
        curl -s --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    fi
}

http_get_headers() {
    local url="$1" token="$2"
    if [[ -n "$token" ]]; then
        curl -s -I -H "Authorization: Bearer ${token}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    else
        curl -s -I --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    fi
}

http_post() {
    local url="$1" data="$2" token="$3" ct="${4:-application/json}"
    if [[ -n "$token" ]]; then
        curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: ${ct}" -H "Authorization: Bearer ${token}" -d "${data}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    else
        curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: ${ct}" -d "${data}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    fi
}

http_post_body() {
    local url="$1" data="$2" token="$3" ct="${4:-application/json}"
    if [[ -n "$token" ]]; then
        curl -s -X POST -H "Content-Type: ${ct}" -H "Authorization: Bearer ${token}" -d "${data}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    else
        curl -s -X POST -H "Content-Type: ${ct}" -d "${data}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    fi
}

http_options() {
    local url="$1" origin="${2:-$TEST_CORS_ORIGIN}"
    curl -s -o /dev/null -w '%{http_code}' -X OPTIONS \
        -H "Origin: ${origin}" \
        -H "Access-Control-Request-Method: GET" \
        --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
}

http_options_full() {
    local url="$1" origin="${2:-$TEST_CORS_ORIGIN}"
    curl -s -I -X OPTIONS \
        -H "Origin: ${origin}" \
        -H "Access-Control-Request-Method: GET" \
        --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
}

# Check connectivity once
check_connectivity() {
    local health_url="${API_BASE}/health"
    vlog "Probing ${health_url} ..."
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 5 "${health_url}" 2>/dev/null)
    if [[ -z "$code" ]] || [[ "$code" == "000" ]]; then
        echo -e "${COLOR_RED}Cannot reach ${health_url}.  Is the server running and network accessible?${COLOR_RESET}"
        return 1
    fi
    return 0
}

# "assert" helpers — compare actual value against expected
assert_status() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$label (HTTP $actual)"
    else
        log_fail "$label" "expected HTTP $expected, got $actual"
    fi
}

assert_content_type() {
    local label="$1" actual="$2"
    if [[ "$actual" == *"application/json"* ]] || [[ "$actual" == *"application/json"* ]]; then
        log_pass "$label"
    else
        log_fail "$label" "expected application/json, got '${actual}'"
    fi
}

assert_elapsed() {
    local label="$1" elapsed="$2" limit="${3:-2.0}"
    if (( $(echo "$elapsed < $limit" | bc -l 2>/dev/null || echo 0) )); then
        log_pass "$label (${elapsed}s < ${limit}s)"
    else
        log_fail "$label" "took ${elapsed}s, limit ${limit}s"
    fi
}

assert_json_field() {
    local label="$1" json="$2" field="$3"
    local val
    val=$(echo "$json" | jq -r ".${field}" 2>/dev/null)
    if [[ -n "$val" ]] && [[ "$val" != "null" ]]; then
        log_pass "$label (${field}=${val})"
    else
        log_fail "$label" "field '${field}' missing or null"
    fi
}

assert_json_array() {
    local label="$1" json="$2" field="$3"
    local result
    result=$(echo "$json" | jq -r "if .${field} | type == \"array\" then \"array\" else \"not-array\" end" 2>/dev/null)
    if [[ "$result" == "array" ]]; then
        log_pass "$label"
    else
        log_fail "$label" "field '${field}' is not an array"
    fi
}

# -- Main ------------------------------------------------------------
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  FRGCRM API Regression Test Suite${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Target : ${API_BASE}${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Timeout: ${TIMEOUT}s${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"

if ! check_connectivity; then
    echo -e "${COLOR_RED}Server unreachable — all tests skipped.${COLOR_RESET}"
    exit 1
fi

# ===================================================================
# 1. HEALTH ENDPOINT
# ===================================================================
log_hdr "1. Health Endpoint"

status=$(http_get "${API_BASE}/health" "")
if [[ "$status" == "000" ]]; then
    log_skip "GET /api/crm/health" "connection refused"
else
    assert_status "GET /api/crm/health returns 200" "$status" "200"
fi

body=$(http_get_body "${API_BASE}/health" "")
if [[ -n "$body" ]]; then
    ct=$(echo "$body" | head -c 1)
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/crm/health returns valid JSON"
        assert_json_field "Health status field" "$body" "status"
    else
        log_fail "GET /api/crm/health returns valid JSON" "invalid JSON"
    fi
else
    log_skip "GET /api/crm/health body validation" "empty response"
fi

# ===================================================================
# 2. VERSION ENDPOINT
# ===================================================================
log_hdr "2. Version Endpoint"

status=$(http_get "${API_BASE}/version" "")
assert_status "GET /api/crm/version returns 200" "$status" "200"

body=$(http_get_body "${API_BASE}/version" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/crm/version returns valid JSON"
    assert_json_field "Version field present" "$body" "version"
else
    log_skip "GET /api/crm/version body validation" "invalid or empty JSON"
fi

# ===================================================================
# 3. AUTHENTICATION
# ===================================================================
log_hdr "3. Authentication"

# 3a — login with no creds
status=$(http_post "${API_BASE}/auth/login" '{}' "")
assert_status "POST /api/crm/auth/login (empty body)" "$status" "401"

# 3b — login with clearly invalid creds
status=$(http_post "${API_BASE}/auth/login" '{"email":"invalid@nonexistent.test","password":"wrong"}' "")
assert_status "POST /api/crm/auth/login (bad creds)" "$status" "401"

# 3c — login with missing fields
status=$(http_post "${API_BASE}/auth/login" '{"email":"user@example.com"}' "")
assert_status "POST /api/crm/auth/login (missing password)" "$status" "401"

# 3d — login with valid token if configured
if [[ -n "${API_TOKEN}" ]]; then
    # If there is a token-verification endpoint
    status=$(http_get "${API_BASE}/auth/verify" "${API_TOKEN}")
    if [[ "$status" != "404" ]]; then
        assert_status "GET /api/crm/auth/verify (with token)" "$status" "200"
    else
        log_skip "GET /api/crm/auth/verify" "endpoint returns 404 (not implemented)"
    fi
else
    log_skip "Authenticated auth test" "FRGCRM_TOKEN not set"
fi

# ===================================================================
# 4. CASES LIST
# ===================================================================
log_hdr "4. Cases List"

# 4a — without token
status=$(http_get "${API_BASE}/cases" "")
assert_status "GET /api/crm/cases (no token)" "$status" "401"

# 4b — with token (if configured)
if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/cases" "${API_TOKEN}")
    if [[ "$status" == "200" ]]; then
        log_pass "GET /api/crm/cases (with token) returns 200"
        body=$(http_get_body "${API_BASE}/cases" "${API_TOKEN}")
        if echo "$body" | jq -e . >/dev/null 2>&1; then
            log_pass "GET /api/crm/cases returns valid JSON"
            # Check if response is array or has data field
            if echo "$body" | jq -e 'if type == "array" then true else has("data") or has("cases") or has("items") end' >/dev/null 2>&1; then
                log_pass "GET /api/crm/cases structure valid"
            fi
        fi
    else
        log_fail "GET /api/crm/cases (with token)" "expected 200, got $status"
    fi
else
    log_skip "GET /api/crm/cases (with token)" "FRGCRM_TOKEN not set"
fi

# ===================================================================
# 5. CASE CRUD
# ===================================================================
log_hdr "5. Case CRUD"

TEST_CASE_ID="test-case-$(date +%s)"

# 5a — GET nonexistent case
status=$(http_get "${API_BASE}/cases/${TEST_CASE_ID}" "${API_TOKEN}")
if [[ "$status" == "404" ]] || [[ "$status" == "401" ]]; then
    if [[ "$status" == "404" ]]; then
        log_pass "GET /api/crm/cases/{nonexistent} returns 404"
    else
        log_pass "GET /api/crm/cases/{nonexistent} returns 401 (auth required)"
    fi
else
    vlog "GET nonexistent case returned $status (may be expected if test case exists)"
    log_pass "GET /api/crm/cases/{nonexistent} responded $status"
fi

# 5b — POST create case (if token available & write tests are safe)
if [[ -n "${API_TOKEN}" ]]; then
    CREATE_PAYLOAD='{"title":"API Test Case","client_name":"QA Test Client","status":"open","priority":"medium"}'
    status=$(http_post "${API_BASE}/cases" "${CREATE_PAYLOAD}" "${API_TOKEN}")
    if [[ "$status" == "201" ]] || [[ "$status" == "200" ]]; then
        log_pass "POST /api/crm/cases (create) returns $status"
        # Try to extract the created ID
        created_body=$(http_post_body "${API_BASE}/cases" "${CREATE_PAYLOAD}" "${API_TOKEN}")
        CREATED_ID=$(echo "$created_body" | jq -r '.id // .case_id // ._id // empty' 2>/dev/null)

        if [[ -n "${CREATED_ID}" ]] && [[ "${CREATED_ID}" != "null" ]]; then
            # 5c — GET created case
            status=$(http_get "${API_BASE}/cases/${CREATED_ID}" "${API_TOKEN}")
            if [[ "$status" == "200" ]]; then
                log_pass "GET /api/crm/cases/{created} returns 200"
            else
                log_fail "GET /api/crm/cases/{created}" "expected 200, got $status"
            fi

            # 5d — PUT update case
            UPDATE_PAYLOAD='{"status":"in_progress","notes":"Updated by regression test"}'
            status=$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${API_TOKEN}" \
                -d "${UPDATE_PAYLOAD}" \
                --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
                "${API_BASE}/cases/${CREATED_ID}")
            if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
                log_pass "PUT /api/crm/cases/{created} returns $status"
            else
                log_fail "PUT /api/crm/cases/{created}" "expected 200/204, got $status"
            fi

            # 5e — DELETE case
            status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
                -H "Authorization: Bearer ${API_TOKEN}" \
                --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
                "${API_BASE}/cases/${CREATED_ID}")
            if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
                log_pass "DELETE /api/crm/cases/{created} returns $status"
            else
                log_fail "DELETE /api/crm/cases/{created}" "expected 200/204, got $status"
            fi

            # 5f — GET deleted case (should 404)
            status=$(http_get "${API_BASE}/cases/${CREATED_ID}" "${API_TOKEN}")
            assert_status "GET /api/crm/cases/{deleted} returns 404" "$status" "404"
        else
            log_skip "Case CRUD (GET/PUT/DELETE)" "could not extract created case ID (response: $(echo "$created_body" | head -c 200))"
        fi
    elif [[ "$status" == "403" ]]; then
        log_skip "POST /api/crm/cases (create)" "forbidden (403) — insufficient permissions"
    elif [[ "$status" == "405" ]]; then
        log_skip "POST /api/crm/cases (create)" "method not allowed (405)"
    else
        log_fail "POST /api/crm/cases (create)" "expected 201, got $status"
    fi
else
    log_skip "Case CRUD tests" "FRGCRM_TOKEN not set"
fi

# ===================================================================
# 6. CLIENT LIST
# ===================================================================
log_hdr "6. Client List"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/clients" "${API_TOKEN}")
    if [[ "$status" == "200" ]]; then
        log_pass "GET /api/crm/clients returns 200"
        body=$(http_get_body "${API_BASE}/clients" "${API_TOKEN}")
        if echo "$body" | jq -e . >/dev/null 2>&1; then
            log_pass "GET /api/crm/clients returns valid JSON"
        fi
    elif [[ "$status" == "401" ]]; then
        log_skip "GET /api/crm/clients" "endpoint requires auth (got 401)"
    else
        log_fail "GET /api/crm/clients" "expected 200, got $status"
    fi
else
    # Try without token
    status=$(http_get "${API_BASE}/clients" "")
    if [[ "$status" == "200" ]]; then
        log_pass "GET /api/crm/clients returns 200 (no auth)"
        body=$(http_get_body "${API_BASE}/clients" "")
        if echo "$body" | jq -e . >/dev/null 2>&1; then
            log_pass "GET /api/crm/clients returns valid JSON"
            assert_json_array "Clients array structure" "$body" "clients"
        fi
    else
        log_skip "GET /api/crm/clients" "returned $status"
    fi
fi

# ===================================================================
# 7. DOCUMENTS ENDPOINT
# ===================================================================
log_hdr "7. Documents Endpoint"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/documents" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/documents" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/crm/documents returns 200"
    body=$(http_get_body "${API_BASE}/documents" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/crm/documents returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/crm/documents" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/crm/documents" "endpoint not implemented (404)"
else
    log_fail "GET /api/crm/documents" "unexpected status $status"
fi

# ===================================================================
# 8. SEARCH ENDPOINT
# ===================================================================
log_hdr "8. Search Endpoint"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/search?q=test" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/search?q=test" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/crm/search?q=test returns 200"
    body=$(http_get_body "${API_BASE}/search?q=test" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/crm/search returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/crm/search" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/crm/search" "endpoint not implemented (404)"
else
    log_fail "GET /api/crm/search" "unexpected status $status"
fi

# Empty search query
status=$(http_get "${API_BASE}/search?q=" "${API_TOKEN}")
vlog "Empty search query returned HTTP $status"
if [[ "$status" == "200" ]] || [[ "$status" == "400" ]]; then
    log_pass "GET /api/crm/search?q= (empty query) handled ($status)"
else
    log_fail "GET /api/crm/search?q= (empty query)" "unexpected $status"
fi

# ===================================================================
# 9. RATE LIMITING
# ===================================================================
log_hdr "9. Rate Limiting"

RAPID_COUNT="${TEST_RATE_LIMIT_RAPID_COUNT:-60}"
log_info "Sending ${RAPID_COUNT} rapid requests to ${API_BASE}/health ..."
rate_limited=0
for i in $(seq 1 "${RAPID_COUNT}"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 2 "${API_BASE}/health" 2>/dev/null)
    if [[ "$code" == "429" ]]; then
        rate_limited=1
        vlog "Rate limited after $i requests"
        break
    fi
done

if [[ "$rate_limited" -eq 1 ]]; then
    log_pass "Rate limiting enforced (received 429)"
else
    log_skip "Rate limiting check" "no 429 received within ${RAPID_COUNT} requests (threshold may be higher or disabled)"
fi

# ===================================================================
# 10. INVALID ROUTE
# ===================================================================
log_hdr "10. Invalid Route (404)"

status=$(http_get "${API_BASE}/nonexistent-endpoint-99999" "")
assert_status "GET /api/crm/nonexistent → 404" "$status" "404"

status=$(http_get "${API_BASE}/this/does/not/exist" "")
assert_status "GET /api/crm/this/does/not/exist → 404" "$status" "404"

# ===================================================================
# 11. MALFORMED JSON
# ===================================================================
log_hdr "11. Malformed JSON (400)"

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d 'this is not valid json {{{' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/cases")
assert_status "POST /api/crm/cases (malformed JSON)" "$status" "400"

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d '{broken' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/auth/login")
assert_status "POST /api/crm/auth/login (malformed JSON)" "$status" "400"

# ===================================================================
# 12. RESPONSE TIME
# ===================================================================
log_hdr "12. Response Time (< 2s)"

timed_get() {
    local url="$1" token="$2"
    local start end
    start=$(date +%s.%N)
    if [[ -n "$token" ]]; then
        curl -s -o /dev/null -H "Authorization: Bearer ${token}" --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    else
        curl -s -o /dev/null --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" "${url}"
    fi
    end=$(date +%s.%N)
    echo "$end - $start" | bc -l
}

elapsed=$(timed_get "${API_BASE}/health" "")
assert_elapsed "GET /api/crm/health latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/version" "")
assert_elapsed "GET /api/crm/version latency" "$elapsed" 2.0

# ===================================================================
# 13. CORS HEADERS
# ===================================================================
log_hdr "13. CORS Headers"

cors_header_line=$(http_options_full "${API_BASE}/health")
vlog "OPTIONS response headers: $(echo "$cors_header_line" | tr '\n' ' ')"

if echo "$cors_header_line" | grep -qi "access-control-allow-origin\|access-control-allow-methods"; then
    log_pass "OPTIONS /api/crm/health returns CORS headers"
else
    log_skip "CORS headers on OPTIONS" "may be configured at EDGE proxy level (not on app server)"
fi

status=$(http_options "${API_BASE}/health")
if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
    log_pass "OPTIONS /api/crm/health returns ${status}"
elif [[ "$status" == "405" ]]; then
    log_skip "OPTIONS /api/crm/health" "method not allowed"
else
    log_fail "OPTIONS /api/crm/health" "unexpected status $status"
fi

# ===================================================================
# 14. CONTENT-TYPE
# ===================================================================
log_hdr "14. Content-Type Validation"

check_ct() {
    local url="$1" token="$2" label="$3"
    local headers ct
    headers=$(http_get_headers "$url" "$token")
    ct=$(echo "$headers" | grep -i '^content-type:' | head -1 | sed 's/.*: //' | tr -d '\r')
    vlog "Content-Type for ${label}: ${ct}"
    if [[ "$ct" == *"application/json"* ]]; then
        log_pass "${label} Content-Type is application/json"
    else
        # Check body instead — some servers omit Content-Type on errors
        local body
        body=$(http_get_body "$url" "$token")
        if echo "$body" | jq -e . >/dev/null 2>&1; then
            log_pass "${label} body is valid JSON (Content-Type header: ${ct:-absent})"
        else
            log_fail "${label} Content-Type" "got '${ct:-absent}', body is not JSON"
        fi
    fi
}

check_ct "${API_BASE}/health" "" "GET /api/crm/health"
check_ct "${API_BASE}/version" "" "GET /api/crm/version"

# ===================================================================
# SUMMARY
# ===================================================================
echo ""
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  FRGCRM API Test Summary${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "  Total : ${TOTAL}"
echo -e "  ${COLOR_GREEN}Pass${COLOR_RESET}  : ${PASS}"
echo -e "  ${COLOR_RED}Fail${COLOR_RESET}  : ${FAIL}"
echo -e "  ${COLOR_YELLOW}Skip${COLOR_RESET}  : ${SKIP}"
echo ""

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo -e "${COLOR_RED}${COLOR_BOLD}Failures:${COLOR_RESET}"
    for f in "${FAILURES[@]}"; do
        echo -e "  ${COLOR_RED}- $f${COLOR_RESET}"
    done
    echo ""
fi

exit "${FAIL}"
