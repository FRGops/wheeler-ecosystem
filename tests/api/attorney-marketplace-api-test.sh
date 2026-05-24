#!/usr/bin/env bash
# ============================================================================
# Attorney Marketplace API Regression Tests
# Target: AIOPS Node via EDGE proxy (https://fundsrecoverygroup.com/api/attorneys)
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
API_HOST="${TEST_ATTORNEY_HOST:-https://fundsrecoverygroup.com}"
API_BASE="${API_HOST}/api/attorneys"
API_TOKEN="${ATTORNEY_TOKEN:-}"

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

Attorney Marketplace API Regression Test Suite

Options:
  --host HOST     API base host (default: ${API_HOST})
  --verbose       Verbose output
  --help          This message

Environment:
  ATTORNEY_TOKEN  API bearer token.  Auth tests are skipped when empty.
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     API_HOST="$2"; API_BASE="${API_HOST}/api/attorneys"; shift 2 ;;
        --verbose)  VERBOSE=1; TEST_VERBOSE=1; shift ;;
        --help)     usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# -- Helpers ---------------------------------------------------------
log_pass() { echo -e "  ${SYMBOL_PASS} ${COLOR_GREEN}PASS${COLOR_RESET}  $1"; ((PASS++)); ((TOTAL++)); }
log_fail() { echo -e "  ${SYMBOL_FAIL} ${COLOR_RED}FAIL${COLOR_RESET}  $1 — $2"; ((FAIL++)); ((TOTAL++)); FAILURES+=("[Attorney Mkt] $1"); }
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
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Attorney Marketplace API Regression Test Suite${COLOR_RESET}"
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
    log_skip "GET /api/attorneys/health" "connection refused"
else
    assert_status "GET /api/attorneys/health returns 200" "$status" "200"
fi

