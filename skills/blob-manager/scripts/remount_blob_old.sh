#!/bin/bash
# remount_blob_old.sh "<SAS_URL>"
#
# 在当前节点：
#   1) 若缺 blobfuse2，则自动安装（Ubuntu 22.04）
#   2) 解析 SAS URL，写 BlobFuse 配置 yaml
#   3) 强制 unmount 旧的 /blob_old，重新挂载
#   4) 确保软链（可选，按需配置 SYMLINK_SRC / SYMLINK_DST）
#
# SAS URL 形如：
#   https://<account>.blob.core.windows.net/<container>?sv=...&sig=...
set -e
SAS_URL="$1"
if [ -z "$SAS_URL" ]; then echo "Usage: $0 <SAS_URL>"; exit 1; fi

ACCOUNT=$(echo "$SAS_URL" | sed -nE 's|^https://([^.]+)\.blob\.core\.windows\.net/.*|\1|p')
CONTAINER=$(echo "$SAS_URL" | sed -nE 's|^https://[^/]+/([^?]+)\?.*|\1|p')
SAS_TOKEN=$(echo "$SAS_URL" | sed -nE 's|^[^?]+\?(.*)|\1|p')
[ -z "$ACCOUNT" ] || [ -z "$CONTAINER" ] || [ -z "$SAS_TOKEN" ] && { echo "Bad SAS URL"; exit 1; }
echo "[info] account=$ACCOUNT container=$CONTAINER token_len=${#SAS_TOKEN}"

# ── 可配置项 ──
MOUNT_POINT="/blob_old"                           # ← 挂载点
CACHE_DIR="/tmp/blobfuse2_cache_old"              # ← 本地缓存目录
SYMLINK_SRC=""                                    # ← 要创建的软链源（如 /blob/mydata），留空则跳过
SYMLINK_DST=""                                    # ← 软链目标（如 /blob_old/mydata），留空则跳过
CFG="$HOME/sh-${ACCOUNT}.yaml"                    # ← BlobFuse 配置文件路径

# 1. Install blobfuse2 if missing
if ! command -v blobfuse2 >/dev/null 2>&1; then
  echo "[install] blobfuse2 missing, installing..."
  UBUNTU_VER=$(. /etc/os-release && echo "$VERSION_ID")
  cd /tmp
  sudo wget -q "https://packages.microsoft.com/config/ubuntu/${UBUNTU_VER}/packages-microsoft-prod.deb"
  sudo dpkg -i packages-microsoft-prod.deb
  sudo apt-get update -qq
  sudo apt-get install -y -qq libfuse3-dev fuse3 blobfuse2
fi
echo "[info] blobfuse2 $(blobfuse2 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

# 2. Write config
cat > "$CFG" <<EOF
foreground: false
allow-other: true
logging:
  type: syslog
  level: log_warning
components:
  - libfuse
  - file_cache
  - attr_cache
  - azstorage
libfuse:
  attribute-expiration-sec: 120
  entry-expiration-sec: 120
  negative-entry-expiration-sec: 240
file_cache:
  path: ${CACHE_DIR}
  timeout-sec: 120
  max-size-mb: 4096
attr_cache:
  timeout-sec: 7200
azstorage:
  type: block
  account-name: ${ACCOUNT}
  endpoint: https://${ACCOUNT}.blob.core.windows.net/
  mode: sas
  sas: "${SAS_TOKEN}"
  container: ${CONTAINER}
EOF
echo "[info] config written: $CFG"

# 3. Cleanup old mount (lazy, ignore errors)
sudo umount "$MOUNT_POINT" 2>/dev/null || true
sudo fusermount3 -uz "$MOUNT_POINT" 2>/dev/null || true
sudo fusermount -uz "$MOUNT_POINT" 2>/dev/null || true
sudo umount -l "$MOUNT_POINT" 2>/dev/null || true
sudo rm -rf "$CACHE_DIR"
sudo mkdir -p "$MOUNT_POINT" "$CACHE_DIR"

# 4. Mount
sudo blobfuse2 mount "$MOUNT_POINT" --config-file "$CFG"
sleep 2
mount | grep -q "on ${MOUNT_POINT}" || { echo "[FAIL] ${MOUNT_POINT} not mounted"; exit 2; }
echo "[ok] ${MOUNT_POINT} mounted"

# 5. Symlink (optional, configure SYMLINK_SRC and SYMLINK_DST above)
if [ -n "$SYMLINK_SRC" ] && [ -n "$SYMLINK_DST" ]; then
  if [ -L "$SYMLINK_SRC" ]; then
    echo "[ok] $SYMLINK_SRC already symlink -> $(readlink "$SYMLINK_SRC")"
  elif [ -d "$SYMLINK_SRC" ]; then
    BAK="${SYMLINK_SRC}.bak.$(date +%s)"
    echo "[warn] $SYMLINK_SRC is real dir; backing up to $BAK"
    sudo mv "$SYMLINK_SRC" "$BAK"
    sudo ln -s "$SYMLINK_DST" "$SYMLINK_SRC"
  elif [ ! -e "$SYMLINK_SRC" ]; then
    sudo ln -s "$SYMLINK_DST" "$SYMLINK_SRC"
  fi
  echo "[ok] $SYMLINK_SRC -> $(readlink -f "$SYMLINK_SRC")"
  ls "$SYMLINK_SRC" | head -5
fi
echo "[done]"
