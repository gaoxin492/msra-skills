# MSRA Skills — Claude Code 运维插件

> 一组面向 MSRA 集群训练、数据管理和服务器运维的 Claude Code 技能。

---

## 初衷

在 MSRA 管理多个集群会涉及大量繁琐、重复的操作：登录到正确的节点、查 GPU 状态、轮换 SAS Token、重挂 Blob 存储、部署 Tunnel 等等。这些工作非常适合打包成 skill，交给本地的 Claude Code 来帮你管理。

有了 **msra-skills**，Claude 帮你记住所有集群的别名、凭据和配置，统一管理，不容易搞乱。不用再去记哪个别名对应哪个 job，也不用手动 SSH 进 10 个节点挨个重挂存储。集群多的时候，这对日常研究效率的提升非常明显。

目前包含三个技能，**Server Manager**、**Blob Manager** 和 **Vibe Paper**，但这是一个开放、可扩展的插件框架，随时可以加入新的技能（实验追踪、任务调度、日志分析等等）。

---

## 更新日志

### v1.5.0 (2026-05-02)

**Vibe Paper**（新技能）
- **学术论文写作助手**：内置 Microsoft Tech Report 模板一键初始化 LaTeX 项目，也支持用户自定义模板（ICLR/NeurIPS/CVPR 等）
- 遵循顶会写作规范（ICLR/ICML/NeurIPS 风格）
- 丰富的环境支持：彩色定理框、伪代码（algorithm2e）、LLM Prompt 框（含 JSON）、子图、booktabs 表格
- 附录目录开关（`\appendixtoctrue` / `\appendixtocfalse`）
- 自动检测并引导安装 LaTeX 环境
- 自动编译（pdflatex + bibtex）

**Server Manager**
- **新增批量 SSH 端口迁移（22 → 2223）**：分步指南，涵盖 NSG 规则管理、sshd 配置、连通性验证。适用于公司安全策略要求关闭 22 端口的公网 VM。

### v1.4.0 (2026-05-01)

**Server Manager**
- **新增 WSS 编程式访问**：Claude 现在可以通过动态获取 WSS URL + SSH ProxyCommand 的方式直接在 AzureML 节点上执行命令，无需 expect、无需交互式会话。当 Dev Tunnel 不可用时，这是 Claude 自动化管理服务器的关键备用通道。
- **更新连接诊断决策树**：明确区分交互式脚本（`s`/`t`）和编程式访问（devtunnel connect + ssh / WSS ProxyCommand），Claude 在自动化场景下会选择正确的方式。

### v1.3.0

- 首次公开发布，包含 Server Manager 和 Blob Manager

---

## 安装方法

### 方式一：`claude plugin install`（推荐）

通过插件系统安装，先注册 marketplace 再安装：

```bash
claude plugin marketplace add gaoxin492/msra-skills
claude plugin install msra-skills
```

重启 Claude Code 后就能看到 `msra-skills:server-manager`、`msra-skills:blob-manager` 和 `msra-skills:vibe-paper`。每次启动自动加载，不需要额外参数。

### 方式二：Git Clone 安装

手动 clone 后作为插件加载。适合开发调试或需要直接访问文件的场景。

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills
claude --plugin-dir ~/.claude/plugins/msra-skills
```

注意：每次启动需要带 `--plugin-dir` 参数，可以设置 shell alias：

```bash
alias claude='claude --plugin-dir ~/.claude/plugins/msra-skills'
```

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
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/ .claude/skills/
git add .claude/skills/
```

---

## 更新

个人配置文件（`s`、`t`、`s-check`、`blob_sas.json`）在插件目录之外，不会被更新覆盖。

**方式一用户**（`claude plugin install`）：

```bash
claude plugin marketplace update msra-skills-marketplace
claude plugin update msra-skills@msra-skills-marketplace
```

重启 Claude Code 生效。

**方式二用户**（git clone）：

```bash
cd ~/.claude/plugins/msra-skills
git pull
```

---

## 能做什么？

安装后只需跟 Claude 自然对话，对应的 skill 会自动触发：

- *"帮我登录 b0"* → SSH 登录集群 B 节点 0（多层自动降级）
- *"查一下所有集群 GPU 利用率"* → 全集群巡检
- *"SAS token 过期了，重新挂载 blob"* → 自动生成新 SAS token 并批量重挂载
- *"上传这个文件到 blob"* → AzCopy 高速传输
- *"帮我上线一台新服务器"* → 引导式上线流程，部署 tunnel + watchdog
- *"帮我新建一篇论文"* → 用 Microsoft Tech Report 模板初始化 LaTeX 项目
- *"帮我写 Introduction"* → 按顶会规范撰写引言

---

## 技能详情

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

