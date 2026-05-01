# MSRA Skills — Claude Code Plugin

> A collection of Claude Code skills for cluster training, data management, and server operations at MSRA.

---

## Philosophy

Managing multiple clusters at MSRA involves a lot of tedious, repetitive work: logging into the right node, checking GPU status, rotating SAS tokens, remounting Blob storage, setting up tunnels, etc. These tasks are perfect candidates for packaging into skills and handing off to your local Claude Code.

With **msra-skills**, Claude keeps track of all your clusters, credentials, and configurations in one place. You don't need to remember which alias maps to which job, or manually SSH into 10 nodes to remount storage. When you have many clusters, this makes a real difference in day-to-day research efficiency.

We currently ship two skills, **Server Manager** and **Blob Manager**, but this is an open and extensible plugin. New skills can be added anytime as needs emerge (experiment tracking, job scheduling, log analysis, etc.).

---

## Changelog

### v1.4.0 (2026-05-01)

**Server Manager**
- **Added WSS programmatic access**: Claude can now execute commands on AzureML nodes non-interactively by dynamically fetching the WSS URL and using SSH ProxyCommand. No `expect` needed. This is the critical fallback when Dev Tunnel is unavailable.
- **Updated connection diagnostic decision tree**: Clearly distinguishes interactive scripts (`s`/`t`) from programmatic access (devtunnel connect + ssh / WSS ProxyCommand), so Claude picks the right method in automated scenarios.

### v1.3.0

- Initial public release with Server Manager and Blob Manager

---

## Installation

### Method 1: `claude plugin install` (Recommended)

Register our repo as a marketplace, then install through the plugin system:

```bash
claude plugin marketplace add gaoxin492/msra-skills
claude plugin install msra-skills
```

Restart Claude Code and you'll see `msra-skills:server-manager` and `msra-skills:blob-manager`. No extra flags needed on every launch.

### Method 2: Git Clone

Clone the repo and load it as a plugin manually. Useful for development or if you want direct file access.

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills
claude --plugin-dir ~/.claude/plugins/msra-skills
```

Note: you need to pass `--plugin-dir` each time, or set up a shell alias:

```bash
alias claude='claude --plugin-dir ~/.claude/plugins/msra-skills'
```

### Method 3: As Standalone Skills

Copy individual skills into `~/.claude/skills/`. Claude auto-discovers them, no marketplace needed:

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

Skills are available as `/server-manager` and `/blob-manager` (shorter names, no `msra-skills:` prefix).

### Method 4: Project-Level (Team Sharing)

Add to a project repo so your whole team gets the skills via Git:

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/ .claude/skills/
git add .claude/skills/
```

---

## Updating

Personal config files (`s`, `t`, `s-check`, `blob_sas.json`) live outside the plugin directory and will never be overwritten by updates.

**Method 1 users** (`claude plugin install`):

```bash
claude plugin marketplace update msra-skills-marketplace
claude plugin update msra-skills@msra-skills-marketplace
```

Restart Claude Code to apply.

**Method 2 users** (git clone):

```bash
cd ~/.claude/plugins/msra-skills
git pull
```

---

## What Can It Do?

Once installed, just talk to Claude naturally. The right skill activates automatically:

- *"帮我登录 b0"* → SSH into cluster B node 0 (with multi-layer failover)
- *"查一下所有集群 GPU 利用率"* → Health check across all nodes
- *"SAS token 过期了，重新挂载 blob"* → Auto-generate a new SAS token and batch remount
- *"上传这个文件到 blob"* → AzCopy high-speed transfer
- *"帮我上线一台新服务器"* → Guided onboarding with tunnel deployment

---

## Skill Details

### Server Manager

Manages login, monitoring, and tunnel infrastructure for all your remote servers.

AzureML clusters are typically accessed via `az ml job connect-ssh`, which routes through a **WSS (WebSocket) relay**. This works but can be slow (30+ second handshake) and suffers from known intermittent relay outages. To provide faster and more reliable access, Server Manager also deploys **tunnels** on each node:

- **Dev Tunnel** provides direct SSH access from your terminal, bypassing the WSS relay entirely. This is the primary connection method and is also what allows Claude to manage your servers directly.
- **VS Code Tunnel** lets you open a full VS Code editor in the browser, connected to the remote node. Useful when both WSS and Dev Tunnel are down, or when you want a GUI.

Both tunnels are supervised by a **watchdog** process on the server that checks every 5 minutes and auto-restarts any dead tunnel.

When connecting, Server Manager tries each method in order (Dev Tunnel → WSS → VS Code Tunnel) and automatically falls back if one fails.

