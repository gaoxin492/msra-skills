# MSRA Skills — Claude Code 运维插件

> 一组面向 MSRA 集群训练、数据管理和服务器运维的 Claude Code 技能。

---

## 初衷

在 MSRA 管理多个集群会涉及大量繁琐、重复的操作：登录到正确的节点、查 GPU 状态、轮换 SAS Token、重挂 Blob 存储、部署 Tunnel 等等。这些工作非常适合打包成 skill，交给本地的 Claude Code 来帮你管理。

有了 **msra-skills**，Claude 帮你记住所有集群的别名、凭据和配置，统一管理，不容易搞乱。不用再去记哪个别名对应哪个 job，也不用手动 SSH 进 10 个节点挨个重挂存储。集群多的时候，这对日常研究效率的提升非常明显。

目前包含两个技能，**Server Manager** 和 **Blob Manager**，但这是一个开放、可扩展的插件框架，随时可以加入新的技能（实验追踪、任务调度、日志分析等等）。

---

## 能做什么？

安装后只需跟 Claude 自然对话，对应的 skill 会自动触发：

- *"帮我登录 b0"* → SSH 登录集群 B 节点 0（多层自动降级）
- *"查一下所有集群 GPU 利用率"* → 全集群巡检
- *"SAS token 过期了，重新挂载 blob"* → 自动生成新 SAS token 并批量重挂载
- *"上传这个文件到 blob"* → AzCopy 高速传输
- *"帮我上线一台新服务器"* → 引导式上线流程，部署 tunnel + watchdog

---

## 当前技能

### Server Manager — 服务器大管家

管理所有远程服务器的登录、监控和 Tunnel 基础设施。

AzureML 集群通常通过 `az ml job connect-ssh` 访问，走的是 **WSS（WebSocket）relay**。这种方式可以用，但首次握手较慢（30 秒以上），而且 relay 有已知的间歇性故障。为了提供更快、更稳定的连接，Server Manager 会在每个节点上部署 **Tunnel**：

- **Dev Tunnel** 提供从终端直接 SSH 的能力，完全绕过 WSS relay。这是首选的连接方式，也是 Claude 直接管理服务器所依赖的通道。
- **VS Code Tunnel** 可以在浏览器中打开完整的 VS Code 编辑器，连接到远程节点。当 WSS 和 Dev Tunnel 都不可用时，或者你需要图形界面时很有用。

两种 Tunnel 都由服务器上的 **watchdog** 进程监管，每 5 分钟检查一次，自动重启挂掉的 tunnel。

连接时，Server Manager 会按顺序尝试各种方式（Dev Tunnel → WSS → VS Code Tunnel），如果前一种失败会自动降级到下一种。

| 功能 | 命令 | 说明 |
|------|------|------|
| WSS 登录 | `s <别名>` | 通过跳板机 + AzureML WSS relay 连接 |
| Dev Tunnel 登录 | `t <别名>` | 直接 SSH，绕过 WSS relay |
| 全面巡检 | `s check` | Job 状态 + GPU 利用率一起查 |
| GPU 监控 | `s check gpu` | 所有节点 GPU 利用率 |
| Tunnel 状态 | `t status` | 查看哪些 Dev Tunnel 在线 |
| 新服务器上线 | 引导式 | 部署 Dev Tunnel + VS Code Tunnel + watchdog |
| 自愈 | Watchdog | 远端每 5 分钟检查并重启挂掉的 tunnel |

也支持直连 SSH 服务器（树莓派、VPS 等）和 K8S Pod（通过 `kubectl exec` 桥接）。

### Blob Manager — Blob 存储管家

管理训练集群的 Azure Blob 存储访问。

AzureML 节点通常通过 **BlobFuse** 将 Azure Blob 容器挂载为本地目录。这需要有效的 **SAS token**，而 SAS token 每 7 天过期。过期后所有挂载变成 stale 状态，正在训练的任务如果尝试写 checkpoint 可能会导致崩溃。

Blob Manager 自动化了整个续期流程：

1. **自动生成新 SAS token**：通过跳板机上的 `az CLI` 生成，不需要打开 Azure Storage Explorer
2. **批量重挂载**：一条命令重新挂载所有集群节点的 BlobFuse
3. **验证**：确认挂载正常工作

在本地和 Blob 之间传输文件时，支持两种方式：

- **AzCopy** 适合大文件（多线程并行，~5 MB/s）
- **Python SDK**（`azure-storage-blob`）适合列目录、查元数据、小文件操作

