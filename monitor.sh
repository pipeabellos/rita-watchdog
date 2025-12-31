#!/bin/bash
# Rita Watchdog - Home Network Monitor
# Monitors WiFi, 4G, and power via UptimeRobot heartbeats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOG_FILE="/var/log/rita-watchdog.log"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE" >&2
    exit 1
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Send heartbeat via any available interface
send_heartbeat() {
    local url="$1"
    local name="$2"

    # Try 4G first (fast timeout), then WiFi, then any route
    if curl --interface "$FOURG_INTERFACE" -s -o /dev/null -m 10 "$url" 2>/dev/null; then
        log "$name heartbeat sent via $FOURG_INTERFACE"
        return 0
    elif curl --interface "$WIFI_INTERFACE" -s -o /dev/null -m 10 "$url" 2>/dev/null; then
        log "$name heartbeat sent via $WIFI_INTERFACE (4G fallback)"
        return 0
    elif curl -s -o /dev/null -m 10 "$url" 2>/dev/null; then
        log "$name heartbeat sent via auto-route (both interfaces failed)"
        return 0
    else
        log "Warning: Failed to send $name heartbeat (no connectivity)"
        return 1
    fi
}

# Check connectivity on specific interface
check_interface() {
    local interface="$1"
    if ping -c 2 -W 5 -I "$interface" "$CHECK_HOST" > /dev/null 2>&1; then
        return 0  # Interface has internet
    else
        return 1  # Interface down
    fi
}

# Try to reconnect WiFi
reconnect_wifi() {
    log "Attempting WiFi reconnect..."

    # Check if interface is down
    if ! ip link show "$WIFI_INTERFACE" | grep -q "state UP"; then
        log "WiFi interface is down, bringing it up..."
        ip link set "$WIFI_INTERFACE" up 2>/dev/null || true
        sleep 2
    fi

    # Try to activate the connection
    if nmcli connection up "$WIFI_CONNECTION_NAME" 2>/dev/null; then
        log "WiFi reconnect successful"
        sleep 5  # Wait for connection to stabilize
        return 0
    else
        log "WiFi reconnect failed"
        return 1
    fi
}

main() {
    log "=== Starting monitoring check ==="

    local wifi_up=false
    local fourg_up=false

    # Check WiFi connectivity
    if check_interface "$WIFI_INTERFACE"; then
        log "WiFi is UP"
        wifi_up=true
    else
        log "WiFi is DOWN - attempting reconnect"
        if reconnect_wifi && check_interface "$WIFI_INTERFACE"; then
            log "WiFi recovered after reconnect"
            wifi_up=true
        else
            log "WiFi still DOWN"
        fi
    fi

    # Check 4G connectivity
    if check_interface "$FOURG_INTERFACE"; then
        log "4G is UP"
        fourg_up=true
    else
        log "4G is DOWN"
    fi

    # Send POWER heartbeat (always try - proves Pi is alive)
    if [ "$fourg_up" = true ] || [ "$wifi_up" = true ]; then
        send_heartbeat "$POWER_HEARTBEAT_URL" "Power"
    else
        log "ERROR: No internet connection available"
    fi

    # Send WIFI heartbeat (only if WiFi is working)
    if [ "$wifi_up" = true ]; then
        send_heartbeat "$WIFI_HEARTBEAT_URL" "WiFi"
    else
        log "WiFi is DOWN - skipping WiFi heartbeat"
    fi

    # Send 4G heartbeat (only if 4G is working)
    if [ "$fourg_up" = true ]; then
        send_heartbeat "$FOURG_HEARTBEAT_URL" "4G"
    else
        log "4G is DOWN - skipping 4G heartbeat"
    fi

    log "=== Check complete ==="
}

main "$@"