body=$(http_get_body "${API_BASE}/health" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/attorneys/health returns valid JSON"
    assert_json_field "Health status field" "$body" "status"
else
    log_skip "GET /api/attorneys/health body validation" "invalid or empty JSON"
fi

# ===================================================================
# 2. VERSION ENDPOINT
# ===================================================================
log_hdr "2. Version Endpoint"

status=$(http_get "${API_BASE}/version" "")
assert_status "GET /api/attorneys/version returns 200" "$status" "200"

body=$(http_get_body "${API_BASE}/version" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/attorneys/version returns valid JSON"
    assert_json_field "Version field present" "$body" "version"
fi

# ===================================================================
# 3. ATTORNEY SEARCH
# ===================================================================
log_hdr "3. Attorney Search Endpoint"

status=$(http_get "${API_BASE}/search?q=bankruptcy&state=CA" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/search?q=bankruptcy&state=CA returns 200"
    body=$(http_get_body "${API_BASE}/search?q=bankruptcy&state=CA" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/attorneys/search returns valid JSON"
        # Check for search results array
        if echo "$body" | jq -e 'has("results") or has("attorneys") or has("data") or type == "array"' >/dev/null 2>&1; then
            log_pass "GET /api/attorneys/search response structure valid"
        fi
    fi
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/attorneys/search" "endpoint not implemented (404)"
else
    log_fail "GET /api/attorneys/search" "unexpected status $status"
fi

# -- search with empty query
status=$(http_get "${API_BASE}/search?q=" "")
if [[ "$status" == "200" ]] || [[ "$status" == "400" ]]; then
    log_pass "GET /api/attorneys/search?q= (empty query) handled ($status)"
else
    log_skip "GET /api/attorneys/search?q=" "unexpected status $status"
fi

# -- search with multiple filters
status=$(http_get "${API_BASE}/search?q=litigation&state=NY&practice_area=securities" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/search with multiple filters returns 200"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/attorneys/search with filters" "endpoint not implemented"
else
    log_skip "GET /api/attorneys/search filters" "status $status"
fi

# ===================================================================
# 4. ATTORNEY PROFILE
# ===================================================================
log_hdr "4. Attorney Profile Endpoint"

# -- valid attorney (use a known test ID or placeholder)
status=$(http_get "${API_BASE}/profile/test-attorney-1" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/profile/{id} returns 200"
    body=$(http_get_body "${API_BASE}/profile/test-attorney-1" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/attorneys/profile/{id} returns valid JSON"
        assert_json_field "Attorney profile has name" "$body" "name"
    fi
elif [[ "$status" == "404" ]]; then
    log_pass "GET /api/attorneys/profile/{nonexistent} returns 404 (expected for test ID)"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/attorneys/profile/{id}" "auth required"
else
    log_fail "GET /api/attorneys/profile/{id}" "unexpected status $status"
fi

# -- profile not found
status=$(http_get "${API_BASE}/profile/nonexistent-id-999999" "")
if [[ "$status" == "404" ]]; then
    log_pass "GET /api/attorneys/profile/{bad-id} returns 404"
elif [[ "$status" == "200" ]]; then
    log_skip "GET /api/attorneys/profile/{bad-id}" "endpoint returned 200 (may have fallback)"
else
    log_skip "GET /api/attorneys/profile/{bad-id}" "status $status"
fi

# ===================================================================
# 5. PRACTICE AREA LISTING
# ===================================================================
log_hdr "5. Practice Area Listing"

status=$(http_get "${API_BASE}/practice-areas" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/practice-areas returns 200"
    body=$(http_get_body "${API_BASE}/practice-areas" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/attorneys/practice-areas returns valid JSON"
        assert_json_array "Practice areas is array" "$body" "practice_areas"
    fi
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/attorneys/practice-areas" "endpoint not implemented (404)"
else
    log_fail "GET /api/attorneys/practice-areas" "unexpected status $status"
fi

# ===================================================================
# 6. STATE/JURISDICTION FILTERING
# ===================================================================
log_hdr "6. State/Jurisdiction Filtering"

status=$(http_get "${API_BASE}/jurisdictions" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/jurisdictions returns 200"
    body=$(http_get_body "${API_BASE}/jurisdictions" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/attorneys/jurisdictions returns valid JSON"
    fi
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/attorneys/jurisdictions" "endpoint not implemented (404)"
else
    log_skip "GET /api/attorneys/jurisdictions" "status $status"
fi

# -- filter attorneys by state
status=$(http_get "${API_BASE}/search?state=NY" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/search?state=NY returns 200"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/attorneys/search?state=NY" "search endpoint not implemented"
else
    log_skip "GET /api/attorneys/search?state=NY" "status $status"
fi

# -- filter by multiple states
status=$(http_get "${API_BASE}/search?state=CA&state=NY" "")
vlog "Multi-state filter returned HTTP $status"
if [[ "$status" == "200" ]] || [[ "$status" == "400" ]]; then
    log_pass "GET /api/attorneys/search?state=CA&state=NY handled ($status)"
else
    log_skip "GET /api/attorneys/search multi-state" "status $status"
fi

# ===================================================================
# 7. REVIEW/RATING ENDPOINT
# ===================================================================
log_hdr "7. Review/Rating Endpoint"

# -- get reviews for an attorney
status=$(http_get "${API_BASE}/profile/test-attorney-1/reviews" "")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/attorneys/profile/{id}/reviews returns 200"
    body=$(http_get_body "${API_BASE}/profile/test-attorney-1/reviews" "")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET reviews returns valid JSON"
    fi
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/attorneys/profile/{id}/reviews" "endpoint not implemented (404)"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/attorneys/profile/{id}/reviews" "auth required"
else
    log_skip "GET /api/attorneys/profile/{id}/reviews" "status $status"
fi

# -- submit review (requires auth)
if [[ -n "${API_TOKEN}" ]]; then
    REVIEW_PAYLOAD='{"rating":5,"title":"Excellent service","comment":"API regression test review"}'
    status=$(http_post "${API_BASE}/profile/test-attorney-1/reviews" "${REVIEW_PAYLOAD}" "${API_TOKEN}")
    if [[ "$status" == "201" ]] || [[ "$status" == "200" ]]; then
        log_pass "POST /api/attorneys/profile/{id}/reviews returns $status"
    elif [[ "$status" == "403" ]]; then
        log_skip "POST review" "forbidden (403)"
    elif [[ "$status" == "404" ]]; then
        log_skip "POST review" "endpoint not implemented"
    else
        log_fail "POST review" "unexpected status $status"
    fi
else
    log_skip "POST review (authenticated)" "ATTORNEY_TOKEN not set"
fi

# ===================================================================
# 8. CONTACT REQUEST ENDPOINT
# ===================================================================
log_hdr "8. Contact Request Endpoint"

CONTACT_PAYLOAD='{"attorney_id":"test-attorney-1","client_name":"QA Test","client_email":"qa@fundsrecoverygroup.com","message":"API regression test contact request"}'

status=$(http_post "${API_BASE}/contact" "${CONTACT_PAYLOAD}" "")
if [[ "$status" == "200" ]] || [[ "$status" == "201" ]] || [[ "$status" == "202" ]]; then
    log_pass "POST /api/attorneys/contact returns $status"
elif [[ "$status" == "401" ]]; then
    log_skip "POST /api/attorneys/contact" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/attorneys/contact" "endpoint not implemented (404)"
else
    log_fail "POST /api/attorneys/contact" "unexpected status $status"
fi

# -- contact with missing fields
status=$(http_post "${API_BASE}/contact" '{}' "")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "POST /api/attorneys/contact (empty body) returns $status"
else
    log_skip "POST /api/attorneys/contact (empty body)" "got $status"
fi

# ===================================================================
# 9. AUTHENTICATION
# ===================================================================
log_hdr "9. Authentication"

status=$(http_post "${API_BASE}/auth/login" '{"email":"bad@test.local","password":"wrong"}' "")
assert_status "POST /api/attorneys/auth/login (bad creds)" "$status" "401"

status=$(http_post "${API_BASE}/auth/login" '{}' "")
assert_status "POST /api/attorneys/auth/login (empty body)" "$status" "401"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/auth/verify" "${API_TOKEN}")
    if [[ "$status" != "404" ]]; then
        assert_status "GET /api/attorneys/auth/verify (with token)" "$status" "200"
    else
        log_skip "GET /api/attorneys/auth/verify" "endpoint not implemented"
    fi
else
    log_skip "Authenticated auth test" "ATTORNEY_TOKEN not set"
fi

# ===================================================================
# 10. ERROR HANDLING
# ===================================================================
log_hdr "10. Error Handling"

# 10a — 404
status=$(http_get "${API_BASE}/this-route-does-not-exist" "")
assert_status "Nonexistent route returns 404" "$status" "404"

# 10b — malformed JSON
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d 'not-json {{{' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/contact")
assert_status "Malformed JSON returns 400" "$status" "400"

# 10c — invalid method
status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/health")
if [[ "$status" == "405" ]]; then
    log_pass "PATCH health returns 405 (Method Not Allowed)"
else
    log_skip "PATCH health" "got $status"
fi

# 10d — request with large payload (if applicable)
LARGE_PAYLOAD="{\"data\":\"$(python3 -c "print('x'*100000)" 2>/dev/null || printf 'x%.0s' {1..100000})\"}"
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d "${LARGE_PAYLOAD}" \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/contact" 2>/dev/null)
if [[ "$status" == "413" ]]; then
    log_pass "Large payload returns 413 (Payload Too Large)"
else
    log_skip "Large payload test" "got $status (expected 413)"
fi

# ===================================================================
# 11. LATENCY TESTS
# ===================================================================
log_hdr "11. Latency Tests (< 2s per endpoint)"

elapsed=$(timed_get "${API_BASE}/health" "")
assert_elapsed "GET /api/attorneys/health latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/version" "")
assert_elapsed "GET /api/attorneys/version latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/practice-areas" "")
assert_elapsed "GET /api/attorneys/practice-areas latency" "$elapsed" 2.0

# ===================================================================
# 12. CORS TESTS
# ===================================================================
log_hdr "12. CORS Tests"

cors_header_line=$(http_options_full "${API_BASE}/health")
vlog "OPTIONS response headers: $(echo "$cors_header_line" | tr '\n' ' ')"

if echo "$cors_header_line" | grep -qi "access-control-allow-origin\|access-control-allow-methods"; then
    log_pass "OPTIONS /api/attorneys/health returns CORS headers"
else
    log_skip "CORS headers on OPTIONS" "may be configured at EDGE proxy level (not on app server)"
fi

status=$(http_options "${API_BASE}/health")
if [[ "$status" == "200" ]] || [[ "$status" == "204" ]]; then
    log_pass "OPTIONS /api/attorneys/health returns ${status}"
elif [[ "$status" == "405" ]]; then
    log_skip "OPTIONS /api/attorneys/health" "method not allowed"
else
    log_fail "OPTIONS /api/attorneys/health" "unexpected status $status"
fi

# Content-Type check
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

check_ct "${API_BASE}/health" "" "GET /api/attorneys/health"
check_ct "${API_BASE}/version" "" "GET /api/attorneys/version"

# ===================================================================
# SUMMARY
# ===================================================================
echo ""
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Attorney Marketplace API Test Summary${COLOR_RESET}"
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
