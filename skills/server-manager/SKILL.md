---
description: "服务器大管家：管理本地和远程服务器的登录、状态巡检、Tunnel 部署与自愈。支持直连 SSH 服务器（树莓派、VPS 等）和复杂的 AzureML/K8S 集群。Trigger when: 用户提到服务器、集群、GPU、登录机器、训练机器，或问运维状态。"
---

# 服务器大管家

> **Language**: 始终用中文回复用户。

---

## 脚本与安装

本 skill 自带所有必需脚本：

```
server-manager/
├── SKILL.md                          # 本文档
├── scripts/
│   ├── s                             # WSS 登录脚本（需配置集群信息）
│   ├── t                             # Dev Tunnel 登录脚本（需注册 tunnel ID）
│   ├── s-check                       # 一键巡检脚本（需配置集群信息）
│   ├── vscode-azml-proxy.sh          # VS Code AzureML SSH 代理（通用）
│   ├── vscode-k8s-proxy.sh           # VS Code K8S SSH 代理（通用）
│   └── remote/                       # 部署到服务器上的 watchdog 脚本
│       ├── keep_tunnel.sh            # devtunnel 自动拉起（需改 TUNNEL_ID）
│       ├── keep_code_tunnel.sh       # VS Code tunnel 自动拉起（需改 NAME）
│       └── keep_tunnel_loop.sh       # 每 5 分钟巡检 loop
```

### 首次安装

```bash
# 1. 从模板复制脚本到 ~/.local/bin/（个人配置，不受插件更新影响）
mkdir -p ~/.local/bin
SKILL_DIR="${CLAUDE_SKILL_DIR}"  # Claude 会自动设置这个变量
cp "${SKILL_DIR}/scripts/s.example" ~/.local/bin/s
cp "${SKILL_DIR}/scripts/t.example" ~/.local/bin/t
cp "${SKILL_DIR}/scripts/s-check.example" ~/.local/bin/s-check
cp "${SKILL_DIR}/scripts/vscode-azml-proxy.sh" ~/.local/bin/vscode-azml-proxy.sh
cp "${SKILL_DIR}/scripts/vscode-k8s-proxy.sh" ~/.local/bin/vscode-k8s-proxy.sh
chmod +x ~/.local/bin/s ~/.local/bin/t ~/.local/bin/s-check ~/.local/bin/vscode-azml-proxy.sh ~/.local/bin/vscode-k8s-proxy.sh

# 2. 确保 ~/.local/bin 在 PATH 中（加到 .zshrc 或 .bashrc）
export PATH="$HOME/.local/bin:$PATH"

# 3. 创建配置目录
mkdir -p ~/.config/msra-skills

# 3. 安装 devtunnel CLI
curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
chmod +x ~/.local/bin/devtunnel
devtunnel user login --github

# 4. 配置 SSH
# 需要：~/.ssh/config（跳板机配置）、SSH 私钥
# 这些含敏感信息，不打包在 skill 中
```

### 配置你的集群

安装后需要编辑以下脚本，填入你自己的集群信息：

| 脚本 | 要改什么 |
|------|----------|
| `scripts/s` | 跳板机别名、集群 job 名、workspace、subscription 等 |
| `scripts/t` | `get_tunnel_id()` 中的 tunnel ID 映射 |
| `scripts/s-check` | `CLUSTERS` 数组中的集群信息 |

脚本中所有需要修改的位置都用 `← 改成...` 注释标记。

---

## 连接降级链路（核心）

本 skill 支持两类服务器：

### 直连 SSH 服务器（树莓派、VPS、云主机等）

直接 `s <别名>` 即可，底层就是 `ssh <user>@<host>`。无需 tunnel、无需跳板机。

### AzureML 集群（需要跳板机 + WSS relay）

按以下 4 层依次尝试连接。如果某一层失败且不确定服务器是否存活，可以查 job 状态辅助判断：

```bash
# 查 AzureML job 是否还在 Running（可选诊断手段，不是必须前置步骤）
ssh <jumpbox> "sudo -u '<user>' bash -c 'az ml job show --name <JOB> --workspace-name <WS> --resource-group <RG> --subscription <SUB> -o tsv --query status'"
```

- 如果 **不是 Running** → 告知用户 job 已挂，所有连接方式都不会通
- 如果 **Running** 但连不上 → 说明是 WSS relay 等中间环节故障，服务器本身正常

### Layer 1: `t <别名>` — Dev Tunnel（首选，秒连）

通过 Microsoft Dev Tunnels 直连服务器 SSH，**完全绕开 AzureML WSS relay**。

```bash
t <别名>        # SSH 连接
t status        # 检查 tunnel 在线状态
t setup         # 查看部署指南
```

