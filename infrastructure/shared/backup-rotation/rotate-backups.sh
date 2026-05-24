#!/usr/bin/env bash
# =============================================================================
# rotate-backups.sh — Generic Backup Rotation Script
# =============================================================================
# Given a directory containing dated backup files and a retention policy:
#   - Keep: last 7 days, Sundays for 4 weeks, 1st-of-month for 3 months
#   - Delete with confirmation (--force to skip)
#   - Shows space freed
#   - Dry-run mode
#
# Usage: ./rotate-backups.sh [--dir <path>] [--pattern <glob>] [options]
# =============================================================================
set -euo pipefail

# --- Configuration (defaults) ------------------------------------------------
TARGET_DIR=""
FILE_PATTERN="*.dump"  # Default: PostgreSQL dump files
RETENTION_DAYS=7
RETENTION_WEEKS=4
RETENTION_MONTHS=3
FORCE=false
DRY_RUN=false
VERBOSE=false

LOG_DIR="${LOG_DIR:-/opt/logs}"
ROTATE_LOG="${LOG_DIR}/rotate.log"

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${message}" | tee -a "${ROTATE_LOG}"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Usage -------------------------------------------------------------------
usage() {
    cat <<-EOF
Usage: $(basename "$0") [options]

Generic backup rotation script. Scans a directory for dated backup files and
applies configurable retention policies.

Options:
  --dir <path>        Target directory to scan (required)
  --pattern <glob>    File pattern to match (default: *.dump)
  --days <N>          Keep N daily backups (default: 7)
  --weeks <N>         Keep N weekly (Sunday) backups (default: 4)
  --months <N>        Keep N monthly (1st-of-month) backups (default: 3)
  --force             Skip confirmation prompt
  --dry-run           Show what would be deleted without deleting
  --verbose           Show detailed file information
  --help              Show this help message

Examples:
  $(basename "$0") --dir /opt/backups/databases --pattern "*.dump"
  $(basename "$0") --dir /opt/backups/volumes --pattern "*.tar.gz" --days 7 --force
  $(basename "$0") --dir /root/backups/hostinger --days 14 --dry-run
EOF
    exit 0
}

# --- Parse arguments ---------------------------------------------------------
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                usage
                ;;
            --dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            --pattern)
                FILE_PATTERN="$2"
                shift 2
                ;;
            --days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --weeks)
                RETENTION_WEEKS="$2"
                shift 2
                ;;
            --months)
                RETENTION_MONTHS="$2"
                shift 2
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate
    if [ -z "${TARGET_DIR}" ]; then
        echo "ERROR: --dir is required"
        usage
    fi

    if [ ! -d "${TARGET_DIR}" ]; then
        echo "ERROR: Directory does not exist: ${TARGET_DIR}"
        exit 1
    fi
}

# --- Get file's day-of-month (1-31) ------------------------------------------
get_dom() {
    local file="$1"
    date -r "${file}" '+%d' 2>/dev/null || echo "99"
}

# --- Get file's day-of-week (1=Mon .. 7=Sun) ---------------------------------
get_dow() {
    local file="$1"
    date -r "${file}" '+%u' 2>/dev/null || echo "0"
}

# --- Get file's modification timestamp (epoch) --------------------------------
get_mtime() {
    local file="$1"
    stat -c%Y "${file}" 2>/dev/null || stat -f%m "${file}" 2>/dev/null || echo "0"
}

