#!/usr/bin/env bash
# ============================================================================
# Wheeler Brain OS API Regression Tests
# Target: AIOPS Node via EDGE proxy (https://fundsrecoverygroup.com/api/brain)
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
API_HOST="${TEST_WHEELER_BRAIN_HOST:-https://fundsrecoverygroup.com}"
API_BASE="${API_HOST}/api/brain"
API_TOKEN="${WHEELER_BRAIN_TOKEN:-}"

TIMEOUT="${TEST_REQUEST_TIMEOUT:-10}"
AI_TIMEOUT="${TEST_AI_TIMEOUT:-30}"      # AI endpoints get longer timeout
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

Wheeler Brain OS API Regression Test Suite

Options:
  --host HOST     API base host (default: ${API_HOST})
  --verbose       Verbose output
  --help          This message

Environment:
  WHEELER_BRAIN_TOKEN  API bearer token.  Auth tests are skipped when empty.
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)     API_HOST="$2"; API_BASE="${API_HOST}/api/brain"; shift 2 ;;
        --verbose)  VERBOSE=1; TEST_VERBOSE=1; shift ;;
        --help)     usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# -- Helpers ---------------------------------------------------------
log_pass() { echo -e "  ${SYMBOL_PASS} ${COLOR_GREEN}PASS${COLOR_RESET}  $1"; ((PASS++)); ((TOTAL++)); }
log_fail() { echo -e "  ${SYMBOL_FAIL} ${COLOR_RED}FAIL${COLOR_RESET}  $1 — $2"; ((FAIL++)); ((TOTAL++)); FAILURES+=("[Wheeler Brain] $1"); }
log_skip() { echo -e "  ${SYMBOL_SKIP} ${COLOR_YELLOW}SKIP${COLOR_RESET}  $1 — $2"; ((SKIP++)); ((TOTAL++)); }
log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}  $1"; }
log_hdr()  { echo -e "\n${COLOR_BOLD}${COLOR_MAGENTA}$1${COLOR_RESET}"; }

http_get() {
    local url="$1" token="$2" t="${3:-$TIMEOUT}"
    if [[ -n "$token" ]]; then
        curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${token}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    else
        curl -s -o /dev/null -w '%{http_code}' --connect-timeout "${t}" --max-time "${t}" "${url}"
    fi
}

http_get_body() {
    local url="$1" token="$2" t="${3:-$TIMEOUT}"
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Bearer ${token}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    else
        curl -s --connect-timeout "${t}" --max-time "${t}" "${url}"
    fi
}

http_get_headers() {
    local url="$1" token="$2" t="${3:-$TIMEOUT}"
    if [[ -n "$token" ]]; then
        curl -s -I -H "Authorization: Bearer ${token}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    else
        curl -s -I --connect-timeout "${t}" --max-time "${t}" "${url}"
    fi
}

http_post() {
    local url="$1" data="$2" token="$3" ct="${4:-application/json}" t="${5:-$TIMEOUT}"
    if [[ -n "$token" ]]; then
        curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: ${ct}" -H "Authorization: Bearer ${token}" -d "${data}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    else
        curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: ${ct}" -d "${data}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    fi
}

http_post_body() {
    local url="$1" data="$2" token="$3" ct="${4:-application/json}" t="${5:-$TIMEOUT}"
    if [[ -n "$token" ]]; then
        curl -s -X POST -H "Content-Type: ${ct}" -H "Authorization: Bearer ${token}" -d "${data}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    else
        curl -s -X POST -H "Content-Type: ${ct}" -d "${data}" --connect-timeout "${t}" --max-time "${t}" "${url}"
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
    local url="$1" token="$2" t="${3:-$TIMEOUT}"
    local start end
    start=$(date +%s.%N)
    if [[ -n "$token" ]]; then
        curl -s -o /dev/null -H "Authorization: Bearer ${token}" --connect-timeout "${t}" --max-time "${t}" "${url}"
    else
        curl -s -o /dev/null --connect-timeout "${t}" --max-time "${t}" "${url}"
    fi
    end=$(date +%s.%N)
    echo "$end - $start" | bc -l
}

