# MSRA Skills

A Claude Code plugin bundling server management and Azure Blob storage tools for AzureML/K8S cluster operations.

## Skills Included

| Skill | Description |
|-------|-------------|
| **server-manager** | 服务器登录、状态巡检、GPU 利用率、Tunnel 部署与自愈。支持直连 SSH 和 AzureML/K8S 集群。 |
| **blob-manager** | Azure Blob 存储管理：BlobFuse 重挂载、AzCopy 传输、Python SDK 操作、SAS Token 管理。 |

## Installation

### As a Claude Code Plugin (Recommended)

```bash
# Option 1: Load directly
claude --plugin-dir /path/to/msra-skills

# Option 2: Clone and load
git clone https://github.com/gaoxin492/msra-skills.git ~/.claude/plugins/msra-skills
claude --plugin-dir ~/.claude/plugins/msra-skills
```

After loading, skills are available as:
- `/msra-skills:server-manager`
- `/msra-skills:blob-manager`

### As Standalone Skills

If you prefer standalone installation (shorter `/server-manager` names):

```bash
git clone https://github.com/gaoxin492/msra-skills.git /tmp/msra-skills
cp -r /tmp/msra-skills/skills/server-manager ~/.claude/skills/
cp -r /tmp/msra-skills/skills/blob-manager ~/.claude/skills/
```

## First-Time Setup

Both skills require configuration before use:

### Server Manager
Edit `skills/server-manager/scripts/s` to fill in your cluster credentials (jumpbox, user email, job names, subscriptions, etc.).

### Blob Manager
1. Create a `blob_sas.json` with your Azure SAS token
2. Edit `skills/blob-manager/scripts/run_remount_all.sh` to set your cluster aliases

See each skill's `SKILL.md` for detailed instructions.

## License

MIT
