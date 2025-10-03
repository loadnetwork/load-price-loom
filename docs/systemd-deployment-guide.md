# Systemd Deployment Guide

Complete guide for deploying the Price Oracle Bot as a systemd service on Ubuntu/Debian servers.

## Prerequisites

- Ubuntu/Debian server with systemd
- Node.js installed (`node` available at `/usr/bin/node`)
- `jq` installed (`sudo apt install jq`)
- Oracle bot repository cloned to `/home/reth-node/code/load-price-loom`
- `keys.json` file with operator private keys in the project root

---

## Step 1: Prepare the Environment

```bash
# Navigate to your project
cd /home/reth-node/code/load-price-loom

# Create logs directory
sudo mkdir -p /var/log/price-oracle-bot
sudo chown reth-node:reth-node /var/log/price-oracle-bot

# Create environment files directory
mkdir -p ~/.config/price-oracle-bot

# Create env file for AR/USD feed
cat > ~/.config/price-oracle-bot/ar-usd.env << EOF
RPC_URL=https://alphanet.load.network
ORACLE=0x8A0ffF4C118767c818C9F8a30c39E8F9bB36CEd5
FEED_DESC=ar/usd-testv1
INTERVAL=30000
PRICE_BASE=6
PRIVATE_KEYS_JSON=$(cat keys.json | jq -c)
EOF

# Create env file for AR/bytes feed
cat > ~/.config/price-oracle-bot/ar-bytes.env << EOF
RPC_URL=https://alphanet.load.network
ORACLE=0x8A0ffF4C118767c818C9F8a30c39E8F9bB36CEd5
FEED_DESC=ar/bytes-testv1
INTERVAL=30000
PRICE_BASE=1.5e-9
PRIVATE_KEYS_JSON=$(cat keys.json | jq -c)
EOF

# Secure the env files (important!)
chmod 600 ~/.config/price-oracle-bot/*.env

# Verify env files were created correctly
ls -la ~/.config/price-oracle-bot/
echo "AR/USD env file:"
head -3 ~/.config/price-oracle-bot/ar-usd.env
```

---

## Step 2: Create Systemd Service Template

```bash
sudo tee /etc/systemd/system/price-oracle-bot@.service << 'EOF'
[Unit]
Description=Price Oracle Bot - %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=reth-node
Group=reth-node
WorkingDirectory=/home/reth-node/code/load-price-loom

# Load environment from instance-specific file
EnvironmentFile=/home/reth-node/.config/price-oracle-bot/%i.env

# Execute the bot
ExecStart=/usr/bin/node scripts/bot/operators-bot.mjs \
  --rpc ${RPC_URL} \
  --oracle ${ORACLE} \
  --feedDesc ${FEED_DESC} \
  --interval ${INTERVAL} \
  --priceBase ${PRICE_BASE}

# Restart policy
Restart=always
RestartSec=10
StartLimitInterval=200
StartLimitBurst=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/var/log/price-oracle-bot

# Logging
StandardOutput=append:/var/log/price-oracle-bot/%i.log
StandardError=append:/var/log/price-oracle-bot/%i.error.log
SyslogIdentifier=oracle-bot-%i

# Resource limits (optional)
LimitNOFILE=65536
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF
```

---

## Step 3: Enable and Start Services

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Start both feed bots
sudo systemctl start price-oracle-bot@ar-usd
sudo systemctl start price-oracle-bot@ar-bytes

# Check status
sudo systemctl status price-oracle-bot@ar-usd
sudo systemctl status price-oracle-bot@ar-bytes

# Enable auto-start on boot
sudo systemctl enable price-oracle-bot@ar-usd
sudo systemctl enable price-oracle-bot@ar-bytes

# Verify they're enabled
sudo systemctl is-enabled price-oracle-bot@ar-usd
sudo systemctl is-enabled price-oracle-bot@ar-bytes
```

---

## Verification & Monitoring

```bash
# List all running oracle bot services
sudo systemctl list-units 'price-oracle-bot@*'

# Follow live logs (Ctrl+C to exit)
sudo journalctl -u price-oracle-bot@ar-usd -f

# Check last 100 lines
sudo journalctl -u price-oracle-bot@ar-usd -n 100

# Check both bots at once
sudo journalctl -f -u price-oracle-bot@ar-usd -u price-oracle-bot@ar-bytes

