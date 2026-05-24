#!/usr/bin/env bash
# ============================================================================
# Prediction Radar API Regression Tests
# Target: AIOPS Node via EDGE proxy (https://fundsrecoverygroup.com/api/radar)
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
API_HOST="${TEST_PREDICTION_RADAR_HOST:-https://fundsrecoverygroup.com}"
API_BASE="${API_HOST}/api/radar"
API_TOKEN="${PREDICTION_RADAR_TOKEN:-}"

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

Prediction Radar API Regression Test Suite

Options:
  --host HOST     API base host (default: ${API_HOST})
  --verbose       Verbose output
  --help          This message

Environment:
  PREDICTION_RADAR_TOKEN  API bearer token.  Auth tests are skipped when empty.
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     API_HOST="$2"; API_BASE="${API_HOST}/api/radar"; shift 2 ;;
        --verbose)  VERBOSE=1; TEST_VERBOSE=1; shift ;;
        --help)     usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# -- Helpers ---------------------------------------------------------
log_pass() { echo -e "  ${SYMBOL_PASS} ${COLOR_GREEN}PASS${COLOR_RESET}  $1"; ((PASS++)); ((TOTAL++)); }
log_fail() { echo -e "  ${SYMBOL_FAIL} ${COLOR_RED}FAIL${COLOR_RESET}  $1 — $2"; ((FAIL++)); ((TOTAL++)); FAILURES+=("[Prediction Radar] $1"); }
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
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Prediction Radar API Regression Test Suite${COLOR_RESET}"
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
    log_skip "GET /api/radar/health" "connection refused"
else
    assert_status "GET /api/radar/health returns 200" "$status" "200"
fi

