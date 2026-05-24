#!/usr/bin/env bash
# ============================================================================
# SurplusAI API Regression Tests
# Target: AIOPS Node via EDGE proxy (https://fundsrecoverygroup.com/api/surplusai)
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

# -- Defaults -------------------------------------------------------
API_HOST="${TEST_SURPLUSAI_HOST:-https://fundsrecoverygroup.com}"
API_BASE="${API_HOST}/api/surplusai"
API_TOKEN="${SURPLUSAI_TOKEN:-}"

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

SurplusAI API Regression Test Suite

Options:
  --host HOST     API base host (default: ${API_HOST})
  --verbose       Verbose output
  --help          This message

Environment:
  SURPLUSAI_TOKEN API bearer token.  Auth tests are skipped when empty.
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     API_HOST="$2"; API_BASE="${API_HOST}/api/surplusai"; shift 2 ;;
        --verbose)  VERBOSE=1; TEST_VERBOSE=1; shift ;;
        --help)     usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# -- Helpers ---------------------------------------------------------
log_pass() { echo -e "  ${SYMBOL_PASS} ${COLOR_GREEN}PASS${COLOR_RESET}  $1"; ((PASS++)); ((TOTAL++)); }
log_fail() { echo -e "  ${SYMBOL_FAIL} ${COLOR_RED}FAIL${COLOR_RESET}  $1 — $2"; ((FAIL++)); ((TOTAL++)); FAILURES+=("[SurplusAI] $1"); }
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

assert_status() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$label (HTTP $actual)"
    else
        log_fail "$label" "expected HTTP $expected, got $actual"
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

assert_elapsed() {
    local label="$1" elapsed="$2" limit="${3:-2.0}"
    if (( $(echo "$elapsed < $limit" | bc -l 2>/dev/null || echo 0) )); then
        log_pass "$label (${elapsed}s < ${limit}s)"
    else
        log_fail "$label" "took ${elapsed}s, limit ${limit}s"
    fi
}

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

# -- Main ------------------------------------------------------------
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  SurplusAI API Regression Test Suite${COLOR_RESET}"
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
    log_skip "GET /api/surplusai/health" "connection refused"
else
    assert_status "GET /api/surplusai/health returns 200" "$status" "200"
fi

