# Rita Watchdog

Home network monitoring system for Raspberry Pi. Monitors WiFi, 4G, and power outages via UptimeRobot heartbeats.

## Features

- **WiFi Monitoring**: Alerts when home WiFi/internet goes down
- **4G Monitoring**: Alerts when 4G backup connection goes down
- **Power Monitoring**: Alerts when Pi loses power
- **Auto-reconnect**: Automatically tries to reconnect WiFi if it drops
- **Failover**: Uses available connection to send alerts

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Raspberry Pi Zero 2W                   │
├─────────────────────────────────────────────────────────┤
│  wlan0 (WiFi) ───► Home Network                         │
│  eth0 (Ethernet) ─► 4G Modem (USB adapter)              │
├─────────────────────────────────────────────────────────┤
│  rita-watchdog.timer (every 60s)                        │
│  ├── Check WiFi connectivity (HTTP check via wlan0)     │
│  ├── Check 4G connectivity (HTTP check via eth0)        │
│  ├── Send POWER heartbeat (tries 4G → WiFi → auto)      │
│  ├── Send WIFI heartbeat (if WiFi up)                   │
│  └── Send 4G heartbeat (if 4G up)                       │
└─────────────────────────────────────────────────────────┘
```

### Connectivity Checks

The script uses HTTP requests (not ICMP ping) to verify connectivity, which is more reliable:

1. **Primary**: HTTP to `connectivitycheck.gstatic.com` (Google's 204 endpoint)
2. **Fallback**: HTTPS to `1.1.1.1` (Cloudflare, bypasses DNS)
3. **Last resort**: ICMP ping to `8.8.8.8`

All requests use `-4` flag to force IPv4 (IPv6 often fails on home networks).

## How Alerts Work

| Scenario | What Happens |
|----------|--------------|
| WiFi down, 4G up | WiFi heartbeat stops → UptimeRobot alerts |
| 4G down, WiFi up | 4G heartbeat stops → UptimeRobot alerts |
| Both down | Power heartbeat stops → UptimeRobot alerts |
| Pi loses power | All heartbeats stop → UptimeRobot alerts |

## Requirements

- Raspberry Pi with WiFi (tested on Pi Zero 2W)
- USB Ethernet adapter connected to 4G modem
- UptimeRobot account (free tier works) with 3 heartbeat monitors

## Installation

1. Clone this repo on your Pi:
   ```bash
   cd ~
   git clone https://github.com/pipeabellos/rita-watchdog.git
   cd rita-watchdog
   ```

2. Create your config file:
   ```bash
   cp config.env.example config.env
   nano config.env
   ```

3. Set up UptimeRobot:
   - Create 3 "Heartbeat" monitors at [uptimerobot.com](https://uptimerobot.com):
     - Power Monitor (5 min interval)
     - WiFi Monitor (2 min interval)
     - 4G Monitor (2 min interval)
   - Copy each heartbeat URL into your `config.env`

4. Update WiFi connection name:
   ```bash
   # Find your WiFi connection name
   nmcli connection show
   # Update WIFI_CONNECTION_NAME in config.env
   ```

5. Create symlink and install systemd services:
   ```bash
   # Symlink so git pull auto-updates the running version
   sudo ln -s ~/rita-watchdog /opt/rita-watchdog

   # Make script executable
   chmod +x monitor.sh

   # Install systemd timer
   sudo cp rita-watchdog.service /etc/systemd/system/
   sudo cp rita-watchdog.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable rita-watchdog.timer
   sudo systemctl start rita-watchdog.timer
   ```

## Usage

```bash
# Check timer status
systemctl status rita-watchdog.timer

# View logs
tail -f /var/log/rita-watchdog.log

# Run manually
sudo /opt/rita-watchdog/monitor.sh

# Stop monitoring
sudo systemctl stop rita-watchdog.timer

# Start monitoring
sudo systemctl start rita-watchdog.timer
```

## Configuration

Edit `config.env` (or `/opt/rita-watchdog/config.env` after install):

| Variable | Description |
|----------|-------------|
| `POWER_HEARTBEAT_URL` | UptimeRobot heartbeat for power monitoring |
| `WIFI_HEARTBEAT_URL` | UptimeRobot heartbeat for WiFi monitoring |
| `FOURG_HEARTBEAT_URL` | UptimeRobot heartbeat for 4G monitoring |
| `WIFI_INTERFACE` | WiFi interface (default: wlan0) |
| `FOURG_INTERFACE` | 4G/Ethernet interface (default: eth0) |
| `WIFI_CONNECTION_NAME` | NetworkManager connection name for WiFi |
| `CHECK_HOST` | Host to ping for connectivity check |

## Updating

With the symlink setup, updates are simple:

```bash
cd ~/rita-watchdog
git pull
```

The running version is automatically updated (no reinstall needed).

## Troubleshooting

### Viewing logs
```bash
# Recent logs
tail -50 /var/log/rita-watchdog.log

# Watch live
tail -f /var/log/rita-watchdog.log

# Search for failures
grep -a "Warning\|Failed\|DOWN" /var/log/rita-watchdog.log | tail -20
```

### Log has binary content
If `grep` says "binary file matches", use:
```bash
strings /var/log/rita-watchdog.log | grep "pattern"
```

### Curl exit codes
When heartbeats fail, the log shows curl exit codes:
- `6` = DNS resolution failed
- `7` = Connection refused
- `28` = Timeout
- `35` = SSL/TLS error

### Common issues

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| WiFi UP but heartbeat fails | IPv6 timeout | Ensure `-4` flag in curl commands |
| All heartbeats fail | No network connectivity | Check both interfaces manually |
| Timer not running | systemd issue | `sudo systemctl restart rita-watchdog.timer` |

## License

MIT