| Feature | Command | Details |
|---------|---------|---------|
| WSS Login | `s <alias>` | Connect via AzureML WSS relay through jumpbox |
| Dev Tunnel Login | `t <alias>` | Fast direct SSH, bypasses WSS relay |
| Health Check | `s check` | Job status + GPU utilization across all clusters |
| GPU Monitor | `s check gpu` | GPU utilization on all nodes |
| Tunnel Status | `t status` | Check which Dev Tunnels are online |
| New Server Onboarding | Guided | Deploy Dev Tunnel + VS Code Tunnel + watchdog |
| Self-Healing | Watchdog | Auto-restart dead tunnels every 5 min on remote nodes |

Also supports direct SSH servers (Raspberry Pi, VPS, etc.) and K8S pods (via `kubectl exec` bridging).

### Blob Manager

Manages Azure Blob storage access for your training clusters.

AzureML nodes typically mount Azure Blob containers as local directories using **BlobFuse**. This requires a valid **SAS token**, which expires every 7 days. When it expires, all mounts go stale and training jobs that try to write checkpoints can crash.

Blob Manager automates the entire renewal cycle:

1. **Generate a new SAS token** automatically via `az CLI` on the jumpbox (no need to open Azure Storage Explorer)
2. **Batch remount** BlobFuse on all cluster nodes with a single command
3. **Verify** the mount is working

For file transfers between your local machine and Blob storage, it supports:

- **AzCopy** for large files (multi-threaded, ~5 MB/s)
- **Python SDK** (`azure-storage-blob`) for listing directories, reading metadata, and small file operations

| Feature | Tool | Details |
|---------|------|---------|
| SAS Token Auto-Renewal | az CLI on jumpbox | Generate new token without Storage Explorer |
| BlobFuse Remount | Shell script | Batch remount `/blob_old` on all nodes |
| Large File Transfer | AzCopy | ~5 MB/s multi-threaded upload/download |
| List / Browse | Python SDK | Directories, file sizes, metadata |
| Small File I/O | Python SDK | Upload, download, batch delete |

> 💡 More skills coming. Contributions welcome!

---

## First-Time Setup

After installation, Claude will **automatically guide you** through initial configuration. It will ask about your servers, clusters, and credentials, then configure everything for you.

### Server Manager

1. Claude asks what servers you have (direct SSH, AzureML, K8S)
2. You provide connection info (IPs, usernames, job names, subscriptions)
3. Claude copies the template scripts to `~/.local/bin/` and fills in your cluster info
4. Ensure `~/.local/bin` is in your PATH:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"  # add to .zshrc / .bashrc
   ```
5. Install Dev Tunnel CLI (for AzureML users):
   ```bash
   curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
   unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
   devtunnel user login --github
   ```

### Blob Manager

1. Create `~/.config/msra-skills/blob_sas.json` with your Azure SAS token (or let Claude auto-generate one via the jumpbox)
2. Install dependencies: `pip install azure-storage-blob`
3. (Optional) Install `azcopy` for large file transfers

See each skill's `SKILL.md` for detailed documentation.

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

## Developer Guide

### Setup

Clone the repo to a working directory (not the plugin install path):

```bash
git clone https://github.com/gaoxin492/msra-skills.git ~/Projects/msra-skills
cd ~/Projects/msra-skills
```

You can also use `claude plugin install` normally for daily use. The dev clone and the installed plugin are independent.

### Making Changes

Edit SKILL.md, scripts, README, or add new skills. Key files:

| What to change | Where |
|----------------|-------|
| Skill behavior / Claude instructions | `skills/<name>/SKILL.md` |
| Script templates | `skills/<name>/scripts/*.example` |
| Helper scripts (non-personal) | `skills/<name>/scripts/*.sh` |
| Plugin metadata | `.claude-plugin/plugin.json` |
| README | `README.md`, `README_CN.md` |

### Publishing

After making changes, bump the version and push:

```bash
# 1. Edit .claude-plugin/plugin.json, bump "version" (e.g. "1.2.0" → "1.3.0")

# 2. Commit and push
git add -A
git commit -m "feat: describe your change"
git push
```

That's it. Users can now update via:

```bash
claude plugin marketplace update msra-skills-marketplace
claude plugin update msra-skills@msra-skills-marketplace
```

The version bump is required; without it, `claude plugin update` won't detect the change.

### Adding a New Skill

1. Create `skills/your-skill-name/SKILL.md` with a YAML frontmatter `description` field
2. Add helper scripts under `skills/your-skill-name/scripts/` (use `.example` suffix for templates that contain user-specific config)
3. Update `.gitignore` if the skill has personal config files
4. Bump version in `.claude-plugin/plugin.json`
5. Push

### Architecture

```
Plugin directory (managed by claude plugin install, read-only for users)
  └── SKILL.md              ← Claude reads this to know what it can do
  └── scripts/*.example     ← Templates for personal scripts
  └── scripts/*.sh          ← Shared helper scripts (non-personal)

~/.local/bin/ (user's own, never touched by plugin updates)
  └── s, t, s-check         ← Personal scripts with cluster credentials

~/.config/msra-skills/ (user's own)
  └── blob_sas.json         ← SAS token
```

---

## License

MIT License
