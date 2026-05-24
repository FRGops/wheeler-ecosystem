#!/usr/bin/env bash
# ==============================================================================
# tmux-dev-workflow.sh — Tmux Development Environment
# ==============================================================================
#
# Creates a persistent tmux session for remote development across the
# two-server Wheeler AIOps stack.
#
# Session Layout:
#   Window 1: "system"    — htop, docker stats, system monitoring
#   Window 2: "logs"      — tail -f /opt/wheeler/logs/*.log
#   Window 3: "hetzner"   — SSH to Hetzner CPX51
#   Window 4: "hostinger" — SSH to Hostinger VPS
#   Window 5: "deploy"    — Working directory in /opt/wheeler/deploy/
#   Window 6: "edit"      — Code editing workspace
#
# Usage:
#   ./tmux-dev-workflow.sh [--session <name>] [--attach] [--kill]
#
# Options:
#   --session <name>  Session name (default: wheeler-dev)
#   --attach          Attach immediately after creation
#   --kill            Kill the session
#   --layout <name>   Layout preset (dev, ops, monitoring)
#
# Key bindings (inside session):
#   Ctrl+a Ctrl+|     Split vertically
#   Ctrl+a Ctrl+-     Split horizontally
#   Ctrl+a n/p        Next/previous window
#   Ctrl+a 1-6        Jump to window 1-6
#   Ctrl+a d          Detach (session keeps running)
#   Ctrl+a :source-file ~/.tmux.conf  Reload config
#
# This script is idempotent — safe to run multiple times.
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
SESSION_NAME="${TMUX_SESSION:-wheeler-dev}"
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
SCRIPTS_DIR="${BASE_DIR}/scripts"
DEPLOY_DIR="${BASE_DIR}/deploy"

# Tmux configuration
TMUX_CONFIG="${HOME}/.tmux/wheeler-dev.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Pre-flight checks -------------------------------------------------------
pre_flight() {
    if ! command -v tmux &>/dev/null; then
        error "tmux is not installed."
        error "Install it: apt install tmux -y  (or brew install tmux)"
        exit 1
    fi

    # Check tmux version (3.0+ recommended for features)
    local tmux_version
    tmux_version=$(tmux -V | grep -oP '\d+\.\d+' | head -1 || echo "0.0")
    if awk "BEGIN {exit !(${tmux_version} < 3.0)}"; then
        warn "tmux ${tmux_version} detected. 3.0+ recommended for best features."
    fi
}

# --- Create the tmux config --------------------------------------------------
create_tmux_config() {
    mkdir -p "$(dirname "$TMUX_CONFIG")"

    # Create a dedicated tmux config for the dev session
    cat > "$TMUX_CONFIG" <<'TMUXCONF'
# ==============================================================================
# Tmux Configuration — Wheeler AIOps Dev Session
# ==============================================================================

# Set base index to 1 (instead of 0)
set -g base-index 1
set -g pane-base-index 1

# Increase scrollback
set -g history-limit 50000

# Mouse support
set -g mouse on

# True color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Status bar
set -g status-interval 5
set -g status-position top
set -g status-style "bg=#1a1b26,fg=#a9b1d6"

set -g status-left "#[bg=#7aa2f7,fg=#1a1b26,bold] ◆ Wheeler AIOps #[bg=#1a1b26,fg=#7aa2f7] "
set -g status-right "#[bg=#1a1b26,fg=#a9b1d6] %Y-%m-%d %H:%M "

# Window format
set -g window-status-format " #I:#W "
set -g window-status-current-format "#[bg=#7aa2f7,fg=#1a1b26,bold] #I:#W "
set -g window-status-separator ""

# Key bindings
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Split panes
bind | split-window -h
bind - split-window -v

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded"

# Quick navigation
bind 1 select-window -t 1
bind 2 select-window -t 2
bind 3 select-window -t 3
bind 4 select-window -t 4
bind 5 select-window -t 5
bind 6 select-window -t 6

# Pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Synchronize panes (toggle)
bind S setw synchronize-panes \; display "Synchronize panes: #{?synchronize-panes,ON,OFF}"
TMUXCONF

    success "tmux config created: ${TMUX_CONFIG}"
}