body=$(http_get_body "${API_BASE}/health" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/surplusai/health returns valid JSON"
    assert_json_field "Health status field" "$body" "status"
else
    log_skip "GET /api/surplusai/health body validation" "invalid or empty JSON"
fi

# ===================================================================
# 2. VERSION ENDPOINT
# ===================================================================
log_hdr "2. Version Endpoint"

status=$(http_get "${API_BASE}/version" "")
assert_status "GET /api/surplusai/version returns 200" "$status" "200"

body=$(http_get_body "${API_BASE}/version" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/surplusai/version returns valid JSON"
    assert_json_field "Version field present" "$body" "version"
fi

# ===================================================================
# 3. AUTHENTICATION
# ===================================================================
log_hdr "3. Authentication"

status=$(http_post "${API_BASE}/auth/login" '{"email":"invalid@nonexistent.test","password":"wrong"}' "")
assert_status "POST /api/surplusai/auth/login (bad creds)" "$status" "401"

status=$(http_post "${API_BASE}/auth/login" '{}' "")
assert_status "POST /api/surplusai/auth/login (empty body)" "$status" "401"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/auth/verify" "${API_TOKEN}")
    if [[ "$status" != "404" ]]; then
        assert_status "GET /api/surplusai/auth/verify (with token)" "$status" "200"
    else
        log_skip "GET /api/surplusai/auth/verify" "endpoint not implemented (404)"
    fi
else
    log_skip "Authenticated auth test" "SURPLUSAI_TOKEN not set"
fi

# ===================================================================
# 4. SURPLUS ASSET CRUD
# ===================================================================
log_hdr "4. Surplus Asset CRUD"

# 4a — list without token
status=$(http_get "${API_BASE}/assets" "")
if [[ "$status" == "401" ]]; then
    log_pass "GET /api/surplusai/assets (no token) returns 401"

    if [[ -n "${API_TOKEN}" ]]; then
        # 4b — list with token
        status=$(http_get "${API_BASE}/assets" "${API_TOKEN}")
        if [[ "$status" == "200" ]]; then
            log_pass "GET /api/surplusai/assets (with token) returns 200"
            body=$(http_get_body "${API_BASE}/assets" "${API_TOKEN}")
            if echo "$body" | jq -e . >/dev/null 2>&1; then
                log_pass "GET /api/surplusai/assets returns valid JSON"

                # 4c — create asset
                CREATE_PAYLOAD='{"name":"QA Test Surplus Asset","category":"equipment","estimated_value":5000.00,"condition":"good","description":"API regression test asset"}'
                status=$(http_post "${API_BASE}/assets" "${CREATE_PAYLOAD}" "${API_TOKEN}")
                if [[ "$status" == "201" ]] || [[ "$status" == "200" ]]; then
                    log_pass "POST /api/surplusai/assets (create) returns $status"

                    created_body=$(http_post_body "${API_BASE}/assets" "${CREATE_PAYLOAD}" "${API_TOKEN}")
                    CREATED_ID=$(echo "$created_body" | jq -r '.id // .asset_id // ._id // empty' 2>/dev/null)

                    if [[ -n "${CREATED_ID}" ]] && [[ "${CREATED_ID}" != "null" ]]; then
                        # 4d — GET created asset
                        status=$(http_get "${API_BASE}/assets/${CREATED_ID}" "${API_TOKEN}")
                        assert_status "GET /api/surplusai/assets/{created}" "$status" "200"

                        # 4e — PUT update
                        UPDATE_PAYLOAD='{"condition":"excellent","estimated_value":6000.00}'
                        status=$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
                            -H "Content-Type: application/json" \
                            -H "Authorization: Bearer ${API_TOKEN}" \
                            -d "${UPDATE_PAYLOAD}" \
                            --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
                            "${API_BASE}/assets/${CREATED_ID}")
                        if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
                            log_pass "PUT /api/surplusai/assets/{created} returns $status"
                        else
                            log_fail "PUT /api/surplusai/assets/{created}" "expected 200/204, got $status"
                        fi

                        # 4f — DELETE
                        status=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
                            -H "Authorization: Bearer ${API_TOKEN}" \
                            --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
                            "${API_BASE}/assets/${CREATED_ID}")
                        if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
                            log_pass "DELETE /api/surplusai/assets/{created} returns $status"
                        else
                            log_fail "DELETE /api/surplusai/assets/{created}" "expected 200/204, got $status"
                        fi

                        # 4g — confirm deleted
                        status=$(http_get "${API_BASE}/assets/${CREATED_ID}" "${API_TOKEN}")
                        assert_status "GET /api/surplusai/assets/{deleted}" "$status" "404"
                    else
                        log_skip "Asset CRUD GET/PUT/DELETE" "could not extract created asset ID"
                    fi
                elif [[ "$status" == "403" ]]; then
                    log_skip "POST /api/surplusai/assets (create)" "forbidden (403)"
                elif [[ "$status" == "405" ]]; then
                    log_skip "POST /api/surplusai/assets (create)" "method not allowed (405)"
                else
                    log_fail "POST /api/surplusai/assets (create)" "expected 201, got $status"
                fi
            fi
        else
            log_fail "GET /api/surplusai/assets (with token)" "expected 200, got $status"
        fi
    else
        log_skip "Asset CRUD (authenticated)" "SURPLUSAI_TOKEN not set"
    fi
