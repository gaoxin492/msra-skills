# MSRA Skills — Claude Code 运维插件

一套专为科研人员和工程师打造的 **Claude Code 插件**，整合了服务器管理和 Azure Blob 存储工具，面向 AzureML / K8S 集群和远程服务器的日常运维。

---

## 这是什么？

**msra-skills** 是一个 **Claude Code Plugin（插件）**——一组专业技能的集合，安装后可以扩展 Claude Code 的能力。安装完成后，Claude 可以自动帮你：

- **登录远程服务器**（SSH / AzureML WSS / Dev Tunnel），支持多层自动降级
- **管理 Azure Blob 存储**（挂载、上传、下载、SAS Token 轮换）
- **监控 GPU 利用率**和集群健康状态
- **部署并自愈 Tunnel**，保障持久远程访问
- **引导你上线新服务器**，一步步完成配置

---

## 包含的技能

| 技能 | 触发关键词 | 功能描述 |
|------|-----------|----------|
| **server-manager** | 服务器、集群、GPU、登录、tunnel、SSH | 服务器全生命周期管理：SSH/WSS/DevTunnel 多层登录、状态巡检、GPU 监控、Tunnel 部署与 Watchdog 自愈。支持直连 SSH 服务器（树莓派、VPS 等）和 AzureML/K8S 集群。 |
| **blob-manager** | blob、SAS token、重挂载、azcopy、上传、下载 | Azure Blob 存储操作：BlobFuse 挂载/重挂载、AzCopy 高速传输（~5 MB/s）、Python SDK 列目录/元数据、SAS Token 生命周期管理（7 天过期提醒）。 |

---

## 安装方法

### 方式一：作为插件安装（推荐）

一次性安装所有技能，技能名带 `msra-skills:` 前缀。

```bash
# 克隆仓库
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills

# 启动 Claude Code 时加载插件
claude --plugin-dir ~/.claude/plugins/msra-skills
```

加载后可用的技能：
- `msra-skills:server-manager` — 提到服务器、集群、GPU 等时自动触发
- `msra-skills:blob-manager` — 提到 blob、SAS token、重挂载等时自动触发

### 方式二：作为独立技能安装

如果你希望技能名更短（不带 `msra-skills:` 前缀）：

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

技能名变为 `/server-manager` 和 `/blob-manager`。

### 方式三：直接指定路径

不想移动文件的话，直接指定路径即可：

```bash
claude --plugin-dir /path/to/msra-skills
```

---

## 首次配置

安装后，首次使用时 Claude 会 **自动引导你** 完成初始配置。以下是你需要准备的信息：

### Server Manager 配置

1. **Claude 会问你有哪些服务器** — 直连 SSH（树莓派、VPS）、AzureML 集群、还是 K8S Pod
2. **你提供连接信息** — IP、用户名、job 名、subscription 等
3. **Claude 自动配置脚本** — 更新 `scripts/s`、`scripts/t`、`scripts/s-check`
4. **将辅助脚本链接到 PATH**：
   ```bash
   mkdir -p ~/.local/bin
   SKILL_DIR="$HOME/.claude/plugins/msra-skills/skills/server-manager"
   for script in s t s-check vscode-azml-proxy.sh vscode-k8s-proxy.sh; do
     ln -sf "${SKILL_DIR}/scripts/${script}" ~/.local/bin/${script}
   done
   export PATH="$HOME/.local/bin:$PATH"  # 加到 .zshrc 或 .bashrc
   ```
5. **安装 Dev Tunnel CLI**（AzureML 用户需要）：
   ```bash
   # macOS ARM
   curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
   unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
   devtunnel user login --github
   ```

### Blob Manager 配置

1. **创建 SAS 配置文件** `~/.claude/skills/blob-manager/blob_sas.json`：
   ```json
   {
     "container_url": "https://你的账户.blob.core.windows.net/你的容器?sv=...&sig=...",
     "account": "你的账户",
     "container": "你的容器",
     "expires": "2026-05-05T07:45:00Z"
   }
   ```
2. **编辑 `scripts/run_remount_all.sh`**，设置你的集群别名（用于批量 BlobFuse 重挂载）
3. **安装依赖**：
   ```bash
   pip install azure-storage-blob
   # 大文件传输需要本地安装 azcopy
   ```

---

## 技能详细功能

### Server Manager — 服务器大管家

| 功能 | 命令 / 操作 | 说明 |
|------|------------|------|
| **WSS 登录** | `s <别名>` | 通过跳板机 + AzureML WSS relay 连接 |
| **Dev Tunnel 登录** | `t <别名>` | 绕过 WSS relay 的快速直连 |
| **Tunnel 状态** | `t status` | 检查所有 Dev Tunnel 是否在线 |
| **全面巡检** | `s check` | 状态 + GPU 一起查 |
| **GPU 巡检** | `s check gpu` | 查看所有节点 GPU 利用率 |
| **新服务器上线** | 引导式流程 | 部署 Dev Tunnel + VS Code Tunnel + Watchdog |
| **自动降级** | 自动执行 | 四层降级链：DevTunnel → WSS → VS Code Tunnel → Happy App |
| **自愈机制** | Watchdog 脚本 | 远端每 5 分钟检查并自动重启挂掉的 Tunnel |

### Blob Manager — Blob 存储管家

| 功能 | 工具 | 说明 |
|------|------|------|
| **大文件传输** | AzCopy | 多线程上传/下载，~5 MB/s |
| **列目录 / 浏览** | Python SDK | 列文件、查大小、读元数据 |
| **小文件读写** | Python SDK | 上传/下载小文件、批量删除 |
| **BlobFuse 重挂载** | Shell 脚本 | SAS 过期后批量重挂所有节点的 `/blob_old` |
| **SAS Token 管理** | `blob_sas.json` | 存储、更新、验证 SAS Token |

---

## 项目结构

```
msra-skills/
├── .claude-plugin/
│   └── plugin.json              # 插件清单（名称、版本、作者）
├── skills/
│   ├── server-manager/
│   │   ├── SKILL.md             # 完整技能文档和 Claude 指令
│   │   └── scripts/
│   │       ├── s                # WSS 登录脚本
│   │       ├── t                # Dev Tunnel 登录脚本
│   │       ├── s-check          # 巡检脚本
│   │       ├── vscode-azml-proxy.sh   # VS Code AzureML SSH 代理
│   │       ├── vscode-k8s-proxy.sh    # VS Code K8S SSH 代理
│   │       └── remote/          # 部署到服务器上的 Watchdog 脚本
│   │           ├── keep_tunnel.sh
│   │           ├── keep_code_tunnel.sh
│   │           └── keep_tunnel_loop.sh
│   └── blob-manager/
│       ├── SKILL.md             # 完整技能文档和 Claude 指令
│       └── scripts/
│           ├── remount_blob_old.sh    # 单节点 BlobFuse 重挂载
│           └── run_remount_all.sh     # 批量重挂载所有节点
├── README.md                    # 英文版 README
├── README_CN.md                 # 本文件（中文版）
└── .gitignore
```

---

## 许可证

MIT

---

## 作者

**gaoxin492** — [GitHub](https://github.com/gaoxin492/msra-skills)
