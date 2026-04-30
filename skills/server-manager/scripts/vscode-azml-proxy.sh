#!/usr/bin/env bash
# VS Code SSH ProxyCommand 辅助脚本
# 用法: vscode-azml-proxy.sh <user> <job> <node_index> <workspace> <rg> <subscription>
# 通过跳板机获取 WSS URL 并启动 websocket 代理

set -uo pipefail

USER="$1"
JOB="$2"
NODE_INDEX="$3"
WS="$4"
RG="$5"
SUB="$6"

JUMPBOX="msra"

if [ "$USER" = "DIRECT" ]; then
    ssh_line=$(ssh -o ConnectTimeout=15 "$JUMPBOX" "az account set --subscription ${SUB} 2>/dev/null && az ml job connect-ssh --name ${JOB} --node-index ${NODE_INDEX} --private-key-file-path ~/.ssh/id_rsa --workspace-name ${WS} --resource-group ${RG} --subscription ${SUB} 2>&1 | grep ssh_command" 2>/dev/null)
else
    ssh_line=$(ssh -o ConnectTimeout=15 "$JUMPBOX" "sudo -u ${USER} bash -c 'cd ~ && az ml job connect-ssh --name ${JOB} --node-index ${NODE_INDEX} --private-key-file-path ~/.ssh/id_rsa --workspace-name ${WS} --resource-group ${RG} --subscription ${SUB} 2>&1 | grep ssh_command'" 2>/dev/null)
fi

wss_url=$(echo "$ssh_line" | grep -oE 'wss://[^ "]+' | head -n1)
connector_path=$(echo "$ssh_line" | grep -oE '/home/[^/]+/.azure/cliextensions/ml/azext_mlv2/manual/custom/_ssh_connector.py' | head -n1)

if [ -z "$wss_url" ] || [ -z "$connector_path" ]; then
    echo "ERROR: Failed to get WSS URL" >&2
    exit 1
fi

if [ "$USER" = "DIRECT" ]; then
    exec ssh -q "$JUMPBOX" "/opt/az/bin/python3 ${connector_path} ${wss_url}"
else
    exec ssh -q "$JUMPBOX" "sudo -u ${USER} /opt/az/bin/python3 ${connector_path} ${wss_url}"
fi