- 依赖远端 `devtunnel host` 后台运行（有 watchdog 自动拉起）
- **失败时** → 尝试 Layer 2

### Layer 2: `s <别名>` — WSS SSH（慢，受 relay 影响）

通过 AzureML 的 WSS relay 连接，首次握手 30+ 秒。

```bash
s <别名>        # 登录服务器（交互式）
```

- AzureML WSS relay 有已知间歇性故障（[Issue #2423](https://github.com/microsoft/vscode-tools-for-ai/issues/2423)），可持续数小时
- ⚠️ **不要让用户 cancel job**（会丢失计算资源）
- **失败时** → 尝试 Layer 3

#### WSS 编程式访问（Claude 必读）

`s <别名>` 和 `az ml job connect-ssh` 都是**交互式**的，不支持直接传远程命令。但 Claude 可以通过 `vscode-azml-proxy.sh` 的原理，动态获取 WSS URL 后像普通 SSH 一样执行命令：

```bash
# 第 1 步：通过跳板机获取 WSS URL 和 connector 路径
ssh_line=$(ssh -o ConnectTimeout=15 <JUMPBOX> "sudo -u '<USER>' bash -c 'cd ~ && az ml job connect-ssh \
    --name <JOB> --node-index <NODE> --private-key-file-path ~/.ssh/id_rsa \
    --workspace-name <WS> --resource-group <RG> --subscription <SUB> 2>&1 | grep ssh_command'" 2>/dev/null)

WSS_URL=$(echo "$ssh_line" | grep -oE 'wss://[^ "]+' | head -n1)
CONNECTOR=$(echo "$ssh_line" | grep -oE '/home/[^/]+/.azure/cliextensions/ml/azext_mlv2/manual/custom/_ssh_connector.py' | head -n1)

# 第 2 步：通过 WSS 代理执行远程命令（像普通 SSH 一样）
ssh -o StrictHostKeyChecking=no \
    -o ProxyCommand="ssh -q <JUMPBOX> \"sudo -u '<USER>' /opt/az/bin/python3 ${CONNECTOR} ${WSS_URL}\"" \
    -i <LOCAL_SSH_KEY> aiscuser@placeholder "<REMOTE_COMMAND>"
```

**关键点：**
- WSS URL 是一次性的，每次需要重新获取（第 1 步）
- `aiscuser@placeholder` 中的 hostname 是占位符，实际连接通过 ProxyCommand 建立
- 本地 SSH 私钥路径（如 `~/.ssh/azml_id_rsa`）与跳板机上的不同
- 这个方法**完全不需要 expect**，可以直接在脚本中使用
- 当 Dev Tunnel 不可用时，这是 Claude 自动化执行远程命令的唯一方式

### Layer 3: VS Code Tunnel 浏览器终端

让用户在浏览器中打开 VS Code Tunnel 链接，在内置终端执行命令。

```
https://vscode.dev/tunnel/<tunnel-name>
```

- 告诉用户：「请打开链接，在终端里帮我执行以下命令：...」
- **失败时** → 尝试 Layer 4

### Layer 4: Happy App 远程 Claude

让用户通过手机上的 Happy App 连接到远程 Claude 实例，由那个 Claude 执行命令。

- 告诉用户：「请打开 Happy，新建一个会话，让那边的 Claude 帮忙执行以下命令：...」
- **这是最后手段**

### 降级决策流程图

```
尝试 t <别名> → ✅ 连上了
  └─ 失败 → 尝试 s <别名> → ✅ 连上了
      └─ 失败 → 查 job 状态判断服务器是否存活
          ├─ 非 Running → 告知用户 job 已挂
          └─ Running（说明是 relay 故障）→ 让用户开 VS Code Tunnel → ✅
              └─ 也挂了 → 让用户用 Happy App → ✅ / ❌ 全部失败
```

---

## 新服务器上线 Checklist

用户获得新机器后，按以下步骤建立完整防护：

### 0. 确定别名

问用户：「要给这个集群起一个什么别名？」如果没有特别想法，按字母顺序自动分配（A → B → C → D ...，别名为 `a0`/`a1`/`b0`/`b1`/...）。

### 1. 注册到本地脚本

在 `scripts/s` 中添加集群配置和 case 分支，在 `scripts/t` 中预留别名。

### 2. 通过 WSS 首次登录

```bash
s <别名>    # 通过跳板机 → az ml job connect-ssh 进入
```

### 3. 部署 Dev Tunnel（Layer 1）

```bash
# 安装到持久存储（重启不丢）
mkdir -p /blob/gaoxin/bin
curl -sSL https://aka.ms/TunnelsCliDownload/linux-x64 -o /blob/gaoxin/bin/devtunnel
chmod +x /blob/gaoxin/bin/devtunnel

# 登录 GitHub
/blob/gaoxin/bin/devtunnel user login -g -d
# ⏸️ 这里会输出一个设备码和 URL（https://github.com/login/device）
# Claude 必须暂停，把设备码告诉用户，等用户在浏览器完成授权后再继续

# 创建固定 tunnel
/blob/gaoxin/bin/devtunnel create --allow-anonymous
# 记录输出的 Tunnel ID

# 添加端口并启动
/blob/gaoxin/bin/devtunnel port create <TUNNEL_ID> -p 22
nohup /blob/gaoxin/bin/devtunnel host <TUNNEL_ID> </dev/null >/tmp/devtunnel-host.log 2>&1 &
disown
```

### 4. 部署 VS Code Tunnel（Layer 3）

```bash
mkdir -p ~/.local/bin
curl -sSL "https://update.code.visualstudio.com/latest/cli-linux-x64/stable" -o /tmp/vscode-cli.tar.gz
tar -xzf /tmp/vscode-cli.tar.gz -C ~/.local/bin

pkill -9 -f "code tunnel" 2>/dev/null; sleep 2
~/.local/bin/code tunnel user logout 2>/dev/null
nohup setsid ~/.local/bin/code tunnel --accept-server-license-terms --name "<UNIQUE_NAME>" </dev/null >~/.code-tunnel.log 2>&1 &
disown
tail -f ~/.code-tunnel.log
# ⏸️ 日志中会出现 "use code XXXX-XXXX" 和一个 URL（https://github.com/login/device）
# Claude 必须暂停，把设备码告诉用户，等用户在浏览器完成授权后再继续
# 设备码 15 分钟过期，过期后需 pkill 重启 tunnel 进程获取新码
```

> ⚠️ AzureML 节点 hostname 都是 `node-0`，**必须显式 `--name`** 给唯一名字。

### 5. 部署 Watchdog 自愈

将 `scripts/remote/` 下的脚本 SCP 或复制到服务器持久存储，修改 TUNNEL_ID 和 TUNNEL_NAME 后启动：

```bash
nohup setsid bash /blob/gaoxin/keep_tunnel_loop.sh </dev/null >/tmp/keep_tunnel_loop.log 2>&1 & disown
```

### 6. 注册固定 Tunnel ID

编辑本地 `scripts/t`，在 `get_tunnel_id()` 中添加映射。

### 7. 验证

```bash
t <别名>       # Dev Tunnel 连接
t status       # 检查在线状态
```

---

## 自愈机制

AzureML 节点没有 crontab 和 systemd，通过后台 loop 实现 watchdog。

### 脚本说明

| 脚本 | 功能 |
|------|------|
| `remote/keep_tunnel.sh` | 检查 devtunnel host，死了就重启（需改 TUNNEL_ID） |
| `remote/keep_code_tunnel.sh` | 检查 code tunnel，死了就重启（需改 TUNNEL_NAME） |
| `remote/keep_tunnel_loop.sh` | 每 5 分钟跑上面两个脚本 |

### 节点重启后

watchdog loop 在内存中，重启后需手动启动一次：

```bash
nohup setsid bash /blob/gaoxin/keep_tunnel_loop.sh </dev/null >/tmp/keep_tunnel_loop.log 2>&1 & disown
```

同时可能需要重新 `devtunnel user login -g -d`（GitHub 授权）。

### 多节点注意

每台节点需要独立的 watchdog 配置（不同的 TUNNEL_ID 和 TUNNEL_NAME）。建议复制为 `keep_tunnel_<别名>.sh` 分别配置。

---

## VS Code Tunnel 常见坑

- **GitHub 设备码过期**：15 分钟内未授权就过期，重启 tunnel 进程会出新码
- **Tunnel 名字撞了**：日志报 `name already in use`，用 `code tunnel rename <newname>`
- **🔥 启动 1 小时后挂、报 `access token is no longer valid`**：
  - 根因：旧进程还在时启动新的，refresh token 没正确保存
  - 修复：**必须先 logout 再启动**
  - 判断：日志不应出现 `Connected to an existing tunnel process`

---

## 日常运维

| 优先级 | 事项 | 频率 |
|--------|------|------|
| 🔴 P0 | 续期 Blob SAS Token（如有） | 每 7 天 |
| 🔴 P0 | 确认占卡程序运行中（如有） | 每日 |
| 🟡 P1 | 确认 tunnel 在线（`t status`） | 每周 |

### 巡检

```bash
s check            # 全部（状态 + GPU）
s check status     # 只查在线状态
s check gpu        # 只查 GPU 利用率
t status           # 检查 Dev Tunnel 状态
```

---

## Instructions for Claude

### 首次使用引导

如果 `scripts/s` 中的集群配置还是模板占位符（`your_email@microsoft.com`、`your_job_name_here` 等），说明用户还没配置过。此时 Claude 应该主动引导用户完成初始化。

**先问用户有哪些服务器**，然后根据类型分别处理：

#### 类型 A：直连 SSH 服务器（树莓派、VPS、云主机等）

最简单的情况，只需要：
1. **问连接信息**：「IP/域名是什么？用户名是什么？用密码还是私钥？」
2. **问别名**：「你想叫它什么？比如 `pi`、`dev` 之类的。」
3. Claude 自动在 `scripts/s` 中添加一条 `ssh <user>@<host>` 即可，在 `~/.ssh/config` 中添加 Host 配置
4. **不需要** tunnel、跳板机、devtunnel 等复杂配置

#### 类型 B：AzureML 集群（需要跳板机 + WSS relay）

复杂情况，需要完整的三层防护：
1. **问跳板机信息**：「你的跳板机 SSH 别名是什么？（比如 `msra`）用户名是什么？」
2. **问集群信息**：「请告诉我每个集群的：
   - `az ml job connect-ssh` 的完整命令（或 job 名、workspace、resource group、subscription）
   - 跳板机上需要 `sudo su` 到哪个用户
   - 这个集群有几个节点」
3. **问别名**：「你想给这些集群起什么别名？不想起名的话我按 A/B/C/D 顺序分配。」
4. **问 SSH 私钥**：「连接服务器的 SSH 私钥放在哪里？（比如 `~/.ssh/azml_id_rsa`）」
5. **检查依赖**：确认 `~/.local/bin` 在 PATH 中、脚本已 symlink、`devtunnel` CLI 已安装

收集完信息后，Claude 自动：
- 更新 `scripts/s` 中的集群配置和 case 分支
- 更新 `scripts/t` 中的 `get_user()` 映射
- 更新 `scripts/s-check` 中的 `CLUSTERS` 数组
- 通过 `s <别名>` 首次登录，部署 Dev Tunnel 和 VS Code Tunnel（需要用户配合完成设备码授权）

#### 类型 C：K8S 集群（kubectl 管理）

1. **问管理节点**：「K8S 管理节点怎么连？（SSH 别名或 IP）」
2. **问 namespace 和 pod 信息**
3. Claude 配置 `scripts/s` 和 `~/.ssh/config`（通过 `kubectl exec + ncat` 桥接）

### 连接诊断决策树

当用户说「连不上服务器」或需要在服务器执行命令时：

```
1. 确认目标服务器别名
2. 尝试 Dev Tunnel（手动构建 devtunnel connect + ssh）  ← Claude 自己执行
3. 失败 → 尝试 WSS 编程式访问（动态获取 WSS URL + ssh ProxyCommand）← Claude 自己执行
4. 失败 → 查 job 状态判断服务器是否存活：
   - 非 Running → 告知用户 job 已挂
   - Running → 说明是 relay 故障，继续降级：
5. 让用户开 VS Code Tunnel            ← 给用户浏览器链接
6. 也挂了 → 让用户用 Happy App        ← 给用户完整命令，让远程 Claude 执行
```

**注意：`s <别名>` 和 `t <别名>` 都是交互式登录脚本，不支持传远程命令。** Claude 需要自动化执行命令时，应使用以下方式：

- **Dev Tunnel 方式**：手动 `devtunnel connect <TUNNEL_ID>` 获取本地端口，再 `ssh -p <port> user@127.0.0.1 "command"`
- **WSS 方式**：动态获取 WSS URL 后通过 ProxyCommand 执行（见「Layer 2 → WSS 编程式访问」章节）

### 新服务器上线

- **先问别名**：问用户要不要起名，没有的话按字母顺序分配
- 按「新服务器上线 Checklist」部署
- 部署 devtunnel（放持久存储，创建固定 tunnel，启动 host）
  - ⚠️ `devtunnel user login -g -d` 和 `code tunnel` 启动时都会输出**设备码**，Claude 必须暂停并把设备码告诉用户，等用户在浏览器 https://github.com/login/device 完成授权后才能继续
- 部署 code tunnel（同样需要用户完成设备码授权）
- 部署完成后更新 `scripts/s`、`scripts/t`、本 skill

### 配置变更

job 名、tunnel ID 等变化时，需同步更新：
- `scripts/s` — WSS 登录脚本
- `scripts/t` — Dev Tunnel 登录脚本
- `scripts/s-check` — 巡检脚本
- `~/.ssh/config` — SSH 配置
- 本 skill 文档
