#!/usr/bin/env bash
# ============================================================================
# Wheeler Ecosystem — Full API Regression Test Suite Runner
# ============================================================================
# Runs each API test script in order, collects results, and produces a
# unified grand-summary report.
#
# Usage:
#   ./run-all-api-tests.sh [--host HOST] [--verbose] [--api NAME] [--report]
#
# Exit code = number of failed test suites (0 = all green).
# ============================================================================
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f /root/scripts/validation.env ]]; then
    # shellcheck source=/dev/null
    source /root/scripts/validation.env
fi

# -- Globals --------------------------------------------------------
API_HOST="${TEST_BASE_URL:-https://fundsrecoverygroup.com}"
VERBOSE=0
RUN_SINGLE=""       # if --api=NAME is set, run only that API
GENERATE_REPORT=0
REPORT_DIR="${SCRIPT_DIR}/reports"
REPORT_FILE=""

declare -A API_SCRIPTS
API_SCRIPTS[frgcrm]="${SCRIPT_DIR}/frgcrm-api-test.sh"
API_SCRIPTS[surplusai]="${SCRIPT_DIR}/surplusai-api-test.sh"
API_SCRIPTS[attorneys]="${SCRIPT_DIR}/attorney-marketplace-api-test.sh"
API_SCRIPTS[brain]="${SCRIPT_DIR}/wheeler-brain-api-test.sh"
API_SCRIPTS[radar]="${SCRIPT_DIR}/prediction-radar-api-test.sh"

declare -A API_RESULTS
declare -A API_EXIT_CODES
SUITE_TOTAL=0
SUITE_PASS=0
SUITE_FAIL=0

# -- Help -----------------------------------------------------------
usage() {
    cat <<USAGE
Usage: $0 [OPTIONS]

Wheeler Ecosystem — Full API Regression Test Suite Runner

Options:
  --host HOST      API base host (default: ${API_HOST})
  --verbose        Verbose output passed through to each test script
  --api NAME       Run only one API suite:
                     frgcrm | surplusai | attorneys | brain | radar
  --report         Generate a timestamped report in ${REPORT_DIR}
  --help           This message

Examples:
  $0 --host https://staging.fundsrecoverygroup.com --verbose
  $0 --api brain --report
  $0 --api frgcrm
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)      API_HOST="$2"; shift 2 ;;
        --verbose)   VERBOSE=1; shift ;;
        --api)       RUN_SINGLE="$2"; shift 2 ;;
        --report)    GENERATE_REPORT=1; shift ;;
        --help)      usage ;;
        *)           echo "Unknown option: $1"; usage ;;
    esac
done

# -- Build verbose flag ---------------------------------------------
VFLAG=""
if [[ "$VERBOSE" -eq 1 ]]; then
    VFLAG="--verbose"
fi

# -- Validate --api argument ----------------------------------------
VALID_APIS="frgcrm surplusai attorneys brain radar"
if [[ -n "$RUN_SINGLE" ]]; then
    found=0
    for a in $VALID_APIS; do
        if [[ "$a" == "$RUN_SINGLE" ]]; then
            found=1; break
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo -e "${COLOR_RED}Invalid API name: '${RUN_SINGLE}'.  Valid: ${VALID_APIS}${COLOR_RESET}"
        exit 1
    fi
fi

# -- Report setup ---------------------------------------------------
if [[ "$GENERATE_REPORT" -eq 1 ]]; then
    mkdir -p "${REPORT_DIR}"
    TS=$(date +%Y%m%d-%H%M%S)
    if [[ -n "$RUN_SINGLE" ]]; then
        REPORT_FILE="${REPORT_DIR}/api-test-${RUN_SINGLE}-${TS}.txt"
    else
        REPORT_FILE="${REPORT_DIR}/api-test-suite-${TS}.txt"
    fi
fi

report_echo() {
    echo "$1" | tee -a "${REPORT_FILE:-/dev/null}"
}

