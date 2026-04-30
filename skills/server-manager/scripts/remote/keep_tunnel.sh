#!/bin/bash
# Watchdog: restart devtunnel host if not running
# Usage: Customize TUNNEL_ID per node, then run via keep_tunnel_loop.sh
DT=/blob/gaoxin/bin/devtunnel
TUNNEL_ID="your-tunnel-id-here"  # ← 每台节点改成自己的固定 tunnel ID
LOG=/tmp/devtunnel-host.log
pgrep -f "devtunnel host" >/dev/null && exit 0
echo "[$(date)] devtunnel dead, restarting..." >> /tmp/keep_tunnel.log
nohup $DT host "$TUNNEL_ID" </dev/null >"$LOG" 2>&1 &
disown
