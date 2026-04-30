#!/bin/bash
# Watchdog: restart VS Code tunnel if not running
# Usage: Customize TUNNEL_NAME per node
CODE=~/.local/bin/code
TUNNEL_NAME="rl-node0"  # ← 每台节点改成自己的唯一名字
LOG=~/.code-tunnel.log
pgrep -f "code tunnel" >/dev/null && exit 0
echo "[$(date)] code tunnel dead, restarting..." >> /tmp/keep_tunnel.log
nohup setsid $CODE tunnel --accept-server-license-terms --name "$TUNNEL_NAME" </dev/null >"$LOG" 2>&1 &
disown