# --- Create the session ------------------------------------------------------
create_session() {
    info "Creating tmux session: ${SESSION_NAME}"

    # Start new session (detached) with the first window
    tmux new-session -d -s "$SESSION_NAME" -n "system" -c "$HOME" 2>/dev/null || {
        info "Session ${SESSION_NAME} already exists."
        return 1
    }

    # -- Window 1: System Monitoring --
    # Split into 3 panes
    tmux send-keys -t "${SESSION_NAME}:1.1" "htop" Enter
    tmux split-window -h -t "${SESSION_NAME}:1"
    tmux send-keys -t "${SESSION_NAME}:1.2" "docker stats --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'" Enter
    tmux split-window -v -t "${SESSION_NAME}:1.2"
    tmux send-keys -t "${SESSION_NAME}:1.3" "watch -n 10 'df -h / ; echo \"---\" ; free -h ; echo \"---\" ; docker info --format \"Containers: {{.Containers}} / {{.ContainersRunning}} running\"'" Enter

    # -- Window 2: Logs --
    tmux new-window -t "$SESSION_NAME" -n "logs" -c "${BASE_DIR}/logs"
    tmux send-keys -t "${SESSION_NAME}:2" "tail -f /opt/wheeler/logs/*.log 2>/dev/null || echo 'No log files yet. Waiting...' && sleep 5 && exec tail -f /opt/wheeler/logs/*.log 2>/dev/null" Enter
    # Split for docker logs
    tmux split-window -h -t "${SESSION_NAME}:2"
    tmux send-keys -t "${SESSION_NAME}:2.2" "echo 'Run: docker logs <container> --tail 100 -f' ; echo 'Or use: service-manager.sh logs <service>'" Enter

    # -- Window 3: Hetzner SSH --
    tmux new-window -t "$SESSION_NAME" -n "hetzner" -c "$HOME"
    # Check for SSH config
    if grep -q "Host hetzner\|Host cpx51" ~/.ssh/config 2>/dev/null; then
        tmux send-keys -t "${SESSION_NAME}:3" "ssh hetzner" Enter
    else
        tmux send-keys -t "${SESSION_NAME}:3" "# ssh <user>@<hetzner-ip>  # Add to ~/.ssh/config for convenience" Enter
        tmux send-keys -t "${SESSION_NAME}:3" "echo 'Host: Hetzner CPX51'" Enter
    fi
    tmux split-window -h -t "${SESSION_NAME}:3"
    tmux send-keys -t "${SESSION_NAME}:3.2" "# Connection info:" Enter
    tmux send-keys -t "${SESSION_NAME}:3.2" "echo 'Hetzner CPX51 — Primary AIOps'" Enter
    tmux send-keys -t "${SESSION_NAME}:3.2" "echo 'Tailscale: 100.121.x.x'" Enter

    # -- Window 4: Hostinger SSH --
    tmux new-window -t "$SESSION_NAME" -n "hostinger" -c "$HOME"
    if grep -q "Host hostinger\|Host vps" ~/.ssh/config 2>/dev/null; then
        tmux send-keys -t "${SESSION_NAME}:4" "ssh hostinger" Enter
    else
        tmux send-keys -t "${SESSION_NAME}:4" "# ssh <user>@<hostinger-ip>  # Add to ~/.ssh/config for convenience" Enter
        tmux send-keys -t "${SESSION_NAME}:4" "echo 'Host: Hostinger VPS'" Enter
    fi
    tmux split-window -h -t "${SESSION_NAME}:4"
    tmux send-keys -t "${SESSION_NAME}:4.2" "# Connection info:" Enter
    tmux send-keys -t "${SESSION_NAME}:4.2" "echo 'Hostinger VPS — Edge / Frontend'" Enter
    tmux send-keys -t "${SESSION_NAME}:4.2" "echo 'Tailscale: 100.98.x.x'" Enter

    # -- Window 5: Deploy --
    tmux new-window -t "$SESSION_NAME" -n "deploy" -c "${DEPLOY_DIR}"
    tmux send-keys -t "${SESSION_NAME}:5" "ls -la && echo '---' && echo 'Deploy scripts ready. Available:' && ls *.sh 2>/dev/null" Enter

    # Split into two panes
    tmux split-window -h -t "${SESSION_NAME}:5"
    tmux send-keys -t "${SESSION_NAME}:5.2" "echo 'Common deploy commands:'" Enter
    tmux send-keys -t "${SESSION_NAME}:5.2" "echo '  ./deploy-release.sh prediction-radar main'" Enter
    tmux send-keys -t "${SESSION_NAME}:5.2" "echo '  ./deploy-all.sh --dry-run'" Enter
    tmux send-keys -t "${SESSION_NAME}:5.2" "echo '  ./deploy-release.sh --help'" Enter

    # -- Window 6: Edit --
    tmux new-window -t "$SESSION_NAME" -n "edit" -c "$HOME"
    # Check for common editors
    if command -v nvim &>/dev/null; then
        tmux send-keys -t "${SESSION_NAME}:6" "nvim" Enter
    elif command -v vim &>/dev/null; then
        tmux send-keys -t "${SESSION_NAME}:6" "vim" Enter
    elif command -v nano &>/dev/null; then
        tmux send-keys -t "${SESSION_NAME}:6" "nano" Enter
    else
        tmux send-keys -t "${SESSION_NAME}:6" "echo 'No editor found. Install nvim, vim, or nano.'" Enter
    fi

    # Set the default window to "system"
    tmux select-window -t "${SESSION_NAME}:1"

    success "Session ${SESSION_NAME} created!"
    return 0
}

