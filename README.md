# MSRA Skills Plugin for Claude Code

A comprehensive Claude Code plugin that bundles server management and Azure Blob storage tools, designed for researchers and engineers working with AzureML / K8S clusters and remote servers.

---

## What is This?

**msra-skills** is a **Claude Code Plugin** — a collection of specialized skills that extend Claude Code's capabilities for infrastructure and DevOps tasks. Once installed, Claude can automatically:

- **Log into remote servers** (SSH, AzureML WSS, Dev Tunnel) with multi-layer failover
- **Manage Azure Blob storage** (mount, upload, download, SAS token rotation)
- **Monitor GPU utilization** and cluster health
- **Deploy and self-heal tunnels** for persistent remote access
- **Guide you through onboarding new servers** step by step

---

## Skills Included

| Skill | Trigger Keywords | Description |
|-------|-----------------|-------------|
| **server-manager** | server, cluster, GPU, login, tunnel, SSH | Full server lifecycle management: login via SSH/WSS/DevTunnel, status checks, GPU monitoring, tunnel deployment with watchdog auto-recovery. Supports direct SSH servers (Raspberry Pi, VPS, etc.) and complex AzureML/K8S clusters. |
| **blob-manager** | blob, SAS token, remount, azcopy, upload, download | Azure Blob storage operations: BlobFuse mount/remount, AzCopy high-speed transfers (~5 MB/s), Python SDK for listing/metadata, SAS token lifecycle management with 7-day expiry alerts. |

---

## Installation

### Method 1: As a Plugin (Recommended)

This installs all skills at once under the `msra-skills:` namespace.

```bash
# Clone the repository
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills

# Launch Claude Code with the plugin
claude --plugin-dir ~/.claude/plugins/msra-skills
```

After loading, skills are available as:
- `msra-skills:server-manager` — triggered automatically when you mention servers, clusters, GPU, etc.
- `msra-skills:blob-manager` — triggered automatically when you mention blob, SAS token, remount, etc.

### Method 2: As Standalone Skills

If you prefer shorter skill names (without the `msra-skills:` prefix):

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

Skills are then available as `/server-manager` and `/blob-manager`.

### Method 3: Direct Path Loading

If you don't want to move files:

```bash
claude --plugin-dir /path/to/msra-skills
```

---

## First-Time Setup

After installation, Claude will **automatically guide you** through initial configuration when you first use any skill. Here's what to expect:

### Server Manager Setup

1. **Claude asks what servers you have** — direct SSH (Pi, VPS), AzureML clusters, or K8S pods
2. **You provide connection info** — IPs, usernames, job names, subscriptions, etc.
3. **Claude configures scripts** — updates `scripts/s`, `scripts/t`, `scripts/s-check` automatically
4. **Symlink helper scripts to PATH**:
   ```bash
   mkdir -p ~/.local/bin
   SKILL_DIR="$HOME/.claude/plugins/msra-skills/skills/server-manager"
   for script in s t s-check vscode-azml-proxy.sh vscode-k8s-proxy.sh; do
     ln -sf "${SKILL_DIR}/scripts/${script}" ~/.local/bin/${script}
   done
   export PATH="$HOME/.local/bin:$PATH"  # add to .zshrc / .bashrc
   ```
5. **Install Dev Tunnel CLI** (for AzureML users):
   ```bash
   # macOS ARM
   curl -sSL https://aka.ms/TunnelsCliDownload/osx-arm64-zip -o /tmp/devtunnel.zip
   unzip -o /tmp/devtunnel.zip -d ~/.local/bin/
   devtunnel user login --github
   ```

### Blob Manager Setup

1. **Create a SAS config file** at `~/.claude/skills/blob-manager/blob_sas.json`:
   ```json
   {
     "container_url": "https://YOUR_ACCOUNT.blob.core.windows.net/YOUR_CONTAINER?sv=...&sig=...",
     "account": "YOUR_ACCOUNT",
     "container": "YOUR_CONTAINER",
     "expires": "2026-05-05T07:45:00Z"
   }
   ```
2. **Edit `scripts/run_remount_all.sh`** to set your cluster aliases (used for batch BlobFuse remount)
3. **Install dependencies**:
   ```bash
   pip install azure-storage-blob
   # azcopy should be installed locally for large file transfers
   ```

---

## What Each Skill Can Do

### Server Manager

| Feature | Command / Action | Details |
|---------|-----------------|---------|
| **SSH Login** | `s <alias>` | Connect via AzureML WSS relay (through jumpbox) |
| **Dev Tunnel Login** | `t <alias>` | Fast direct connection bypassing WSS relay |
| **Tunnel Status** | `t status` | Check if Dev Tunnels are online |
| **Health Check** | `s check` | Full cluster inspection (status + GPU) |
| **GPU Check** | `s check gpu` | GPU utilization across all nodes |
| **New Server Onboarding** | Guided workflow | Deploy Dev Tunnel + VS Code Tunnel + Watchdog |
| **Auto-Failover** | Automatic | 4-layer fallback: DevTunnel → WSS → VS Code Tunnel → Happy App |
| **Self-Healing** | Watchdog scripts | Auto-restart tunnels every 5 minutes on remote nodes |

### Blob Manager

| Feature | Tool | Details |
|---------|------|---------|
| **Large File Transfer** | AzCopy | ~5 MB/s multi-threaded upload/download |
| **List / Browse** | Python SDK | List directories, check file sizes, read metadata |
| **Small File I/O** | Python SDK | Upload/download small files, batch delete |
| **BlobFuse Remount** | Shell script | Batch remount `/blob_old` on all cluster nodes after SAS expiry |
| **SAS Token Management** | `blob_sas.json` | Store, update, and validate SAS tokens |

---

## Project Structure

```
msra-skills/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (name, version, author)
├── skills/
│   ├── server-manager/
│   │   ├── SKILL.md             # Full skill documentation & Claude instructions
│   │   └── scripts/
│   │       ├── s                # WSS login script
│   │       ├── t                # Dev Tunnel login script
│   │       ├── s-check          # Health check script
│   │       ├── vscode-azml-proxy.sh   # VS Code AzureML SSH proxy
│   │       ├── vscode-k8s-proxy.sh    # VS Code K8S SSH proxy
│   │       └── remote/          # Watchdog scripts for deployment on servers
│   │           ├── keep_tunnel.sh
│   │           ├── keep_code_tunnel.sh
│   │           └── keep_tunnel_loop.sh
│   └── blob-manager/
│       ├── SKILL.md             # Full skill documentation & Claude instructions
│       └── scripts/
│           ├── remount_blob_old.sh    # Per-node BlobFuse remount
│           └── run_remount_all.sh     # Batch remount across all nodes
├── README.md                    # This file (English)
├── README_CN.md                 # Chinese version
└── .gitignore
```

---

## License

MIT

---

## Author

**gaoxin492** — [GitHub](https://github.com/gaoxin492/msra-skills)
