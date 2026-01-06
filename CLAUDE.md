# Rita Watchdog - Claude Instructions

## Project Overview

Home network monitoring system running on a Raspberry Pi Zero 2W. Sends heartbeats to UptimeRobot to monitor:
- **Power** - Pi is alive and has connectivity
- **WiFi** - Home network is working
- **4G** - Backup 4G modem is working

## Hardware Setup

- **Raspberry Pi Zero 2W** located at home
- **wlan0** - WiFi connected to home network ("ALTA LOMA - 2.4G")
- **eth0** - USB Ethernet adapter connected to 4G modem

## File Structure

```
~/rita-watchdog/          # Git repo on Pi (and local Mac)
├── monitor.sh            # Main monitoring script (runs every 60s)
├── config.env            # Heartbeat URLs and settings (NOT in git)
├── config.env.example    # Template for config
├── rita-watchdog.service # systemd service
├── rita-watchdog.timer   # systemd timer (triggers every 60s)
├── install.sh            # Legacy installer (not needed with symlink)
└── README.md

/opt/rita-watchdog/       # Symlink to ~/rita-watchdog (auto-updates on git pull)
/var/log/rita-watchdog.log # Log file
```

## Deployment

The Pi uses a **symlink** from `/opt/rita-watchdog` to `~/rita-watchdog`, so:
- `git pull` in `~/rita-watchdog` automatically updates the running version
- No need to copy files or run install scripts

To deploy changes:
```bash
# On Mac: commit and push
git add -A && git commit -m "message" && git push

# On Pi: pull
cd ~/rita-watchdog && git pull
```

## SSH Access

```bash
ssh pipeabellos@ritawatch
# or
ssh pipeabellos@<pi-ip-address>
```

## Key Technical Details

### IPv4 Forcing
All curl commands use `-4` flag to force IPv4. IPv6 causes timeouts because home networks often don't have proper IPv6 routing to external services.

### Connectivity Checks
Uses HTTP requests (not ICMP ping) to verify connectivity:
1. HTTP to `connectivitycheck.gstatic.com/generate_204`
2. HTTPS to `1.1.1.1` (bypasses DNS)
3. Fallback to ping `8.8.8.8`

This is more reliable because ping can succeed when HTTP fails (different protocols, routing).

### Heartbeat Logic
```
1. Check WiFi (HTTP check via wlan0) → wifi_up=true/false
2. Check 4G (HTTP check via eth0) → fourg_up=true/false
3. Send Power heartbeat (if any connection up) - tries 4G → WiFi → auto
4. Send WiFi heartbeat (only if wifi_up)
5. Send 4G heartbeat (only if fourg_up)
```

## Debugging Commands

```bash
# Check timer status
systemctl status rita-watchdog.timer

# View recent logs
tail -50 /var/log/rita-watchdog.log

# If log has binary content (corruption)
strings /var/log/rita-watchdog.log | tail -50

# Search for failures
strings /var/log/rita-watchdog.log | grep -E "(Warning|Failed|DOWN|ERROR)" | tail -20

# Run monitor manually
sudo /opt/rita-watchdog/monitor.sh

# Test WiFi connectivity manually
curl -4 --interface wlan0 -v -m 10 "https://heartbeat.uptimerobot.com" 2>&1 | head -20

# Check interfaces
ip addr show wlan0
ip addr show eth0
```

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| WiFi UP but heartbeat fails | IPv6 timeout | Ensure `-4` flag in all curl commands |
| "no connectivity" despite WiFi UP | HTTP works but HTTPS to uptimerobot fails | Check DNS, try manual curl test |
| Log shows binary content | Corrupted from crash | Use `strings` command to read |
| All monitors down but Pi is up | Network issue between Pi and UptimeRobot | Check if curl can reach uptimerobot |
| Timer not running | systemd issue | `sudo systemctl restart rita-watchdog.timer` |

## Curl Exit Codes

When heartbeats fail, logs show exit codes:
- `6` = DNS resolution failed
- `7` = Connection refused
- `28` = Timeout
- `35` = SSL/TLS error

## UptimeRobot Settings

- **Power Monitor**: 5 min check interval (detects prolonged outages)
- **WiFi Monitor**: 2 min check interval
- **4G Monitor**: 2 min check interval

## Config File Location

The `config.env` file contains heartbeat URLs and is NOT in git (sensitive).
Location on Pi: `~/rita-watchdog/config.env`

If it gets deleted, recreate from `config.env.example` and get URLs from UptimeRobot dashboard.