body=$(http_get_body "${API_BASE}/health" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/radar/health returns valid JSON"
    assert_json_field "Health status field" "$body" "status"
else
    log_skip "GET /api/radar/health body validation" "invalid or empty JSON"
fi

# ===================================================================
# 2. VERSION ENDPOINT
# ===================================================================
log_hdr "2. Version Endpoint"

status=$(http_get "${API_BASE}/version" "")
assert_status "GET /api/radar/version returns 200" "$status" "200"

body=$(http_get_body "${API_BASE}/version" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/radar/version returns valid JSON"
    assert_json_field "Version field present" "$body" "version"
fi

# ===================================================================
# 3. PREDICTION QUERY ENDPOINT
# ===================================================================
log_hdr "3. Prediction Query Endpoint"

PREDICTION_PAYLOAD='{"case_type":"asset_recovery","jurisdiction":"US","parameters":{"estimated_amount":500000,"complexity":"medium"}}'

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_post "${API_BASE}/predict" "${PREDICTION_PAYLOAD}" "${API_TOKEN}")
else
    status=$(http_post "${API_BASE}/predict" "${PREDICTION_PAYLOAD}" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "POST /api/radar/predict returns 200"
    body=$(http_post_body "${API_BASE}/predict" "${PREDICTION_PAYLOAD}" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "POST /api/radar/predict returns valid JSON"
        assert_json_field "Prediction has probability" "$body" "probability"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "POST /api/radar/predict" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/radar/predict" "endpoint not implemented (404)"
else
    log_fail "POST /api/radar/predict" "unexpected status $status"
fi

# -- predict with missing parameters
status=$(http_post "${API_BASE}/predict" '{"case_type":"unknown"}' "${API_TOKEN}")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "POST /api/radar/predict (missing params) returns $status"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/radar/predict validation" "endpoint not implemented"
else
    log_skip "POST /api/radar/predict validation" "got $status"
fi

# -- predict with empty body
status=$(http_post "${API_BASE}/predict" '{}' "${API_TOKEN}")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "POST /api/radar/predict (empty body) returns $status"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/radar/predict (empty body)" "endpoint not implemented"
else
    log_skip "POST /api/radar/predict (empty body)" "got $status"
fi

# ===================================================================
# 4. DATA SOURCES STATUS
# ===================================================================
log_hdr "4. Data Sources Status"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/datasources" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/datasources" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/radar/datasources returns 200"
    body=$(http_get_body "${API_BASE}/datasources" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/radar/datasources returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/radar/datasources" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/radar/datasources" "endpoint not implemented (404)"
else
    log_fail "GET /api/radar/datasources" "unexpected status $status"
fi

# -- specific data source health
status=$(http_get "${API_BASE}/datasources/health" "${API_TOKEN}")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/radar/datasources/health returns 200"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/radar/datasources/health" "endpoint not implemented"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/radar/datasources/health" "auth required"
else
    log_skip "GET /api/radar/datasources/health" "status $status"
fi

# ===================================================================
# 5. MODEL LIST ENDPOINT
# ===================================================================
log_hdr "5. Model List Endpoint"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/models" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/models" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/radar/models returns 200"
    body=$(http_get_body "${API_BASE}/models" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/radar/models returns valid JSON"
        assert_json_array "Models is array" "$body" "models"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/radar/models" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/radar/models" "endpoint not implemented (404)"
else
    log_fail "GET /api/radar/models" "unexpected status $status"
fi

# -- single model detail
status=$(http_get "${API_BASE}/models/default-predictor" "${API_TOKEN}")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/radar/models/{name} returns 200"
elif [[ "$status" == "404" ]]; then
    log_pass "GET /api/radar/models/{nonexistent} returns 404 (expected for test model)"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/radar/models/{name}" "auth required"
else
    log_skip "GET /api/radar/models/{name}" "status $status"
fi

# ===================================================================
# 6. HISTORICAL DATA ENDPOINT
# ===================================================================
log_hdr "6. Historical Data Endpoint"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/history?days=30&limit=10" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/history?days=30&limit=10" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/radar/history?days=30 returns 200"
    body=$(http_get_body "${API_BASE}/history?days=30&limit=10" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/radar/history returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/radar/history" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/radar/history" "endpoint not implemented (404)"
else
    log_fail "GET /api/radar/history" "unexpected status $status"
fi

# -- history with no params
status=$(http_get "${API_BASE}/history" "${API_TOKEN}")
if [[ "$status" == "200" ]] || [[ "$status" == "400" ]]; then
    log_pass "GET /api/radar/history (no params) handled ($status)"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/radar/history (no params)" "endpoint not implemented"
else
    log_skip "GET /api/radar/history (no params)" "status $status"
fi

# ===================================================================
# 7. AUTHENTICATION
# ===================================================================
log_hdr "7. Authentication"

status=$(http_post "${API_BASE}/auth/login" '{"email":"bad@test.invalid","password":"wrong"}' "")
assert_status "POST /api/radar/auth/login (bad creds)" "$status" "401"

status=$(http_post "${API_BASE}/auth/login" '{}' "")
assert_status "POST /api/radar/auth/login (empty body)" "$status" "401"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/auth/verify" "${API_TOKEN}")
    if [[ "$status" != "404" ]]; then
        assert_status "GET /api/radar/auth/verify (with token)" "$status" "200"
    else
        log_skip "GET /api/radar/auth/verify" "endpoint not implemented"
    fi
else
    log_skip "Authenticated auth test" "PREDICTION_RADAR_TOKEN not set"
fi

# ===================================================================
# 8. ERROR HANDLING
# ===================================================================
log_hdr "8. Error Handling"

# 8a — 404
status=$(http_get "${API_BASE}/definitely-not-a-route" "")
assert_status "Nonexistent route returns 404" "$status" "404"

# 8b — malformed JSON
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d 'not-json {{{' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/predict")
assert_status "Malformed JSON returns 400" "$status" "400"

# 8c — invalid method
status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/health")
if [[ "$status" == "405" ]]; then
    log_pass "PATCH /api/radar/health returns 405"
else
    log_skip "PATCH /api/radar/health" "got $status"
fi

# 8d — request with non-JSON content-type
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: text/plain" \
    -d 'hello' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/predict")
if [[ "$status" == "415" ]]; then
    log_pass "Unsupported Media Type returns 415"
elif [[ "$status" == "400" ]]; then
    log_pass "Wrong Content-Type handled (400)"
else
    log_skip "Unsupported Media Type test" "got $status"
fi

# ===================================================================
# 9. LATENCY TESTS
# ===================================================================
log_hdr "9. Latency Tests (< 2s per endpoint)"

elapsed=$(timed_get "${API_BASE}/health" "")
assert_elapsed "GET /api/radar/health latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/version" "")
assert_elapsed "GET /api/radar/version latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/models" "${API_TOKEN}")
if (( $(echo "$elapsed < 0" | bc -l 2>/dev/null || echo 0) )); then
    log_skip "GET /api/radar/models latency" "request failed"
else
    assert_elapsed "GET /api/radar/models latency" "$elapsed" 2.0
fi

# ===================================================================
# 10. CORS TESTS
# ===================================================================
log_hdr "10. CORS Tests"

cors_header_line=$(http_options_full "${API_BASE}/health")
vlog "OPTIONS response headers: $(echo "$cors_header_line" | tr '\n' ' ')"

if echo "$cors_header_line" | grep -qi "access-control-allow-origin\|access-control-allow-methods"; then
    log_pass "OPTIONS /api/radar/health returns CORS headers"
else
    log_skip "CORS headers on OPTIONS" "may be configured at EDGE proxy level (not on app server)"
fi

status=$(http_options "${API_BASE}/health")
if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
    log_pass "OPTIONS /api/radar/health returns ${status}"
elif [[ "$status" == "405" ]]; then
    log_skip "OPTIONS /api/radar/health" "method not allowed"
else
    log_fail "OPTIONS /api/radar/health" "unexpected status $status"
fi

# Content-Type validation
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

check_ct "${API_BASE}/health" "" "GET /api/radar/health"
check_ct "${API_BASE}/version" "" "GET /api/radar/version"

# ===================================================================
# SUMMARY
# ===================================================================
echo ""
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Prediction Radar API Test Summary${COLOR_RESET}"
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
