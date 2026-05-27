#!/usr/bin/env bash
# ============================================
# wheeler-loader.sh — Unified Wheeler Shell Loader
# ============================================
# Source this from ~/.bashrc to activate the
# Wheeler Jarvis Command Center in your shell.
#
# Add to ~/.bashrc:
#   [ -f ~/WheelerCommandCenter/bin/wheeler-loader.sh ] && source ~/WheelerCommandCenter/bin/wheeler-loader.sh
#
# Handles both old (~/wheeler-command-center) and new (~/WheelerCommandCenter) layouts.

# Guard: prevent double-loading
if [ -n "${WHEELER_JARVIS_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

# ── New Jarvis Command Center ──
export WHEELER_HOME="${WHEELER_HOME:-$HOME/WheelerCommandCenter}"
export PATH="$WHEELER_HOME/bin:$PATH"

# ── Old Command Center (backward compat) ──
if [ -f "$HOME/wheeler-command-center/configs/shell/wheeler-loader.sh" ]; then
    source "$HOME/wheeler-command-center/configs/shell/wheeler-loader.sh"
fi

# ── Shortcuts ──
alias wh='wheeler'
alias whh='wheeler health'
alias whp='wheeler panic'
alias whd='wheeler domains'
alias whs='wheeler smoke all'
alias whm='wheeler mesh'
alias wht='wheeler today'
alias wha='wheeler ai status'

# ── Banner (interactive shells only) ──
if [[ $- == *i* ]]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     WHEELER JARVIS COMMAND CENTER — Activated           ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  wheeler health  |  whh  — ecosystem health             ║"
    echo "║  wheeler domains |  whd  — domain/SSL status            ║"
    echo "║  wheeler panic   |  whp  — emergency dashboard          ║"
    echo "║  wheeler today   |  wht  — daily CEO briefing           ║"
    echo "║  wheeler ai      |  wha  — AI routing status            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
fi

export WHEELER_JARVIS_LOADED=1
