---
description: "Azure Blob 存储管理：BlobFuse 重挂载、Python SDK 操作、AzCopy 高速传输、SAS Token 管理。Trigger when: 用户说 'SAS token 过期'、'重新挂载 blob'、'换 token'、'/blob_old 不见了'、'remount blob'、'下载 blob 文件'、'上传到 blob'、'列一下 blob 目录'、'blob 里有什么'、'azcopy'、'删 blob 文件'，或在 SAS 失效后想批量恢复存储访问。集群登录/服务器列表请见 msra-skills:server-manager。"
---

# Azure Blob 存储管理

> **Language**: 始终用中文回复用户。

---

## 概览

本 skill 管理 Azure Blob 容器的所有操作：

| 功能 | 工具 | 适用场景 |
|------|------|----------|
| **BlobFuse 重挂载** | `run_remount_all.sh` | SAS 过期后批量重挂服务器 |
| **AzCopy 传输** | `azcopy` (本地已装) | 大文件上传/下载（多线程，~5 MB/s） |
| **Python SDK** | `azure-storage-blob` | 列目录、小文件读写、元数据操作 |
| **SAS Token 管理** | `blob_sas.json` | 存储/更新当前 SAS URL |

---

## SAS Token 管理

### 存储位置

建议将当前 SAS URL 持久化在本地文件中，例如：
```
~/.claude/skills/blob-manager/blob_sas.json
```

格式：
```json
{
  "container_url": "https://YOUR_ACCOUNT.blob.core.windows.net/YOUR_CONTAINER?sv=...&sig=...",
  "account": "YOUR_ACCOUNT",
  "container": "YOUR_CONTAINER",
  "expires": "2026-05-05T07:45:00Z",
  "note": "SAS token 每 7 天过期，需手动更新"
}
```

### 更新 SAS Token

用户提供新 SAS URL 时：
1. 更新 `blob_sas.json` 中的 `container_url` 和 `expires`
2. 用 Python SDK 快速验证连接（列几个文件）
3. 如需重挂服务器，继续跑 BlobFuse 重挂载流程

### ⚠️ SAS Token 7 天过期

过期后：
- 本地 azcopy / Python SDK 会报 403
- 服务器上 BlobFuse 进入 stale 状态，**正在训练的任务写 checkpoint 会导致服务器崩溃**
- 需要用户从 Azure Storage Explorer 重新生成

---

## 方式一：AzCopy（大文件首选）

本地需安装 `azcopy`，多线程并行传输，速度约 **5 MB/s**（比 Python SDK 快 25 倍）。

### 用法

从 `blob_sas.json` 读取 `container_url`，拼接路径：

```bash
# 读取 SAS URL
SAS_URL=$(python3 -c "import json; print(json.load(open('blob_sas.json'))['container_url'])")

# 下载单个文件
azcopy copy "${SAS_URL/YOUR_CONTAINER?/YOUR_CONTAINER/path/to/file?}" /local/path

# 下载整个目录（递归）
azcopy copy "${SAS_URL/YOUR_CONTAINER?/YOUR_CONTAINER/some_dir?}" ./local_dir --recursive

# 上传文件
azcopy copy ./local_file "${SAS_URL/YOUR_CONTAINER?/YOUR_CONTAINER/target/path?}"

# 上传目录
azcopy copy ./local_dir "${SAS_URL/YOUR_CONTAINER?/YOUR_CONTAINER/target_dir?}" --recursive
```

### 实际操作时

Claude 应该用 Python 拼 URL 更可靠：

```python
import json
cfg = json.load(open('blob_sas.json'))
base = cfg['container_url']
# 分离 base URL 和 SAS query
base_url, sas_query = base.split('?', 1)
blob_url = f"{base_url}/path/to/file?{sas_query}"
```

然后调用 `azcopy copy "<blob_url>" <local_path>`。

### 性能参考（本地 Mac → Azure）

| 操作 | 速度 |
|------|------|
| AzCopy 下载 | ~5 MB/s |
| AzCopy 上传 | ~3 MB/s |
| Python SDK 下载 | ~0.2 MB/s |
| Python SDK 上传 | ~3 MB/s |
| 删除 | ~0.2s/个 |