### Vibe Paper — 学术论文写作助手

内置 Microsoft Tech Report 模板的学术论文写作助手。

写论文涉及大量 LaTeX 样板工作：搭建文档结构、配置定理环境、调整浮动体位置、格式化参考文献等等。Vibe Paper 帮你处理所有这些，让你专注于内容本身。

| 功能 | 说明 |
|------|------|
| 模板初始化 | 一条命令创建完整的 Microsoft Tech Report 项目 |
| 自定义模板 | 指定任意 LaTeX 模板（ICLR、NeurIPS、CVPR），Claude 自动适配 |
| 写作规范 | 遵循 ICLR/ICML/NeurIPS 风格：浮动体位置、引用格式、章节结构 |
| 丰富环境 | 彩色定理框、algorithm2e 伪代码、LLM Prompt 框、JSON 代码块 |
| 附录目录 | 可选的附录目录页，通过 `\appendixtoctrue/false` 开关控制 |
| 自动编译 | pdflatex + bibtex 自动编译并检查错误 |

示例 PDF 见 `skills/vibe-paper/example.pdf`。

---

## 首次配置

安装后首次使用时，Claude 会 **自动引导你** 完成配置，问你有哪些服务器、连接信息等，然后帮你配好一切。

### Server Manager

1. Claude 问你有哪些服务器（直连 SSH、AzureML、K8S）
2. 你提供连接信息（IP、用户名、job 名、subscription 等）
3. Claude 将模板脚本复制到 `~/.local/bin/` 并填入你的集群信息
4. 确保 `~/.local/bin` 在 PATH 中：
   ```bash
   export PATH="$HOME/.local/bin:$PATH"  # 加到 .zshrc 或 .bashrc
   ```
5. 安装 Dev Tunnel CLI（AzureML 用户需要）：
   ```bash
   curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
   unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
   devtunnel user login --github
   ```

### Blob Manager

1. 创建 `~/.config/msra-skills/blob_sas.json`，填入你的 Azure SAS Token（也可以让 Claude 通过跳板机自动生成）
2. 安装依赖：`pip install azure-storage-blob`
3. （可选）安装 `azcopy` 用于大文件传输

每个技能的详细文档见 `SKILL.md`。

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
│   └── vibe-paper/
│       ├── SKILL.md             # 技能文档和 Claude 指令
│       ├── example.pdf          # 渲染示例 PDF
│       └── template/            # Microsoft Tech Report LaTeX 模板
├── README.md                    # 英文版
├── README_CN.md                 # 中文版（本文件）
└── .gitignore
```

---

## 开发者指南

### 环境准备

将 repo clone 到一个工作目录（不是插件安装路径）：

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/Projects/msra-skills
cd ~/Projects/msra-skills
```

日常使用可以同时通过 `claude plugin install` 安装。开发用的 clone 和安装的插件互不影响。

### 修改内容

| 改什么 | 在哪里 |
|--------|--------|
| Skill 行为 / Claude 指令 | `skills/<名称>/SKILL.md` |
| 脚本模板 | `skills/<名称>/scripts/*.example` |
| 辅助脚本（非个人配置） | `skills/<名称>/scripts/*.sh` |
| 插件元数据 | `.claude-plugin/plugin.json` |
| README | `README.md`、`README_CN.md` |

### 发布

改完后 bump 版本号然后 push：

```bash
# 1. 编辑 .claude-plugin/plugin.json，修改 "version"（如 "1.2.0" → "1.3.0"）

# 2. 提交并推送
git add -A
git commit -m "feat: 描述你的改动"
git push
```

用户就可以通过以下命令更新：

```bash
claude plugin marketplace update msra-skills-marketplace
claude plugin update msra-skills@msra-skills-marketplace
```

版本号必须 bump，否则 `claude plugin update` 不会检测到变更。

### 添加新技能

1. 创建 `skills/技能名/SKILL.md`，在 YAML frontmatter 中写 `description` 字段
2. 在 `skills/技能名/scripts/` 下放辅助脚本（含个人配置的用 `.example` 后缀）
3. 如果有个人配置文件，在 `.gitignore` 中添加
4. Bump `.claude-plugin/plugin.json` 中的版本号
5. Push

### 架构

```
插件目录（claude plugin install 管理，用户只读）
  └── SKILL.md              ← Claude 读这个来了解能做什么
  └── scripts/*.example     ← 个人脚本的模板
  └── scripts/*.sh          ← 共享辅助脚本（非个人配置）

~/.local/bin/（用户自己的，插件更新不会触碰）
  └── s, t, s-check         ← 个人脚本，含集群凭据

~/.config/msra-skills/（用户自己的）
  └── blob_sas.json         ← SAS token
```

---

## License

MIT License
