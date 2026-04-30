#!/bin/bash
# Watchdog loop: check every 5 min, restart dead tunnels
# Run with: nohup setsid bash keep_tunnel_loop.sh </dev/null >/tmp/keep_tunnel_loop.log 2>&1 & disown
while true; do
  bash /blob/gaoxin/keep_tunnel.sh
  bash /blob/gaoxin/keep_code_tunnel.sh
  sleep 300
done
