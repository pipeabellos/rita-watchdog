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
│  rita-watchdog.timer (every 5 min)                      │
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
| ISP routing issues | WiFi UP but can't reach UptimeRobot → Power alert (false alarm) |

**Note**: A Power alert doesn't always mean power loss. It means heartbeats couldn't be delivered through ANY interface. See [Troubleshooting](#important-power-monitor-false-alarms) for details.

## Requirements

- Raspberry Pi with WiFi (tested on Pi Zero 2W)
- USB Ethernet adapter connected to 4G modem
- UptimeRobot account (free tier works) with 3 heartbeat monitors

## Network Setup (Important!)

**The 4G modem MUST be on a different subnet than your home WiFi network.**

If both networks use the same subnet (e.g., both 192.168.1.x), routing will break and failover won't work properly.

### Correct Setup

| Interface | Network | Gateway | Purpose |
|-----------|---------|---------|---------|
| wlan0 (WiFi) | 192.168.**1**.x | 192.168.**1**.1 | Home network |
| eth0 (4G) | 192.168.**2**.x | 192.168.**2**.1 | 4G backup |

### How to Configure

1. Access your 4G modem's admin panel (usually http://192.168.1.1 when connected via eth0)
2. Find LAN/DHCP settings
3. Change the LAN IP from `192.168.1.1` to `192.168.2.1`
4. Save and reconnect

### Verify Setup

```bash
# Check routing table - should show DIFFERENT subnets
ip route show

# Expected output:
# default via 192.168.2.1 dev eth0 ... metric 100
# default via 192.168.1.1 dev wlan0 ... metric 200
# 192.168.1.0/24 dev wlan0 ...
# 192.168.2.0/24 dev eth0 ...
```

If both routes show the same gateway (e.g., both 192.168.1.1), fix the 4G modem's LAN subnet.

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
     - Power Monitor (10 min interval)
     - WiFi Monitor (10 min interval)
     - 4G Monitor (10 min interval)
   - Copy each heartbeat URL into your `config.env`
   - Note: Script sends heartbeats every 5 min, so 10 min interval = alert after 2 missed beats

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
| WiFi UP but heartbeat fails | ISP can't reach UptimeRobot | Wait for ISP to fix routing; 4G backup should help |
| WiFi UP but heartbeat fails | IPv6 timeout | Ensure `-4` flag in curl commands |
| All heartbeats fail | No network connectivity | Check both interfaces manually |
| Timer not running | systemd issue | `sudo systemctl restart rita-watchdog.timer` |

### Important: Power Monitor False Alarms

The Power monitor going down does NOT always mean power loss. It means **no heartbeats could be delivered**.

**Scenario**: WiFi shows "UP" but Power monitor goes down
- Connectivity check passes (can reach Google)
- But heartbeat fails (can't reach UptimeRobot)
- If 4G is also down, ALL heartbeats fail → Power monitor alert

**Why this happens**: The connectivity check tests `connectivitycheck.gstatic.com` (Google), but heartbeats go to `heartbeat.uptimerobot.com`. Your ISP may have routing issues to UptimeRobot while Google works fine.

**How to verify**: Check logs for:
```bash
grep -a "heartbeat.*failed" /var/log/rita-watchdog.log | tail -20
```

Look for patterns like:
```
WiFi is UP (check: http)
Power heartbeat via eth0 failed (curl: 7)
Power heartbeat via wlan0 failed (curl: 28)
Warning: ALL attempts to send Power heartbeat FAILED
```

This means WiFi connectivity check passed but heartbeat delivery failed.

## License

MIT