| 功能 | 工具 | 说明 |
|------|------|------|
| SAS Token 自动续期 | 跳板机 az CLI | 不用开 Storage Explorer 就能生成新 token |
| BlobFuse 重挂载 | Shell 脚本 | 批量重挂所有节点的 `/blob_old` |
| 大文件传输 | AzCopy | 多线程上传/下载，~5 MB/s |
| 列目录 / 浏览 | Python SDK | 列文件、查大小、读元数据 |
| 小文件读写 | Python SDK | 上传/下载小文件、批量删除 |

> 💡 更多技能持续开发中，欢迎贡献！

---

## 安装方法

### 方式一：`claude plugin install` 安装（推荐）

先注册 marketplace，再安装插件：

```bash
# 第一步：添加 marketplace（只需一次）
claude plugin marketplace add gaoxin492/msra-skills

# 第二步：安装插件
claude plugin install msra-skills
```

搞定。重启 Claude Code 后就能看到 `msra-skills:server-manager` 和 `msra-skills:blob-manager`。

### 方式二：Git Clone 安装（推荐，方便更新）

不想永久安装，可以每次启动时指定路径：

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills
claude --plugin-dir ~/.claude/plugins/msra-skills
```

更新时在 clone 的目录里 `git pull` 即可。每次启动 Claude Code 都需要带 `--plugin-dir` 参数。

### 方式三：独立技能安装

将单个技能复制到 `~/.claude/skills/`，Claude 会自动发现，无需 marketplace：

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

技能名为 `/server-manager` 和 `/blob-manager`（更短，不带 `msra-skills:` 前缀）。

### 方式四：项目级安装（团队共享）

放到项目仓库里，团队通过 Git 自动获得这些技能：

```bash
# 在你的项目根目录
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/ .claude/skills/
git add .claude/skills/
```

---

## 首次配置

安装后首次使用时，Claude 会 **自动引导你** 完成配置，问你有哪些服务器、连接信息等，然后帮你配好一切。

### Server Manager

1. Claude 问你有哪些服务器（直连 SSH、AzureML、K8S）
2. 你提供连接信息（IP、用户名、job 名、subscription 等）
3. Claude 自动配置登录脚本
4. 将辅助脚本链接到 PATH：
   ```bash
   mkdir -p ~/.local/bin
   SKILL_DIR="$HOME/.claude/plugins/msra-skills/skills/server-manager"
   for script in s t s-check vscode-azml-proxy.sh vscode-k8s-proxy.sh; do
     ln -sf "${SKILL_DIR}/scripts/${script}" ~/.local/bin/${script}
   done
   export PATH="$HOME/.local/bin:$PATH"  # 加到 .zshrc 或 .bashrc
   ```
5. 安装 Dev Tunnel CLI（AzureML 用户需要）：
   ```bash
   curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
   unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
   devtunnel user login --github
   ```

### Blob Manager

1. 创建 `blob_sas.json`，填入你的 Azure SAS Token（也可以让 Claude 通过跳板机自动生成）
2. 安装依赖：`pip install azure-storage-blob`
3. （可选）安装 `azcopy` 用于大文件传输

每个技能的详细文档见 `SKILL.md`。

---

## 更新

个人配置文件（`s`、`t`、`s-check`、`blob_sas.json`）已加入 gitignore，更新不会覆盖。

**方式一安装的用户**（`claude plugin install`）：

```bash
# 先刷新 marketplace 索引
claude plugin marketplace update msra-skills-marketplace

# 再更新插件
claude plugin update msra-skills@local-msra
```

> 注意：只有 `plugin.json` 中的版本号 bump 后才会触发更新。

**方式二安装的用户**（git clone）：

```bash
cd ~/.claude/plugins/msra-skills
git pull
```

只更新文档、模板和技能逻辑，你的个人脚本和 token 不受影响。

---

## 项目结构

```
msra-skills/
├── .claude-plugin/
│   ├── plugin.json              # 插件清单
│   └── marketplace.json         # Marketplace 清单（用于 claude plugin install）
├── skills/
│   ├── server-manager/
│   │   ├── SKILL.md             # 技能文档和 Claude 指令
│   │   └── scripts/             # 登录、tunnel、巡检脚本
│   └── blob-manager/
│       ├── SKILL.md             # 技能文档和 Claude 指令
│       └── scripts/             # BlobFuse 重挂载脚本
├── README.md                    # 英文版
├── README_CN.md                 # 中文版（本文件）
└── .gitignore
```

---

## 贡献

在 MSRA 有什么重复性运维操作？把它变成一个 skill：

1. 创建 `skills/你的技能名/SKILL.md`
2. 在 `skills/你的技能名/scripts/` 下放辅助脚本
3. 提 PR

---

## 许可证

MIT

## 作者

**gaoxin492** — [GitHub](https://github.com/gaoxin492/msra-skills)