# -- Banner ---------------------------------------------------------
SEP="============================================================"
banner() {
    echo ""
    report_echo "${COLOR_BOLD}${COLOR_BLUE}${SEP}${COLOR_RESET}"
    report_echo "${COLOR_BOLD}${COLOR_BLUE}  Wheeler Ecosystem API Regression Suite${COLOR_RESET}"
    report_echo "${COLOR_BOLD}${COLOR_BLUE}  Host : ${API_HOST}${COLOR_RESET}"
    report_echo "${COLOR_BOLD}${COLOR_BLUE}  Date : $(date -u +'%Y-%m-%dT%H:%M:%SZ')${COLOR_RESET}"
    if [[ -n "$RUN_SINGLE" ]]; then
        report_echo "${COLOR_BOLD}${COLOR_BLUE}  Scope: ${RUN_SINGLE} only${COLOR_RESET}"
    else
        report_echo "${COLOR_BOLD}${COLOR_BLUE}  Scope: all APIs${COLOR_RESET}"
    fi
    report_echo "${COLOR_BOLD}${COLOR_BLUE}${SEP}${COLOR_RESET}"
    echo ""
}
banner

# -- Runner ---------------------------------------------------------
run_suite() {
    local name="$1"
    local script="${API_SCRIPTS[$name]}"

    if [[ ! -f "$script" ]]; then
        echo -e "${COLOR_RED}  Script not found: ${script}${COLOR_RESET}"
        API_RESULTS[$name]="MISSING"
        API_EXIT_CODES[$name]=1
        return 1
    fi

    if [[ ! -x "$script" ]]; then
        chmod +x "$script" 2>/dev/null || true
    fi

    echo -e "${COLOR_BOLD}${COLOR_CYAN}------------------------------------------------------------${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}  Running: ${name}  (${script##*/})${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}------------------------------------------------------------${COLOR_RESET}"

    local exit_code=0
    # shellcheck disable=SC2086
    bash "$script" --host "${API_HOST}" ${VFLAG} | tee -a "${REPORT_FILE:-/dev/null}" || exit_code=$?

    API_EXIT_CODES[$name]=$exit_code

    if [[ "$exit_code" -eq 0 ]]; then
        API_RESULTS[$name]="${COLOR_GREEN}PASS${COLOR_RESET}"
        ((SUITE_PASS++))
    else
        API_RESULTS[$name]="${COLOR_RED}FAIL (exit ${exit_code})${COLOR_RESET}"
        ((SUITE_FAIL++))
    fi
    ((SUITE_TOTAL++))

    echo ""
}

# -- Execute --------------------------------------------------------
if [[ -n "$RUN_SINGLE" ]]; then
    run_suite "$RUN_SINGLE"
else
    for api in frgcrm surplusai attorneys brain radar; do
        run_suite "$api"
    done
fi

# -- Grand Summary ---------------------------------------------------
echo ""
report_echo "${COLOR_BOLD}${COLOR_BLUE}${SEP}${COLOR_RESET}"
report_echo "${COLOR_BOLD}${COLOR_BLUE}  GRAND SUMMARY${COLOR_RESET}"
report_echo "${COLOR_BOLD}${COLOR_BLUE}${SEP}${COLOR_RESET}"

failed_count=0
for api in frgcrm surplusai attorneys brain radar; do
    if [[ -n "${API_RESULTS[$api]}" ]]; then
        printf "  %-20s : %b\n" "$api" "${API_RESULTS[$api]}" | tee -a "${REPORT_FILE:-/dev/null}"
    elif [[ -n "$RUN_SINGLE" ]] && [[ "$api" != "$RUN_SINGLE" ]]; then
        : # not included in this run
    else
        printf "  %-20s : %s\n" "$api" "not run" | tee -a "${REPORT_FILE:-/dev/null}"
    fi
    if [[ ${API_EXIT_CODES[$api]:-0} -ne 0 ]]; then
        ((failed_count++))
    fi
done

echo "" | tee -a "${REPORT_FILE:-/dev/null}"
report_echo "  Suites run  : ${SUITE_TOTAL}"
report_echo "  ${COLOR_GREEN}Passed${COLOR_RESET}      : ${SUITE_PASS}"
report_echo "  ${COLOR_RED}Failed${COLOR_RESET}      : ${SUITE_FAIL}"

if [[ "$GENERATE_REPORT" -eq 1 ]]; then
    echo "" | tee -a "${REPORT_FILE:-/dev/null}"
    report_echo "  Report saved to: ${REPORT_FILE}"
fi

if [[ "$failed_count" -gt 0 ]]; then
    echo ""
    report_echo "${COLOR_RED}${COLOR_BOLD}  [FAIL] ${failed_count} suite(s) failed.${COLOR_RESET}"
else
    echo ""
    report_echo "${COLOR_GREEN}${COLOR_BOLD}  [PASS] All suites passed.${COLOR_RESET}"
fi

report_echo "${COLOR_BOLD}${COLOR_BLUE}${SEP}${COLOR_RESET}"
echo ""

exit "$failed_count"