# View log files directly
tail -f /var/log/price-oracle-bot/ar-usd.log
tail -f /var/log/price-oracle-bot/ar-bytes.log
```

---

## Common Operations

### Control Services

```bash
# Restart a bot
sudo systemctl restart price-oracle-bot@ar-usd

# Stop a bot
sudo systemctl stop price-oracle-bot@ar-usd

# Start a bot
sudo systemctl start price-oracle-bot@ar-usd

# Restart all bots
sudo systemctl restart 'price-oracle-bot@*'

# Stop all bots
sudo systemctl stop 'price-oracle-bot@*'
```

### Check Status

```bash
# Check if running
sudo systemctl is-active price-oracle-bot@ar-usd

# Check if enabled for boot
sudo systemctl is-enabled price-oracle-bot@ar-usd

# View service configuration
sudo systemctl cat price-oracle-bot@ar-usd

# Show service properties
sudo systemctl show price-oracle-bot@ar-usd
```

### View Logs

```bash
# Follow live logs
sudo journalctl -u price-oracle-bot@ar-usd -f

# Last 100 lines
sudo journalctl -u price-oracle-bot@ar-usd -n 100

# Logs from last hour
sudo journalctl -u price-oracle-bot@ar-usd --since "1 hour ago"

# Today's logs
sudo journalctl -u price-oracle-bot@ar-usd --since today

# Between timestamps
sudo journalctl -u price-oracle-bot@ar-usd --since "2025-10-03 10:00:00" --until "2025-10-03 11:00:00"

# Show only errors
sudo journalctl -u price-oracle-bot@ar-usd -p err

# Export logs to file
sudo journalctl -u price-oracle-bot@ar-usd --since today > oracle-bot-logs.txt

# Check log disk usage
sudo journalctl --disk-usage
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check detailed error messages
sudo journalctl -xe -u price-oracle-bot@ar-usd

# Verify service file is valid
sudo systemd-analyze verify /etc/systemd/system/price-oracle-bot@.service

# Check if Node.js path is correct
which node  # Should be /usr/bin/node

# If node is in different location, update ExecStart in service file
```

### Check Environment Variables

```bash
# Verify environment file is readable
cat ~/.config/price-oracle-bot/ar-usd.env

# Check permissions
ls -la ~/.config/price-oracle-bot/

# Check if PRIVATE_KEYS_JSON is valid JSON
cat ~/.config/price-oracle-bot/ar-usd.env | grep PRIVATE_KEYS_JSON | cut -d= -f2- | jq length
```

### Test Running Manually

```bash
cd /home/reth-node/code/load-price-loom
source ~/.config/price-oracle-bot/ar-usd.env
node scripts/bot/operators-bot.mjs \
  --rpc $RPC_URL \
  --oracle $ORACLE \
  --feedDesc $FEED_DESC \
  --interval $INTERVAL \
  --priceBase $PRICE_BASE
```

### Service Failed After Update

```bash
# Reload service file after editing
sudo systemctl daemon-reload
sudo systemctl restart price-oracle-bot@ar-usd

# Check why service failed
sudo systemctl status price-oracle-bot@ar-usd -l --no-pager
```

---

## Log Rotation Setup

Prevent logs from filling up disk:

```bash
# Create logrotate config
sudo tee /etc/logrotate.d/price-oracle-bot << 'EOF'
/var/log/price-oracle-bot/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 reth-node reth-node
    sharedscripts
    postrotate
        systemctl reload price-oracle-bot@* 2>/dev/null || true
    endscript
}
EOF

# Test logrotate config
sudo logrotate -d /etc/logrotate.d/price-oracle-bot

# Force rotation (for testing)
sudo logrotate -f /etc/logrotate.d/price-oracle-bot
```

---

## Team Access to Logs (No Root Required)

Add team members to log groups:

```bash
# Create log group
sudo groupadd oraclelogs

# Add users to group
sudo usermod -a -G oraclelogs alice
sudo usermod -a -G oraclelogs bob

# Change log directory permissions
sudo chgrp -R oraclelogs /var/log/price-oracle-bot
sudo chmod -R g+r /var/log/price-oracle-bot

