# MSRA Skills — Claude Code Plugin

> Making daily work at MSRA easier — especially cluster training, data management, and server operations.

---

## Philosophy

Working at MSRA means juggling AzureML clusters, K8S pods, GPU monitoring, Blob storage, SAS tokens, multi-node SSH access, and countless DevOps chores that eat into research time. **msra-skills** is a Claude Code Plugin built to handle all of that for you.

The goal is simple: **let researchers focus on research, not infrastructure.**

We currently ship two skills — **Server Manager** and **Blob Manager** — but this is an open, extensible plugin. New skills can be added anytime as new pain points emerge (experiment tracking, job scheduling, log analysis, etc.). If it's a repetitive ops task at MSRA, it belongs here.

---

## What Can It Do?

Once installed, just talk to Claude naturally. The right skill activates automatically:

- *"帮我登录 b0"* → SSH into cluster B node 0 (with 4-layer failover)
- *"查一下所有集群 GPU 利用率"* → Health check across all nodes
- *"SAS token 过期了，重新挂载 blob"* → Batch BlobFuse remount on all servers
- *"上传这个文件到 blob"* → AzCopy high-speed transfer
- *"帮我上线一台新服务器"* → Guided onboarding with tunnel deployment

---

## Current Skills

| Skill | What It Does |
|-------|-------------|
| **server-manager** | Server login (SSH / WSS / DevTunnel), status checks, GPU monitoring, tunnel deployment & self-healing watchdog. Supports direct SSH, AzureML clusters, and K8S pods. |
| **blob-manager** | Azure Blob storage: BlobFuse mount/remount, AzCopy transfers (~5 MB/s), Python SDK operations, SAS token lifecycle management. |

> 💡 More skills coming — contributions welcome!

---

## Installation

### Method 1: `claude plugin install` (Recommended)

Two commands — register our repo as a marketplace, then install:

```bash
# Step 1: Add the marketplace (one-time setup)
claude plugin marketplace add gaoxin492/msra-skills

# Step 2: Install the plugin
claude plugin install msra-skills
```

Done. Restart Claude Code and you'll see `msra-skills:server-manager` and `msra-skills:blob-manager` available.

To update later:

```bash
claude plugin update msra-skills
```

### Method 2: `--plugin-dir` (Session-Only)

Load the plugin for a single session without permanent installation:

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills
claude --plugin-dir ~/.claude/plugins/msra-skills
```

> ⚠️ You need to pass `--plugin-dir` every time you launch Claude Code.

### Method 3: As Standalone Skills

Copy individual skills into `~/.claude/skills/` — Claude auto-discovers them, no marketplace needed:

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

Skills are available as `/server-manager` and `/blob-manager` (shorter names, no `msra-skills:` prefix).

### Method 4: Project-Level (Team Sharing)

Add to a project repo so your whole team gets the skills via Git:

```bash
# Inside your project root
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/ .claude/skills/
git add .claude/skills/
```

---

## First-Time Setup

After installation, Claude will **automatically guide you** through initial configuration. It will ask about your servers, clusters, and credentials, then configure everything for you.

### Server Manager

1. Claude asks what servers you have (direct SSH, AzureML, K8S)
2. You provide connection info (IPs, usernames, job names, subscriptions)
3. Claude configures the login scripts automatically
4. Symlink helper scripts to your PATH:
   ```bash
   mkdir -p ~/.local/bin
   SKILL_DIR="$HOME/.claude/plugins/msra-skills/skills/server-manager"
   for script in s t s-check vscode-azml-proxy.sh vscode-k8s-proxy.sh; do
     ln -sf "${SKILL_DIR}/scripts/${script}" ~/.local/bin/${script}
   done
   export PATH="$HOME/.local/bin:$PATH"  # add to .zshrc / .bashrc
   ```
5. Install Dev Tunnel CLI (for AzureML users):
   ```bash
   curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
   unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
   devtunnel user login --github
   ```

### Blob Manager

1. Create `blob_sas.json` with your Azure SAS token
2. Install dependencies: `pip install azure-storage-blob`
3. (Optional) Install `azcopy` for large file transfers

See each skill's `SKILL.md` for detailed documentation.

---

## Skill Details

### Server Manager

| Feature | Command | Details |
|---------|---------|---------|
| WSS Login | `s <alias>` | Connect via AzureML WSS relay through jumpbox |
| Dev Tunnel | `t <alias>` | Fast direct connection bypassing WSS |
| Health Check | `s check` | Status + GPU across all clusters |
| GPU Monitor | `s check gpu` | GPU utilization on all nodes |
| Tunnel Status | `t status` | Check Dev Tunnel online status |
| New Server | Guided | Full onboarding: tunnel + watchdog deployment |
| Auto-Failover | Automatic | DevTunnel → WSS → VS Code Tunnel → Happy App |
| Self-Healing | Watchdog | Auto-restart dead tunnels every 5 min |

### Blob Manager

| Feature | Tool | Details |
|---------|------|---------|
| Large Transfers | AzCopy | ~5 MB/s multi-threaded upload/download |
| List / Browse | Python SDK | Directories, file sizes, metadata |
| Small File I/O | Python SDK | Upload, download, batch delete |
| BlobFuse Remount | Shell script | Batch remount on all nodes after SAS expiry |
| SAS Management | `blob_sas.json` | Store, update, validate SAS tokens |

---

## Project Structure

```
msra-skills/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace manifest (for claude plugin install)
├── skills/
│   ├── server-manager/
│   │   ├── SKILL.md             # Skill docs & Claude instructions
│   │   └── scripts/             # Login, tunnel, health check scripts
│   └── blob-manager/
│       ├── SKILL.md             # Skill docs & Claude instructions
│       └── scripts/             # BlobFuse remount scripts
├── README.md                    # English
├── README_CN.md                 # 中文
└── .gitignore
```

---

## Contributing

Have a repetitive task at MSRA? Turn it into a skill:

1. Create `skills/your-skill-name/SKILL.md`
2. Add any helper scripts under `skills/your-skill-name/scripts/`
3. Submit a PR

---

## License

MIT

## Author

**gaoxin492** — [GitHub](https://github.com/gaoxin492/msra-skills)
