#!/usr/bin/env bash
# VS Code SSH ProxyCommand for K8S pods
# 用法: vscode-k8s-proxy.sh <pod_name>
# 通过 kubectl exec 桥接 stdio 到 pod 内的 sshd (端口 22)

set -uo pipefail

POD="$1"
NAMESPACE="reviewer-rl-dev"
JUMP="k8s-jump"

# 通过 k8s-jump 执行 kubectl exec，用 socat/nc 连接本地 sshd
# 优先尝试 socat，fallback 到 nc
exec ssh -q -o ConnectTimeout=15 "$JUMP" \
    "kubectl exec -i ${POD} -n ${NAMESPACE} -- ncat localhost 22"
