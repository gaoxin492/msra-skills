# MSRA Skills — Claude Code 运维插件

> 让在 MSRA 的日常工作更轻松——尤其是集群训练、数据管理和服务器运维。

---

## 初衷

在 MSRA 做研究，日常要跟 AzureML 集群、K8S Pod、GPU 监控、Blob 存储、SAS Token、多节点 SSH 登录等各种运维琐事打交道，这些事情占用了大量本该用于研究的时间。**msra-skills** 就是为了解决这个问题而生的 Claude Code 插件。

核心理念很简单：**让研究员专注于研究，而不是基础设施。**

目前包含两个技能——**Server Manager** 和 **Blob Manager**——但这是一个开放、可扩展的插件框架。随时可以加入新的技能（实验追踪、任务调度、日志分析等等）。只要是 MSRA 日常反复要做的运维操作，都可以变成一个 skill 放进来。

---

## 能做什么？

安装后只需跟 Claude 自然对话，对应的 skill 会自动触发：

- *"帮我登录 b0"* → SSH 登录集群 B 节点 0（四层自动降级）
- *"查一下所有集群 GPU 利用率"* → 全集群巡检
- *"SAS token 过期了，重新挂载 blob"* → 批量 BlobFuse 重挂载
- *"上传这个文件到 blob"* → AzCopy 高速传输
- *"帮我上线一台新服务器"* → 引导式上线流程，部署 tunnel + watchdog

---

## 当前技能

| 技能 | 功能 |
|------|------|
| **server-manager** | 服务器登录（SSH / WSS / DevTunnel）、状态巡检、GPU 监控、Tunnel 部署与 Watchdog 自愈。支持直连 SSH、AzureML 集群、K8S Pod。 |
| **blob-manager** | Azure Blob 存储：BlobFuse 挂载/重挂载、AzCopy 传输（~5 MB/s）、Python SDK 操作、SAS Token 生命周期管理。 |

> 💡 更多技能持续开发中，欢迎贡献！

---

## 安装方法

### 方式一：作为插件安装（推荐）

将仓库 clone 到 Claude Code 插件目录，启动时自动识别：

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills
```

搞定。重启 Claude Code 后就能看到 `msra-skills:server-manager` 和 `msra-skills:blob-manager`。

> 也可以不移动文件，直接指定路径加载：
> ```bash
> claude --plugin-dir /path/to/msra-skills
> ```

### 方式二：独立技能安装

如果你只需要某个技能，或者想要更短的名字（不带 `msra-skills:` 前缀）：

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

### 方式三：项目级安装（团队共享）

放到项目仓库里，团队通过 Git 自动获得这些技能：

```bash
# 在你的项目根目录
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/ .claude/skills/
git add .claude/skills/
```

---

## 首次配置

安装后首次使用时，Claude 会 **自动引导你** 完成配置——问你有哪些服务器、连接信息等，然后帮你配好一切。

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

1. 创建 `blob_sas.json`，填入你的 Azure SAS Token
2. 安装依赖：`pip install azure-storage-blob`
3. （可选）安装 `azcopy` 用于大文件传输

每个技能的详细文档见 `SKILL.md`。

---

## 技能详情

### Server Manager — 服务器大管家

| 功能 | 命令 | 说明 |
|------|------|------|
| WSS 登录 | `s <别名>` | 通过跳板机 + AzureML WSS relay 连接 |
| Dev Tunnel | `t <别名>` | 绕过 WSS 的快速直连 |
| 全面巡检 | `s check` | 状态 + GPU 一起查 |
| GPU 监控 | `s check gpu` | 所有节点 GPU 利用率 |
| Tunnel 状态 | `t status` | 检查 Dev Tunnel 是否在线 |
| 新服务器上线 | 引导式 | 完整部署：tunnel + watchdog |
| 自动降级 | 自动 | DevTunnel → WSS → VS Code Tunnel → Happy App |
| 自愈 | Watchdog | 远端每 5 分钟检查并重启挂掉的 tunnel |

### Blob Manager — Blob 存储管家

| 功能 | 工具 | 说明 |
|------|------|------|
| 大文件传输 | AzCopy | 多线程上传/下载，~5 MB/s |
| 列目录 / 浏览 | Python SDK | 列文件、查大小、读元数据 |
| 小文件读写 | Python SDK | 上传/下载小文件、批量删除 |
| BlobFuse 重挂载 | Shell 脚本 | SAS 过期后批量重挂所有节点 |
| SAS Token 管理 | `blob_sas.json` | 存储、更新、验证 |

---

## 项目结构

```
msra-skills/
├── .claude-plugin/
│   └── plugin.json              # 插件清单
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