---

## 方式二：Python SDK（小文件/列目录）

需安装 `azure-storage-blob`（`pip install azure-storage-blob`）。适合列目录、读小文件、批量操作元数据。

### 基本用法

```python
from azure.storage.blob import ContainerClient
import json

cfg = json.load(open('blob_sas.json'))
client = ContainerClient.from_container_url(cfg['container_url'])

# 列目录
for blob in client.list_blobs(name_starts_with="some_dir/"):
    print(f"{blob.name}  ({blob.size / 1024 / 1024:.1f} MB)")

# 查文件大小
props = client.get_blob_client("path/to/file.pt").get_blob_properties()
print(f"Size: {props.size / 1024 / 1024:.1f} MB")

# 下载小文件
data = client.download_blob("path/to/config.json").readall()

# 上传
client.upload_blob("path/to/output.txt", b"content", overwrite=True)

# 删除
client.delete_blob("path/to/old_file.pt")

# 批量删除
for blob in client.list_blobs(name_starts_with="trash/"):
    client.delete_blob(blob.name)
```

---

## 方式三：BlobFuse 重挂载（服务器端）

### 何时触发

- "SAS token 过期了，帮我重挂 blob"
- "/blob_old 挂不上"
- "blobfuse 401 了"
- "换 token，重新挂载"

### 背景

- AzureML 集群各节点需要把 Azure Blob 容器挂到本地 `/blob_old`
- SAS token 7 天过期，过期后所有 mount 进入 stale 状态，需要重新挂载
- 新 SAS URL 由用户从 Azure Storage Explorer 生成

### 操作步骤

1. **获取新 SAS URL**
   - 让用户提供完整的 SAS URL（形如 `https://YOUR_ACCOUNT.blob.core.windows.net/YOUR_CONTAINER?sv=...&sig=...`）
   - **不要在对话日志里再次粘贴完整 SAS** — 直接传进脚本即可

2. **跑批量挂载脚本**（在本地 mac 上执行）：
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/run_remount_all.sh "<完整 SAS URL>"
   ```
   该脚本会依次登录各集群节点，在每个节点上执行 `remount_blob_old.sh`。

3. **每个节点上 `remount_blob_old.sh` 做的事**：
   - 缺 blobfuse2 自动 `apt install`（依赖 `libfuse3-dev fuse3 blobfuse2`，需要先装 `packages-microsoft-prod.deb`）
   - 解析 SAS URL → 写 BlobFuse 配置 yaml（account / container / sas / endpoint）
   - 强制清理 `/blob_old`：`umount` → `fusermount3 -uz` → `umount -l` → 删缓存
   - `sudo blobfuse2 mount /blob_old --config-file <yaml>`
   - 修复软链（可选，按脚本中 SYMLINK_SRC/SYMLINK_DST 配置）

4. **验收**：
   - 看脚本输出每节点是否打印 `[ok] /blob_old mounted` 和 `[done]`
   - 必要时手动 ssh 进去 `ls /blob_old | head` 验证

### 自定义

`run_remount_all.sh` 中的集群别名（如 `rl`、`b0`）需要根据你的 server-manager 配置修改。默认通过 server-manager 的 `s` 脚本登录各节点。

---

## 常见问题

### BlobFuse
- **`mount.go: Mount directory is already mounted` 卡住** → 先 `sudo umount -l /blob_old`，再重新 mount。脚本已包含此步
- **`401 NoAuthenticationInformation`** → SAS token 过期或 yaml 配置错误；重新生成 SAS 再跑脚本
- **`Device or resource busy`** → `sudo lsof +f -- /blob_old` 找 PID 杀掉，或 lazy unmount 后等几秒

### AzCopy
- **403 Forbidden** → SAS token 过期，让用户提供新的
- **速度慢** → 检查网络；azcopy 默认已开并行，一般是带宽瓶颈

### Python SDK
- **`Unable to stream download`** → 大文件超时，改用 azcopy
- **连接慢** → 正常，SDK 单线程；大文件请用 azcopy
