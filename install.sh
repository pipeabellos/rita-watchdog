#!/bin/bash
# Rita Watchdog Installation Script
# Run this on the Raspberry Pi

set -euo pipefail

INSTALL_DIR="/opt/rita-watchdog"
SERVICE_NAME="rita-watchdog"

echo "=== Rita Watchdog Installer ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y curl

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"

# Copy files
echo "Copying files..."
cp monitor.sh "$INSTALL_DIR/"
cp config.env "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/monitor.sh"

# Create log file
touch /var/log/rita-watchdog.log
chmod 644 /var/log/rita-watchdog.log

# Install systemd service
echo "Installing systemd service..."
cp rita-watchdog.service /etc/systemd/system/
cp rita-watchdog.timer /etc/systemd/system/

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable rita-watchdog.timer
systemctl start rita-watchdog.timer

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Monitoring is now active!"
echo ""
echo "Commands:"
echo "  Status:  systemctl status rita-watchdog.timer"
echo "  Logs:    tail -f /var/log/rita-watchdog.log"
echo "  Test:    sudo /opt/rita-watchdog/monitor.sh"