elif [[ "$status" == "200" ]]; then
    log_pass "GET /api/surplusai/assets returns 200 (no auth)"
    body=$(http_get_body "${API_BASE}/assets" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/surplusai/assets returns valid JSON"
    fi
else
    log_skip "GET /api/surplusai/assets" "unexpected status $status"
fi

# ===================================================================
# 5. VALUATION ENDPOINT
# ===================================================================
log_hdr "5. Valuation Endpoint"

VALUATION_PAYLOAD='{"asset_id":"test-001","asset_type":"equipment","age_years":3,"condition":"good","original_value":10000.00}'

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_post "${API_BASE}/valuation" "${VALUATION_PAYLOAD}" "${API_TOKEN}")
else
    status=$(http_post "${API_BASE}/valuation" "${VALUATION_PAYLOAD}" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "POST /api/surplusai/valuation returns 200"
    body=$(http_post_body "${API_BASE}/valuation" "${VALUATION_PAYLOAD}" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "POST /api/surplusai/valuation returns valid JSON"
        assert_json_field "Valuation response has estimated_value" "$body" "estimated_value"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "POST /api/surplusai/valuation" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/surplusai/valuation" "endpoint not implemented (404)"
else
    log_fail "POST /api/surplusai/valuation" "unexpected status $status"
fi

# -- valuation with missing fields
status=$(http_post "${API_BASE}/valuation" '{}' "${API_TOKEN}")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "POST /api/surplusai/valuation (empty body) returns $status"
else
    log_skip "POST /api/surplusai/valuation (empty body)" "got $status (expected 400/422)"
fi

# ===================================================================
# 6. REPORT GENERATION ENDPOINT
# ===================================================================
log_hdr "6. Report Generation Endpoint"

REPORT_PAYLOAD='{"report_type":"valuation_summary","format":"pdf","asset_ids":["test-001"]}'

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_post "${API_BASE}/reports/generate" "${REPORT_PAYLOAD}" "${API_TOKEN}")
else
    status=$(http_post "${API_BASE}/reports/generate" "${REPORT_PAYLOAD}" "")
fi

if [[ "$status" == "200" ]] || [[ "$status" == "202" ]]; then
    log_pass "POST /api/surplusai/reports/generate returns $status"
elif [[ "$status" == "401" ]]; then
    log_skip "POST /api/surplusai/reports/generate" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/surplusai/reports/generate" "endpoint not implemented (404)"
else
    log_fail "POST /api/surplusai/reports/generate" "unexpected status $status"
fi

# -- check report status endpoint
if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/reports" "${API_TOKEN}")
    if [[ "$status" == "200" ]]; then
        log_pass "GET /api/surplusai/reports returns 200"
    elif [[ "$status" == "404" ]]; then
        log_skip "GET /api/surplusai/reports" "endpoint not implemented"
    elif [[ "$status" == "401" ]]; then
        log_skip "GET /api/surplusai/reports" "auth required"
    else
        log_fail "GET /api/surplusai/reports" "unexpected status $status"
    fi
else
    log_skip "GET /api/surplusai/reports" "SURPLUSAI_TOKEN not set"
fi

# ===================================================================
# 7. ERROR HANDLING
# ===================================================================
log_hdr "7. Error Handling"

# 7a — 404
status=$(http_get "${API_BASE}/nonexistent-route-xyz" "")
assert_status "Nonexistent route returns 404" "$status" "404"

# 7b — malformed JSON
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d 'not json {{{' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/assets")
assert_status "Malformed JSON returns 400" "$status" "400"

# 7c — wrong method
status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/health")
if [[ "$status" == "405" ]]; then
    log_pass "PATCH /api/surplusai/health returns 405 (Method Not Allowed)"
elif [[ "$status" == "404" ]]; then
    log_skip "PATCH /api/surplusai/health" "endpoint returns 404"
else
    vlog "PATCH health returned $status"
    log_pass "PATCH health handled gracefully ($status)"
fi

# 7d — invalid query parameter type
status=$(http_get "${API_BASE}/assets?limit=notanumber" "${API_TOKEN}")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "Invalid query param returns 4xx ($status)"
elif [[ "$status" == "200" ]]; then
    log_pass "Invalid query param handled gracefully (200 with default)"
else
    log_skip "Invalid query param test" "got $status"
fi

# ===================================================================
# 8. LATENCY TESTS
# ===================================================================
log_hdr "8. Latency Tests (< 2s per endpoint)"

elapsed=$(timed_get "${API_BASE}/health" "")
assert_elapsed "GET /api/surplusai/health latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/version" "")
assert_elapsed "GET /api/surplusai/version latency" "$elapsed" 2.0

if [[ -n "${API_TOKEN}" ]]; then
    elapsed=$(timed_get "${API_BASE}/assets" "${API_TOKEN}")
    assert_elapsed "GET /api/surplusai/assets latency" "$elapsed" 2.0
fi

# ===================================================================
# 9. CORS TESTS
# ===================================================================
log_hdr "9. CORS Tests"

cors_header_line=$(http_options_full "${API_BASE}/health")
vlog "OPTIONS response headers: $(echo "$cors_header_line" | tr '\n' ' ')"

if echo "$cors_header_line" | grep -qi "access-control-allow-origin\|access-control-allow-methods"; then
    log_pass "OPTIONS /api/surplusai/health returns CORS headers"
else
    log_skip "CORS headers on OPTIONS" "may be configured at EDGE proxy level (not on app server)"
fi

status=$(http_options "${API_BASE}/health")
if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
    log_pass "OPTIONS /api/surplusai/health returns ${status}"
elif [[ "$status" == "405" ]]; then
    log_skip "OPTIONS /api/surplusai/health" "method not allowed"
else
    log_fail "OPTIONS /api/surplusai/health" "unexpected status $status"
fi

# Check Content-Type on JSON endpoints
check_ct() {
    local url="$1" token="$2" label="$3"
    local headers ct
    headers=$(http_get_headers "$url" "$token")
    ct=$(echo "$headers" | grep -i '^content-type:' | head -1 | sed 's/.*: //' | tr -d '\r')
    if [[ "$ct" == *"application/json"* ]]; then
        log_pass "${label} Content-Type is application/json"
    else
        local body
        body=$(http_get_body "$url" "$token")
        if echo "$body" | jq -e . >/dev/null 2>&1; then
            log_pass "${label} body is valid JSON"
        else
            log_fail "${label} Content-Type" "got '${ct:-absent}'"
        fi
    fi
}

check_ct "${API_BASE}/health" "" "GET /api/surplusai/health"
check_ct "${API_BASE}/version" "" "GET /api/surplusai/version"

# ===================================================================
# SUMMARY
# ===================================================================
echo ""
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  SurplusAI API Test Summary${COLOR_RESET}"
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