# --- Apply retention policy --------------------------------------------------
apply_retention() {
    local dir="$1"
    local pattern="$2"
    local keep_daily="$3"
    local keep_weekly="$4"
    local keep_monthly="$5"

    log_info "Applying retention to: ${dir}/${pattern}"
    log_info "Policy: daily=${keep_daily}, weekly=${keep_weekly}, monthly=${keep_monthly}"

    # Find all matching files, sorted by modification time (newest first)
    local all_files=()
    while IFS= read -r file; do
        all_files+=("$file")
    done < <(find "${dir}" -maxdepth 1 -type f -name "${pattern}" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    local total_files="${#all_files[@]}"
    if [ "${total_files}" -eq 0 ]; then
        log_info "No files matching '${pattern}' found in ${dir}"
        return 0
    fi

    log_info "Found ${total_files} files"

    # --- Categorize files ---
    local -a monthly_keep_files=()
    local -a weekly_keep_files=()
    local -a daily_keep_files=()
    local -a delete_candidates=()

    local monthly_count=0
    local weekly_count=0
    local daily_count=0

    for file in "${all_files[@]}"; do
        local dom
        dom="$(get_dom "${file}")"
        local dow
        dow="$(get_dow "${file}")"
        local fname
        fname="$(basename "${file}")"

        # Check if this file is a monthly candidate (1st of month)
        if [ "${dom}" = "01" ]; then
            monthly_count=$((monthly_count + 1))
            if [ "${monthly_count}" -le "${keep_monthly}" ]; then
                monthly_keep_files+=("${file}")
                if [ "${VERBOSE}" = "true" ]; then
                    log_info "  MONTHLY KEEP: ${fname}"
                fi
                continue
            fi
        fi

        # Check if this file is a weekly candidate (Sunday)
        if [ "${dow}" = "7" ]; then
            weekly_count=$((weekly_count + 1))
            if [ "${weekly_count}" -le "${keep_weekly}" ]; then
                weekly_keep_files+=("${file}")
                if [ "${VERBOSE}" = "true" ]; then
                    log_info "  WEEKLY KEEP: ${fname}"
                fi
                continue
            fi
        fi

        # Daily retention (files sorted newest first, keep first N)
        daily_count=$((daily_count + 1))
        if [ "${daily_count}" -le "${keep_daily}" ]; then
            daily_keep_files+=("${file}")
            if [ "${VERBOSE}" = "true" ]; then
                log_info "  DAILY KEEP: ${fname}"
            fi
        else
            delete_candidates+=("${file}")
        fi
    done

    local delete_count="${#delete_candidates[@]}"
    local delete_size=0
    local delete_size_hr="0"

    if [ "${delete_count}" -gt 0 ]; then
        # Calculate space that would be freed
        for file in "${delete_candidates[@]}"; do
            local fsize
            fsize="$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo "0")"
            delete_size=$((delete_size + fsize))
        done
        delete_size_hr="$(numfmt --to=iec "${delete_size}" 2>/dev/null || echo "${delete_size} bytes")"
    fi

    # --- Summary ---
    echo ""
    echo "========================================================"
    echo "Rotation Summary for: ${dir}/${pattern}"
    echo "========================================================"
    echo "  Total files:           ${total_files}"
    echo "  Monthly keep (1st):    ${#monthly_keep_files[@]}"
    echo "  Weekly keep (Sun):     ${#weekly_keep_files[@]}"
    echo "  Daily keep (recent):   ${#daily_keep_files[@]}"
    echo "  To delete:             ${delete_count}"
    echo "  Space to free:         ${delete_size_hr}"
    echo "========================================================"
    echo ""

    if [ "${delete_count}" -eq 0 ]; then
        log_info "No files to delete — retention policy satisfied"
        return 0
    fi

    # --- Show files to delete ---
    if [ "${VERBOSE}" = "true" ] || [ "${delete_count}" -le 20 ]; then
        echo "Files to delete:"
        for file in "${delete_candidates[@]}"; do
            local fname
            fname="$(basename "${file}")"
            local fsize
            fsize="$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null)"
            local fsize_hr
            fsize_hr="$(numfmt --to=iec "${fsize}" 2>/dev/null || echo "${fsize} bytes")"
            local fdate
            fdate="$(date -r "${file}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
            printf "  %-35s %-10s  %s\n" "${fname}" "${fsize_hr}" "${fdate}"
        done
        echo ""
    fi

    # --- Confirm and delete ---
    if [ "${DRY_RUN}" = "true" ]; then
        log_info "[DRY-RUN] Would delete ${delete_count} files (${delete_size_hr})"
        echo "[DRY-RUN] No files were deleted."
        return 0
    fi

    if [ "${FORCE}" != "true" ]; then
        echo "WARNING: This will permanently delete ${delete_count} files (${delete_size_hr})."
        read -r -p "Proceed with deletion? [y/N] " response
        if [[ ! "${response}" =~ ^[yY](es)?$ ]]; then
            log_info "Deletion cancelled by user"
            return 0
        fi
    fi

    # Perform deletion
    local deleted=0
    local freed=0
    for file in "${delete_candidates[@]}"; do
        local fsize
        fsize="$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo "0")"
        local fname
        fname="$(basename "${file}")"

        rm -f "${file}" 2>/dev/null && {
            deleted=$((deleted + 1))
            freed=$((freed + fsize))
            log_info "Deleted: ${fname}"
        } || {
            log_warn "Could not delete: ${fname}"
        }

        # Also remove .info sidecar files
        rm -f "${file}.info" 2>/dev/null || true
    done

    local freed_hr
    freed_hr="$(numfmt --to=iec "${freed}" 2>/dev/null || echo "${freed} bytes")"
    log_info "Deleted ${deleted}/${delete_count} files, freed ${freed_hr}"

    return 0
}

# === MAIN ===
main() {
    mkdir -p "${LOG_DIR}"

    parse_args "$@"

    log_info "=============================================="
    log_info "Backup Rotation Starting"
    log_info "=============================================="

    local start_time
    start_time="$(date +%s)"

    # Apply retention
    apply_retention "${TARGET_DIR}" "${FILE_PATTERN}" \
        "${RETENTION_DAYS}" "${RETENTION_WEEKS}" "${RETENTION_MONTHS}"

    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))

    log_info "Rotation complete in ${duration}s"
}

# --- Run ---------------------------------------------------------------------
main "$@"
