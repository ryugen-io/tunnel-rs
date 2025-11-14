#!/usr/bin/env bash
set -euo pipefail

# rustunnl - Universal SSH Reverse Tunnel Manager
# XDG-compliant tunnel manager with autossh

readonly SCRIPT_NAME="rustunnl"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$SCRIPT_NAME"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$SCRIPT_NAME"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Ensure directories exist
ensure_dirs() {
    mkdir -p "$CONFIG_DIR" "$STATE_DIR"
}

# List all configured tunnels
list_tunnels() {
    log_info "Configured tunnels:"
    if [ -z "$(ls -A "$CONFIG_DIR"/*.env 2>/dev/null)" ]; then
        echo "  No tunnels configured yet."
        echo "  Create a config in: $CONFIG_DIR/<name>.env"
        return 0
    fi

    for config_file in "$CONFIG_DIR"/*.env; do
        local name
        name=$(basename "$config_file" .env)
        local desc=""
        if [ -f "$config_file" ]; then
            desc=$(grep "^DESCRIPTION=" "$config_file" 2>/dev/null | cut -d'"' -f2 || echo "")
        fi
        if is_tunnel_running "$name"; then
            echo -e "  ${GREEN}●${NC} $name ${BLUE}(running)${NC}"
        else
            echo -e "  ${RED}○${NC} $name"
        fi
        if [ -n "$desc" ]; then
            echo "    $desc"
        fi
    done
}

# Check if tunnel is running
is_tunnel_running() {
    local name="$1"
    local pid_file="$STATE_DIR/$name.pid"

    if [ ! -f "$pid_file" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$pid_file")
    if ! kill -0 "$pid" 2>/dev/null; then
        # PID file exists but process is dead - clean up
        rm -f "$pid_file"
        return 1
    fi

    return 0
}

# Get tunnel status
status_tunnel() {
    local name="$1"
    local pid_file="$STATE_DIR/$name.pid"
    local log_file="$STATE_DIR/$name.log"

    echo -e "${BLUE}Tunnel:${NC} $name"

    if is_tunnel_running "$name"; then
        local pid
        pid=$(cat "$pid_file")
        log_success "Running (PID: $pid)"

        # Show last few log entries
        if [ -f "$log_file" ]; then
            echo -e "\n${BLUE}Recent logs:${NC}"
            tail -n 5 "$log_file" | sed 's/^/  /'
        fi
    else
        log_warn "Not running"
    fi
}

# Start tunnel
start_tunnel() {
    local name="$1"
    local config_file="$CONFIG_DIR/$name.env"
    local pid_file="$STATE_DIR/$name.pid"
    local log_file="$STATE_DIR/$name.log"

    if [ ! -f "$config_file" ]; then
        log_error "Config not found: $config_file"
        return 1
    fi

    if is_tunnel_running "$name"; then
        log_warn "Tunnel '$name' is already running"
        return 0
    fi

    # Source config
    # shellcheck source=/dev/null
    source "$config_file"

    # Validate required variables
    if [ -z "${TARGET_HOST:-}" ]; then
        log_error "TARGET_HOST not set in $config_file"
        return 1
    fi
    if [ -z "${SSH_KEY:-}" ]; then
        log_error "SSH_KEY not set in $config_file"
        return 1
    fi
    if [ -z "${REMOTE_PORT:-}" ] || [ -z "${LOCAL_TARGET:-}" ]; then
        log_error "REMOTE_PORT or LOCAL_TARGET not set in $config_file"
        return 1
    fi

    # Expand SSH_KEY path
    SSH_KEY=$(eval echo "$SSH_KEY")

    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH key not found: $SSH_KEY"
        return 1
    fi

    log_info "Starting tunnel '$name'..."
    log_info "  Remote: $TARGET_HOST:$REMOTE_PORT"
    log_info "  Local:  $LOCAL_TARGET"

    # Start autossh in background
    autossh -M 0 -N -f \
        -o "ServerAliveInterval=${KEEPALIVE_INTERVAL:-30}" \
        -o "ServerAliveCountMax=${KEEPALIVE_COUNT_MAX:-3}" \
        -i "$SSH_KEY" \
        -R "${REMOTE_PORT}:${LOCAL_TARGET}" \
        "$TARGET_HOST" \
        >> "$log_file" 2>&1

    # Get PID of autossh
    sleep 1
    local pid
    pid=$(pgrep -f "autossh.*${REMOTE_PORT}:${LOCAL_TARGET}" | head -1)

    if [ -z "$pid" ]; then
        log_error "Failed to start tunnel"
        if [ -f "$log_file" ]; then
            echo -e "\n${RED}Last log entries:${NC}"
            tail -n 10 "$log_file"
        fi
        return 1
    fi

    echo "$pid" > "$pid_file"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tunnel started (PID: $pid)" >> "$log_file"

    log_success "Tunnel '$name' started (PID: $pid)"
}

# Stop tunnel
stop_tunnel() {
    local name="$1"
    local pid_file="$STATE_DIR/$name.pid"
    local log_file="$STATE_DIR/$name.log"

    if ! is_tunnel_running "$name"; then
        log_warn "Tunnel '$name' is not running"
        # Clean up any stray processes anyway
        pkill -f "autossh.*$name" 2>/dev/null || true
        return 0
    fi

    local pid
    pid=$(cat "$pid_file")
    log_info "Stopping tunnel '$name' (PID: $pid)..."

    # Kill child processes first
    pkill -P "$pid" 2>/dev/null || true

    # Kill main process
    kill "$pid" 2>/dev/null || true

    # Wait a bit
    sleep 1

    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi

    # Fallback: kill by pattern
    pkill -f "autossh.*$name" 2>/dev/null || true

    # Clean up PID file
    rm -f "$pid_file"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tunnel stopped" >> "$log_file"

    log_success "Tunnel '$name' stopped"
}

# Restart tunnel
restart_tunnel() {
    local name="$1"
    log_info "Restarting tunnel '$name'..."
    stop_tunnel "$name"
    sleep 1
    start_tunnel "$name"
}

# Main function
main() {
    ensure_dirs

    local command="${1:-}"
    local name="${2:-}"

    case "$command" in
        start)
            if [ -z "$name" ]; then
                log_error "Usage: $SCRIPT_NAME start <name>"
                exit 1
            fi
            start_tunnel "$name"
            ;;
        stop)
            if [ -z "$name" ]; then
                log_error "Usage: $SCRIPT_NAME stop <name>"
                exit 1
            fi
            stop_tunnel "$name"
            ;;
        restart)
            if [ -z "$name" ]; then
                log_error "Usage: $SCRIPT_NAME restart <name>"
                exit 1
            fi
            restart_tunnel "$name"
            ;;
        status)
            if [ -z "$name" ]; then
                # Show all tunnels
                list_tunnels
            else
                status_tunnel "$name"
            fi
            ;;
        list)
            list_tunnels
            ;;
        *)
            echo "Usage: $SCRIPT_NAME {start|stop|restart|status|list} [name]"
            echo ""
            echo "Commands:"
            echo "  start <name>    Start tunnel"
            echo "  stop <name>     Stop tunnel (complete cleanup)"
            echo "  restart <name>  Restart tunnel"
            echo "  status [name]   Show status (all or specific)"
            echo "  list            List all configured tunnels"
            echo ""
            echo "Config directory: $CONFIG_DIR"
            echo "State directory:  $STATE_DIR"
            exit 1
            ;;
    esac
}

main "$@"