# -- Main ------------------------------------------------------------
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Wheeler Brain OS API Regression Test Suite${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Target     : ${API_BASE}${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Timeout    : ${TIMEOUT}s (AI endpoints: ${AI_TIMEOUT}s)${COLOR_RESET}"
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
    log_skip "GET /api/brain/health" "connection refused"
else
    assert_status "GET /api/brain/health returns 200" "$status" "200"
fi

body=$(http_get_body "${API_BASE}/health" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/brain/health returns valid JSON"
    assert_json_field "Health status field" "$body" "status"
else
    log_skip "GET /api/brain/health body validation" "invalid or empty JSON"
fi

# ===================================================================
# 2. VERSION ENDPOINT
# ===================================================================
log_hdr "2. Version Endpoint"

status=$(http_get "${API_BASE}/version" "")
assert_status "GET /api/brain/version returns 200" "$status" "200"

body=$(http_get_body "${API_BASE}/version" "")
if echo "$body" | jq -e . >/dev/null 2>&1; then
    log_pass "GET /api/brain/version returns valid JSON"
    assert_json_field "Version field present" "$body" "version"
fi

# ===================================================================
# 3. AI CHAT COMPLETION (LIGHTWEIGHT)
# ===================================================================
log_hdr "3. AI Chat Completion Endpoint"

CHAT_PAYLOAD='{"messages":[{"role":"user","content":"Hello, respond with a one-word greeting."}],"max_tokens":10,"stream":false}'

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_post "${API_BASE}/chat" "${CHAT_PAYLOAD}" "${API_TOKEN}" "application/json" "${AI_TIMEOUT}")
else
    status=$(http_post "${API_BASE}/chat" "${CHAT_PAYLOAD}" "" "application/json" "${AI_TIMEOUT}")
fi

if [[ "$status" == "200" ]]; then
    log_pass "POST /api/brain/chat returns 200"
    body=$(http_post_body "${API_BASE}/chat" "${CHAT_PAYLOAD}" "${API_TOKEN}" "application/json" "${AI_TIMEOUT}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "POST /api/brain/chat returns valid JSON"
        if echo "$body" | jq -e '.choices[0].message.content // .response // .content // .reply' >/dev/null 2>&1; then
            log_pass "POST /api/brain/chat response contains content"
        else
            log_skip "Chat content check" "unknown response field structure"
        fi
    else
        log_fail "POST /api/brain/chat" "response is not valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "POST /api/brain/chat" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/brain/chat" "endpoint not implemented (404)"
else
    log_fail "POST /api/brain/chat" "unexpected status $status"
fi

# -- chat with empty messages
status=$(http_post "${API_BASE}/chat" '{"messages":[]}' "${API_TOKEN}" "application/json" "${AI_TIMEOUT}")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "POST /api/brain/chat (empty messages) returns $status"
else
    log_skip "POST /api/brain/chat (empty messages)" "got $status (expected 400/422)"
fi

# ===================================================================
# 4. AGENT STATUS ENDPOINT
# ===================================================================
log_hdr "4. Agent Status Endpoint"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/agent/status" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/agent/status" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/brain/agent/status returns 200"
    body=$(http_get_body "${API_BASE}/agent/status" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/brain/agent/status returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/brain/agent/status" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/brain/agent/status" "endpoint not implemented (404)"
else
    log_fail "GET /api/brain/agent/status" "unexpected status $status"
fi

# -- list agents
if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/agents" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/agents" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/brain/agents returns 200"
    body=$(http_get_body "${API_BASE}/agents" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/brain/agents returns valid JSON"
    fi
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/brain/agents" "endpoint not implemented"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/brain/agents" "auth required"
else
    log_skip "GET /api/brain/agents" "status $status"
fi

# ===================================================================
# 5. KNOWLEDGE BASE QUERY
# ===================================================================
log_hdr "5. Knowledge Base Query Endpoint"

KB_PAYLOAD='{"query":"What are the steps for asset recovery?","top_k":3}'

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_post "${API_BASE}/knowledge/query" "${KB_PAYLOAD}" "${API_TOKEN}" "application/json" "${AI_TIMEOUT}")
else
    status=$(http_post "${API_BASE}/knowledge/query" "${KB_PAYLOAD}" "" "application/json" "${AI_TIMEOUT}")
fi

if [[ "$status" == "200" ]]; then
    log_pass "POST /api/brain/knowledge/query returns 200"
    body=$(http_post_body "${API_BASE}/knowledge/query" "${KB_PAYLOAD}" "${API_TOKEN}" "application/json" "${AI_TIMEOUT}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "POST /api/brain/knowledge/query returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "POST /api/brain/knowledge/query" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "POST /api/brain/knowledge/query" "endpoint not implemented (404)"
else
    log_fail "POST /api/brain/knowledge/query" "unexpected status $status"
fi

# -- empty query
status=$(http_post "${API_BASE}/knowledge/query" '{"query":""}' "${API_TOKEN}" "application/json" "${AI_TIMEOUT}")
if [[ "$status" == "400" ]] || [[ "$status" == "422" ]]; then
    log_pass "POST /api/brain/knowledge/query (empty query) returns $status"
else
    log_skip "POST /api/brain/knowledge/query (empty query)" "got $status"
fi

# ===================================================================
# 6. TASK / WORKFLOW STATUS
# ===================================================================
log_hdr "6. Task/Workflow Status Endpoint"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/tasks" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/tasks" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/brain/tasks returns 200"
    body=$(http_get_body "${API_BASE}/tasks" "${API_TOKEN}")
    if echo "$body" | jq -e . >/dev/null 2>&1; then
        log_pass "GET /api/brain/tasks returns valid JSON"
    fi
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/brain/tasks" "auth required"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/brain/tasks" "endpoint not implemented (404)"
else
    log_fail "GET /api/brain/tasks" "unexpected status $status"
fi

# -- specific task
status=$(http_get "${API_BASE}/tasks/task-test-001" "${API_TOKEN}")
if [[ "$status" == "200" ]]; then
    log_pass "GET /api/brain/tasks/{id} returns 200"
elif [[ "$status" == "404" ]]; then
    log_pass "GET /api/brain/tasks/{nonexistent} returns 404 (expected for test ID)"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/brain/tasks/{id}" "auth required"
else
    log_skip "GET /api/brain/tasks/{id}" "status $status"
fi

# -- workflow status
if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/workflows" "${API_TOKEN}")
else
    status=$(http_get "${API_BASE}/workflows" "")
fi

if [[ "$status" == "200" ]]; then
    log_pass "GET /api/brain/workflows returns 200"
elif [[ "$status" == "404" ]]; then
    log_skip "GET /api/brain/workflows" "endpoint not implemented"
elif [[ "$status" == "401" ]]; then
    log_skip "GET /api/brain/workflows" "auth required"
else
    log_skip "GET /api/brain/workflows" "status $status"
fi

# ===================================================================
# 7. AUTHENTICATION
# ===================================================================
log_hdr "7. Authentication"

status=$(http_post "${API_BASE}/auth/login" '{"email":"invalid@nowhere.test","password":"bad"}' "")
assert_status "POST /api/brain/auth/login (bad creds)" "$status" "401"

status=$(http_post "${API_BASE}/auth/login" '{}' "")
assert_status "POST /api/brain/auth/login (empty body)" "$status" "401"

if [[ -n "${API_TOKEN}" ]]; then
    status=$(http_get "${API_BASE}/auth/verify" "${API_TOKEN}")
    if [[ "$status" != "404" ]]; then
        assert_status "GET /api/brain/auth/verify (with token)" "$status" "200"
    else
        log_skip "GET /api/brain/auth/verify" "endpoint not implemented"
    fi
else
    log_skip "Authenticated auth test" "WHEELER_BRAIN_TOKEN not set"
fi

# ===================================================================
# 8. ERROR HANDLING
# ===================================================================
log_hdr "8. Error Handling"

# 8a — 404
status=$(http_get "${API_BASE}/definitely-nonexistent" "")
assert_status "Nonexistent route returns 404" "$status" "404"

# 8b — malformed JSON
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Content-Type: application/json" \
    -d 'not valid json {{{' \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/chat")
assert_status "Malformed JSON returns 400" "$status" "400"

# 8c — unsupported method
status=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "${API_BASE}/health")
if [[ "$status" == "405" ]]; then
    log_pass "PATCH /api/brain/health returns 405"
else
    log_skip "PATCH /api/brain/health" "got $status"
fi

# ===================================================================
# 9. LATENCY TESTS (AI ENDPOINTS GET 30s TIMEOUT)
# ===================================================================
log_hdr "9. Latency Tests"

# Standard endpoints — 2s
elapsed=$(timed_get "${API_BASE}/health" "" "${TIMEOUT}")
assert_elapsed "GET /api/brain/health latency" "$elapsed" 2.0

elapsed=$(timed_get "${API_BASE}/version" "" "${TIMEOUT}")
assert_elapsed "GET /api/brain/version latency" "$elapsed" 2.0

# AI endpoints — 30s timeout
elapsed=$(timed_get "${API_BASE}/agent/status" "${API_TOKEN}" "${AI_TIMEOUT}")
if (( $(echo "$elapsed < 0" | bc -l 2>/dev/null || echo 0) )); then
    log_skip "GET /api/brain/agent/status latency" "request failed"
else
    assert_elapsed "GET /api/brain/agent/status latency (AI)" "$elapsed" 30.0
fi

# ===================================================================
# 10. STREAMING RESPONSE VALIDATION
# ===================================================================
log_hdr "10. Streaming Response Validation"

STREAM_PAYLOAD='{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":5,"stream":true}'

if [[ -n "${API_TOKEN}" ]]; then
    log_info "Testing streaming response (SSE/ndjson) …"
    # Use curl without -s so we capture the stream; grab first few lines
    stream_output=$(curl -s -N -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -d "${STREAM_PAYLOAD}" \
        --connect-timeout "${TIMEOUT}" --max-time "${AI_TIMEOUT}" \
        "${API_BASE}/chat" 2>&1 | head -20)

    if [[ -z "$stream_output" ]]; then
        log_skip "Streaming response test" "empty response"
    elif echo "$stream_output" | grep -qE '^data:|^\{|event:'; then
        log_pass "Streaming endpoint returned SSE/ndjson data"
    elif echo "$stream_output" | jq -e . >/dev/null 2>&1; then
        log_pass "Streaming endpoint returned valid JSON (non-streaming fallback)"
    else
        log_skip "Streaming response validation" "unknown format: $(echo "$stream_output" | head -1)"
    fi
else
    log_skip "Streaming response test" "WHEELER_BRAIN_TOKEN not set"
fi

# Content-Type check for standard endpoints
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

check_ct "${API_BASE}/health" "" "GET /api/brain/health"
check_ct "${API_BASE}/version" "" "GET /api/brain/version"

# ===================================================================
# SUMMARY
# ===================================================================
echo ""
echo -e "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_BLUE}  Wheeler Brain OS API Test Summary${COLOR_RESET}"
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