# --- Attach to session -------------------------------------------------------
attach_session() {
    info "Attaching to session ${SESSION_NAME}..."
    if [[ -z "${TMUX:-}" ]]; then
        tmux attach-session -t "$SESSION_NAME"
    else
        info "Already inside a tmux session (${TMUX})."
        info "Use 'tmux switch -t ${SESSION_NAME}' to switch."
        info "Or detach first with Ctrl+a d."
    fi
}

# --- Kill session ------------------------------------------------------------
kill_session() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        warn "Killing session ${SESSION_NAME}..."
        tmux kill-session -t "$SESSION_NAME"
        success "Session killed."
    else
        info "Session ${SESSION_NAME} does not exist."
    fi
}

# --- Print session info ------------------------------------------------------
show_info() {
    echo ""
    echo "=============================================="
    echo "  Wheeler AIOps — Tmux Dev Environment"
    echo "=============================================="
    echo ""
    echo "  Session: ${SESSION_NAME}"
    echo ""
    echo "  Windows:"
    echo "    1: system    — htop, docker stats, disk/memory"
    echo "    2: logs      — tail -f /opt/wheeler/logs/*.log"
    echo "    3: hetzner   — SSH to Hetzner CPX51"
    echo "    4: hostinger — SSH to Hostinger VPS"
    echo "    5: deploy    — deploy scripts"
    echo "    6: edit      — code editor"
    echo ""
    echo "  Commands:"
    echo "    Start:   $0"
    echo "    Attach:  $0 --attach"
    echo "    Detach:  Ctrl+a d"
    echo "    Kill:    $0 --kill"
    echo ""

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        success "Session is currently running."
        echo "  Attach with: $0 --attach"
    else
        info "Session is not running."
        echo "  Start with:  $0"
    fi
    echo ""
}

# --- Main --------------------------------------------------------------------
main() {
    local DO_ATTACH=false
    local DO_KILL=false
    local DO_INFO=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --attach|-a)
                DO_ATTACH=true
                shift
                ;;
            --kill)
                DO_KILL=true
                shift
                ;;
            --session|-s)
                SESSION_NAME="$2"
                shift 2
                ;;
            --info)
                DO_INFO=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --attach          Attach to running session"
                echo "  --kill            Kill the session"
                echo "  --session <name>  Session name (default: wheeler-dev)"
                echo "  --info            Show session info"
                echo ""
                echo "Examples:"
                echo "  $0                       # Create or attach to session"
                echo "  $0 --attach              # Attach to existing session"
                echo "  $0 --session ops --kill  # Kill a specific session"
                echo "  $0 --info                # Show session details"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    pre_flight

    if [[ "$DO_KILL" == "true" ]]; then
        kill_session
        exit 0
    fi

    if [[ "$DO_INFO" == "true" ]]; then
        show_info
        exit 0
    fi

    # Create tmux config
    create_tmux_config

    # Create session if it doesn't exist
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        create_session || true  # If creation fails, session already exists
    else
        info "Session ${SESSION_NAME} already exists."
    fi

    # Attach
    if [[ "$DO_ATTACH" == "true" ]]; then
        attach_session
    elif [[ -z "${TMUX:-}" ]]; then
        # Not inside tmux — ask if they want to attach
        echo ""
        info "Session ${SESSION_NAME} is ready."
        echo "  Attach now:  $0 --attach"
        echo "  Or later:    tmux attach -t ${SESSION_NAME}"
        echo ""
    else
        info "Session ${SESSION_NAME} is running in the background."
        info "Switch to it: tmux switch -t ${SESSION_NAME}"
    fi
}

main "$@"
