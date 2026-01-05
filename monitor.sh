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
    local curl_exit_code

    # Try 4G first (fast timeout), then WiFi, then any route
    curl --interface "$FOURG_INTERFACE" -s -o /dev/null -m 10 "$url" 2>/dev/null
    curl_exit_code=$?
    if [ $curl_exit_code -eq 0 ]; then
        log "$name heartbeat sent via $FOURG_INTERFACE"
        return 0
    fi

    curl --interface "$WIFI_INTERFACE" -s -o /dev/null -m 10 "$url" 2>/dev/null
    curl_exit_code=$?
    if [ $curl_exit_code -eq 0 ]; then
        log "$name heartbeat sent via $WIFI_INTERFACE"
        return 0
    fi

    curl -s -o /dev/null -m 10 "$url" 2>/dev/null
    curl_exit_code=$?
    if [ $curl_exit_code -eq 0 ]; then
        log "$name heartbeat sent via auto-route"
        return 0
    fi

    # Log failure with curl exit code for debugging
    # Exit codes: 6=DNS fail, 7=connect fail, 28=timeout, 35=SSL error
    log "Warning: Failed to send $name heartbeat (curl exit: $curl_exit_code)"
    return 1
}

# Check connectivity on specific interface using HTTP (more reliable than ping)
check_interface() {
    local interface="$1"

    # Try HTTP check first (proves DNS + TCP + HTTP all work)
    # Using http (not https) to a known endpoint for speed
    if curl --interface "$interface" -s -o /dev/null -m 5 -w "%{http_code}" "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null | grep -q "204"; then
        return 0  # Full HTTP connectivity works
    fi

    # Fallback to HTTPS check (in case HTTP is blocked)
    if curl --interface "$interface" -s -o /dev/null -m 5 "https://1.1.1.1" 2>/dev/null; then
        return 0  # HTTPS to IP works (bypasses DNS)
    fi

    # Last resort: ping (ICMP might work when HTTP doesn't, but less useful)
    if ping -c 2 -W 3 -I "$interface" "$CHECK_HOST" > /dev/null 2>&1; then
        log "Warning: $interface ping works but HTTP failed - connectivity may be degraded"
        return 0  # Partial connectivity
    fi

    return 1  # Interface down
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
