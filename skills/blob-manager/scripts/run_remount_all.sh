#!/bin/bash
# run_remount_all.sh "<SAS_URL>"
#
# 用法（在本地 mac 上跑）:
#   bash run_remount_all.sh \
#     "https://YOUR_ACCOUNT.blob.core.windows.net/YOUR_CONTAINER?sv=...&sig=..."
#
# 该脚本：
#   - 把 remount_blob_old.sh base64 上传到各集群节点
#   - 在每个节点上执行挂载
#
# ════════════════════════════════════════
# 在此配置你的集群别名和节点拓扑
# ════════════════════════════════════════
# 每行格式: "集群别名 标签"
# 别名对应 server-manager 的 s 脚本中的集群名
# 脚本会登录 node-0 执行，再 ssh node-1 执行（2 节点集群）
CLUSTERS=(
  "rl:Cluster A"
  "b0:Cluster B"
)
# 如果你的集群只有 1 个节点，将 MULTI_NODE 设为 false
MULTI_NODE=true

set -e
SAS_URL="$1"
if [ -z "$SAS_URL" ]; then echo "Usage: $0 <SAS_URL>"; exit 1; fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
INNER="$SCRIPT_DIR/remount_blob_old.sh"
[ -f "$INNER" ] || { echo "Missing $INNER"; exit 1; }

SCRIPT_B64=$(base64 < "$INNER" | tr -d '\n')
SAS_B64=$(printf '%s' "$SAS_URL" | base64 | tr -d '\n')

run_on() {
  local NODE="$1"; local LABEL="$2"
  echo ""
  echo "============================================================"
  echo "[$LABEL] running on $NODE (node-0)"
  echo "============================================================"
  echo "echo MARK; echo $SCRIPT_B64 | base64 -d > /tmp/remount.sh && chmod +x /tmp/remount.sh && SAS=\$(echo $SAS_B64 | base64 -d) && bash /tmp/remount.sh \"\$SAS\"; echo END" \
    | s "$NODE" 2>/dev/null | sed -n '/MARK/,/END/p'

  if [ "$MULTI_NODE" = true ]; then
    echo ""
    echo "------ [$LABEL] running on $NODE -> ssh node-1 ------"
    echo "echo MARK; ssh -o StrictHostKeyChecking=no node-1 'echo $SCRIPT_B64 | base64 -d > /tmp/remount.sh && chmod +x /tmp/remount.sh && SAS=\$(echo $SAS_B64 | base64 -d) && bash /tmp/remount.sh \"\$SAS\"'; echo END" \
      | s "$NODE" 2>/dev/null | sed -n '/MARK/,/END/p'
  fi
}

for entry in "${CLUSTERS[@]}"; do
  NODE="${entry%%:*}"
  LABEL="${entry##*:}"
  run_on "$NODE" "$LABEL"
done

echo ""
echo "============================================================"
echo "All done."
echo "============================================================"