# Allow group to read journalctl logs
sudo usermod -a -G systemd-journal alice
sudo usermod -a -G systemd-journal bob
```

Team members can now view logs without sudo (after re-login):

```bash
journalctl -u price-oracle-bot@ar-usd -f
cat /var/log/price-oracle-bot/ar-usd.log
```

---

## Monitoring Script

Create a simple status checker:

```bash
cat > ~/check-bots.sh << 'EOF'
#!/bin/bash

echo "================================================"
echo "Price Oracle Bot Status"
echo "================================================"
echo ""

for feed in ar-usd ar-bytes; do
    echo "┌─ Feed: $feed"

    if systemctl is-active --quiet price-oracle-bot@$feed; then
        echo "│  Status: ✅ RUNNING"

        # Uptime
        uptime=$(systemctl show price-oracle-bot@$feed -p ActiveEnterTimestamp --value)
        echo "│  Started: $uptime"

        # Memory usage
        mem=$(systemctl show price-oracle-bot@$feed -p MemoryCurrent --value)
        mem_mb=$((mem / 1024 / 1024))
        echo "│  Memory: ${mem_mb} MB"

        # Last log line
        last_log=$(journalctl -u price-oracle-bot@$feed -n 1 --no-pager -o cat)
        echo "│  Last log: $last_log"
    else
        echo "│  Status: ❌ STOPPED"
    fi

    echo "└─"
    echo ""
done

echo "Recent errors (last 10 lines):"
journalctl -u 'price-oracle-bot@*' -p err -n 10 --no-pager

echo ""
echo "To view logs: journalctl -u price-oracle-bot@FEED_NAME -f"
echo "To restart: sudo systemctl restart price-oracle-bot@FEED_NAME"
EOF

chmod +x ~/check-bots.sh

# Run it
./check-bots.sh
```

---

## Adding New Feeds

To add a new feed bot:

```bash
# 1. Create environment file
cat > ~/.config/price-oracle-bot/new-feed.env << EOF
RPC_URL=https://alphanet.load.network
ORACLE=0xYourOracleAddress
FEED_DESC=new-feed-description
INTERVAL=30000
PRICE_BASE=100
PRIVATE_KEYS_JSON=$(cat keys.json | jq -c)
EOF

chmod 600 ~/.config/price-oracle-bot/new-feed.env

# 2. Start and enable the service
sudo systemctl start price-oracle-bot@new-feed
sudo systemctl enable price-oracle-bot@new-feed

# 3. Check status
sudo systemctl status price-oracle-bot@new-feed
sudo journalctl -u price-oracle-bot@new-feed -f
```

---

## Updating the Bot

When you pull new code:

```bash
# Navigate to project
cd /home/reth-node/code/load-price-loom

# Pull updates
git pull

# Install dependencies if package.json changed
npm install

# Restart all bots
sudo systemctl restart 'price-oracle-bot@*'

# Verify they're running
sudo systemctl list-units 'price-oracle-bot@*'
```

---

## Uninstalling

To completely remove the bot services:

```bash
# Stop and disable all bots
sudo systemctl stop 'price-oracle-bot@*'
sudo systemctl disable 'price-oracle-bot@*'

# Remove service file
sudo rm /etc/systemd/system/price-oracle-bot@.service

# Reload systemd
sudo systemctl daemon-reload

# Remove logs (optional)
sudo rm -rf /var/log/price-oracle-bot

# Remove env files (optional)
rm -rf ~/.config/price-oracle-bot

# Remove logrotate config (optional)
sudo rm /etc/logrotate.d/price-oracle-bot
```

---

## Security Best Practices

1. **Protect Private Keys**: Environment files are set to `chmod 600` (owner-only read/write)
2. **Use Read-Only File System**: Service has `ProtectSystem=strict` - can't modify system files
3. **Isolate /tmp**: Service has `PrivateTmp=true` - isolated temp directory
4. **Resource Limits**: Memory limited to 512MB, CPU to 50% to prevent resource exhaustion
5. **Run as Non-Root**: Service runs as `reth-node` user, not root
6. **No New Privileges**: Service can't escalate privileges

---

## Related Documentation

- **[Operator Guide](./operator-guide.md)** - Understanding operator responsibilities and EIP-712 signatures
- **[Deployment Cookbook](./deployment-cookbook.md)** - Oracle and factory deployment
- **[Maintenance Guide](./maintenance-guide.md)** - Managing feeds and operators
- **[Scripts & Bots](../scripts/README.md)** - Bot architecture and configuration
