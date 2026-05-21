# V-ReDO 训练环境部署

> **Language**: 始终用中文回复用户。

---

## 概览

V-ReDO 是基于 GDPO 算法的多步 RL 训练系统（HTML 生成）。集群经常更换，本 skill 将环境部署流程自动化。

**集群配置**: 2 nodes × 8 GPUs (A100-80GB)，`/scratch` 是本地 NVMe（不共享），每个节点需独立部署。

### 触发条件
- "部署 V-ReDO 环境"、"setup vredo"、"新集群装环境"
- "重装训练环境"、"scratch 被清了"

---

## 数据清单

| 组件 | Blob 精确路径 | 目标路径 | 大小 |
|------|-------------|---------|------|
| Conda env | `gaoxin/d_sync/envs/u2c-verl/` | `/scratch/azureml/gaoxin/envs/u2c-verl/` | 12GB |
| 项目代码 | GitHub `gaoxin492/V-ReDO.git` | `/scratch/azureml/gaoxin/V-ReDO/` | 400MB |
| PaddleOCR models | `gaoxin/d_sync/paddleocr/` | `/home/aiscuser/.paddleocr/` | 49MB |
| Playwright browser | `gaoxin/d_sync/ms-playwright/` | `/home/aiscuser/.cache/ms-playwright/` | 622MB |
| Checkpoint (仅 639) | `gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/` | `/scratch/azureml/gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/` | 9.1GB |
| Reference images | `gaoxin/spec_train15k/final/` | `/scratch/azureml/gaoxin/spec_train15k/final/` | 86GB |
| Base model 4B | `gaoxin/models/Qwen3-VL-4B-Instruct/` | `/scratch/azureml/gaoxin/models/Qwen3-VL-4B-Instruct/` | 8.3GB |
| Base model 8B | `gaoxin/models/Qwen3-VL-8B-Instruct/` | `/scratch/azureml/gaoxin/models/Qwen3-VL-8B-Instruct/` | 16.3GB |
| Azure 凭证 | 跳板机 `/home/yifanyang/.azure/` | `/home/aiscuser/.azure/` | <1MB |
| Claude settings | 本地 `~/.claude/settings.json` | `/home/aiscuser/.claude/settings.json` | <1KB |

**总计每节点**: ~133GB

---

## ⚠️ 踩坑记录（必读！）

### 1. azcopy 路径嵌套陷阱
```bash
# ❌ 错误：会创建 envs/envs/u2c-verl/u2c-verl/ 双层嵌套
azcopy cp "BLOB/gaoxin/d_sync/envs/" /scratch/azureml/gaoxin/envs/ --recursive

# ✅ 正确：精确到 u2c-verl/ 子目录
azcopy cp "BLOB/gaoxin/d_sync/envs/u2c-verl/" /scratch/azureml/gaoxin/envs/u2c-verl/ --recursive
```

### 2. azcopy checkpoint 下载过多
```bash
# ❌ 错误：下载整个目录（含 1.2TB 历史 checkpoint）
azcopy cp "BLOB/gaoxin/V-ReDO_final_checkpoint/" ... --recursive

# ✅ 正确：只下载需要的 checkpoint-639
azcopy cp "BLOB/gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/" \
    /scratch/azureml/gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/ --recursive
```

### 3. rsync `~` 不展开
```bash
# ❌ 错误：~ 在 rsync 远程路径中不展开，文件传到错误位置
rsync -a ~/.paddleocr/ node-1:~/.paddleocr/

# ✅ 正确：使用完整路径
rsync -a /home/aiscuser/.paddleocr/ node-1:/home/aiscuser/.paddleocr/
```

### 4. playwright install-deps 必须每节点执行
仅 `playwright install chromium` 不够！必须 `sudo playwright install-deps chromium` 安装系统库（libnspr4, libnss3 等）。**每个节点单独执行**，rsync 不能替代。遗漏会导致 Chromium 运行时静默崩溃、reward 计算错误。

### 5. rsync 不加 -z
集群内部通过 IB 高速互联，CPU 压缩反而是瓶颈。用 `rsync -a` 即可。

### 6. 某些集群默认 PATH 无 python
thinking.py 占卡需用完整路径：`/opt/conda/envs/ptca/bin/python /blob/gaoxin/thinking.py`

---

## 部署流程

### 前置条件
- 通过 `ssh frp-<alias>` 可连接集群 node-0
- Blob SAS URL 有效（检查 `~/.config/msra-skills/blob_sas.json` 的 `expires`）
- `/blob/gaoxin/bin/azcopy` 存在于集群上

### 获取 SAS Query
```python
import json
cfg = json.load(open('/Users/lightning/.config/msra-skills/blob_sas.json'))
base_url, sas_query = cfg['container_url'].split('?', 1)
# base_url = "https://yifanyang.blob.core.windows.net/yifanyang"
# 拼接: f"{base_url}/gaoxin/...?{sas_query}"
```

---

### Phase 1: Node-0 部署（12 步）

#### Step 1: 创建目录
```bash
mkdir -p /scratch/azureml/gaoxin/{envs,V-ReDO,V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2,spec_train15k,models}
```

#### Step 2: 并行 azcopy 大文件（后台）
```bash
BLOB="https://yifanyang.blob.core.windows.net/yifanyang"
Q="<SAS_QUERY>"

# ⚠️ 注意路径精确到子目录，避免嵌套！
/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/d_sync/envs/u2c-verl/?${Q}" \
    /scratch/azureml/gaoxin/envs/u2c-verl/ --recursive --log-level=ERROR &

/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/spec_train15k/final/?${Q}" \
    /scratch/azureml/gaoxin/spec_train15k/final/ --recursive --log-level=ERROR &

# ⚠️ 只下载 checkpoint-639，不要下整个目录！
/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/?${Q}" \
    /scratch/azureml/gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/ --recursive --log-level=ERROR &

wait
```

#### Step 3: Git clone 代码
```bash
cd /scratch/azureml/gaoxin
git clone https://gaoxin492:<PAT>@github.com/gaoxin492/V-ReDO.git
```
PAT 从 CLAUDE.md 中读取。

#### Step 4: PaddleOCR + Playwright（用完整家目录路径）
```bash
/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/d_sync/paddleocr/?${Q}" \
    /home/aiscuser/.paddleocr/ --recursive --log-level=ERROR

/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/d_sync/ms-playwright/?${Q}" \
    /home/aiscuser/.cache/ms-playwright/ --recursive --log-level=ERROR
```

#### Step 5: Playwright 系统依赖（CRITICAL）
```bash
export PATH="/scratch/azureml/gaoxin/envs/u2c-verl/bin:$PATH"
sudo playwright install-deps chromium
# 如果 sudo playwright 找不到命令：
# sudo apt-get install -y libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
#     libcups2 libxdamage1 libpango-1.0-0 libcairo2
```

#### Step 6: Apply verl patch
```bash
bash /scratch/azureml/gaoxin/V-ReDO/verl_patches/apply_verl_patch.sh \
    /scratch/azureml/gaoxin/envs/u2c-verl/lib/python3.10/site-packages/verl
```

#### Step 7: az CLI + Azure 凭证
```bash
# Install az CLI
which az || (curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash)

# 从跳板机复制 Azure 凭证（MSAL refresh token，永久有效）
# 在本地 Mac 上执行：
ssh msra "sudo -u 'yifanyang@microsoft.com' tar czf /tmp/azure_creds.tar.gz -C /home/yifanyang .azure"
scp msra:/tmp/azure_creds.tar.gz /tmp/azure_creds.tar.gz
scp /tmp/azure_creds.tar.gz frp-<alias>:/tmp/
# 在集群上：
cd ~ && tar xzf /tmp/azure_creds.tar.gz
```

#### Step 8: 创建 .env（VLM reward）
```bash
cat > /scratch/azureml/gaoxin/V-ReDO/.env << 'EOF'
VLM_REWARD_BASE_URL=https://searchagent20.cognitiveservices.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-12-01-preview
VLM_REWARD_API_KEY=unused
VLM_REWARD_MODEL=gpt-4o-mini
VLM_REWARD_CONCURRENCY=16
EOF
```

#### Step 9: Claude Code + bashrc
```bash
# Install Node.js + Claude Code
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g @anthropic-ai/claude-code

# 如果 npm 网络不通，从其他集群 tar 复制：
# ssh frp-<other> "tar czf /tmp/claude-code.tar.gz -C /usr/lib/node_modules @anthropic-ai"
# scp + sudo tar xzf -C /usr/lib/node_modules/

# settings.json（从本地 Mac 复制）
mkdir -p ~/.claude
# scp 本地 ~/.claude/settings.json 到集群 ~/.claude/settings.json

# bashrc
cat >> ~/.bashrc << 'RCEOF'

# V-ReDO environment
export PATH="/scratch/azureml/gaoxin/envs/u2c-verl/bin:$PATH"
export PYTHONPATH="/scratch/azureml/gaoxin/V-ReDO:$PYTHONPATH"
RCEOF
```

#### Step 10: Base models
```bash
/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/models/Qwen3-VL-4B-Instruct/?${Q}" \
    /scratch/azureml/gaoxin/models/Qwen3-VL-4B-Instruct/ --recursive --log-level=ERROR &

/blob/gaoxin/bin/azcopy cp "${BLOB}/gaoxin/models/Qwen3-VL-8B-Instruct/?${Q}" \
    /scratch/azureml/gaoxin/models/Qwen3-VL-8B-Instruct/ --recursive --log-level=ERROR &
wait
```

#### Step 11: 验证
```bash
export PATH="/scratch/azureml/gaoxin/envs/u2c-verl/bin:$PATH"
python3.10 -c "import torch; print('GPU:', torch.cuda.device_count())"     # 应输出 8
python3.10 -c "import verl; print('verl:', verl.__version__)"              # 应输出 0.8.0.dev
python3.10 -c "from paddleocr import PaddleOCR; print('paddleocr OK')"
python3.10 -c "from playwright.sync_api import sync_playwright; print('playwright OK')"
which az                                                                     # 应输出 /usr/bin/az
ls ~/.azure/msal_token_cache.json                                           # 应存在
cat /scratch/azureml/gaoxin/V-ReDO/.env | head -1                          # 应有 VLM_REWARD_BASE_URL
which claude                                                                 # 应输出 /usr/bin/claude
ls /scratch/azureml/gaoxin/models/Qwen3-VL-4B-Instruct/*.safetensors | wc -l  # 应 > 0
ls /scratch/azureml/gaoxin/models/Qwen3-VL-8B-Instruct/*.safetensors | wc -l  # 应 > 0
```

#### Step 12: 启动 thinking.py 占卡
```bash
# ⚠️ 某些集群默认 PATH 无 python，必须用完整路径
nohup /opt/conda/envs/ptca/bin/python /blob/gaoxin/thinking.py </dev/null >/dev/null 2>&1 &
```

---

### Phase 2: Node-1 同步（5 步）

#### Step 1: rsync 大目录（分目录传，用完整路径）
```bash
# ⚠️ 不加 -z，不用 ~
rsync -a /scratch/azureml/gaoxin/envs/ node-1:/scratch/azureml/gaoxin/envs/ && echo ENVS_DONE
rsync -a /scratch/azureml/gaoxin/V-ReDO/ node-1:/scratch/azureml/gaoxin/V-ReDO/ && echo CODE_DONE
rsync -a /scratch/azureml/gaoxin/V-ReDO_final_checkpoint/ node-1:/scratch/azureml/gaoxin/V-ReDO_final_checkpoint/ && echo CKPT_DONE
rsync -a /scratch/azureml/gaoxin/spec_train15k/ node-1:/scratch/azureml/gaoxin/spec_train15k/ && echo IMAGES_DONE
rsync -a /scratch/azureml/gaoxin/models/ node-1:/scratch/azureml/gaoxin/models/ && echo MODELS_DONE
```

#### Step 2: rsync 家目录组件（完整路径！）
```bash
rsync -a /home/aiscuser/.paddleocr/ node-1:/home/aiscuser/.paddleocr/
rsync -a /home/aiscuser/.cache/ms-playwright/ node-1:/home/aiscuser/.cache/ms-playwright/
rsync -a /home/aiscuser/.azure/ node-1:/home/aiscuser/.azure/
rsync -a /home/aiscuser/.claude/ node-1:/home/aiscuser/.claude/
```

#### Step 3: Playwright 系统依赖（CRITICAL - 每节点必须单独执行）
```bash
ssh node-1 "sudo apt-get install -y libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libxdamage1 libpango-1.0-0 libcairo2"
```

#### Step 4: az CLI + Claude Code on node-1
```bash
ssh node-1 "which az || (curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash)"
ssh node-1 "which claude || (curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs && sudo npm install -g @anthropic-ai/claude-code)"
```

#### Step 5: 验证 + thinking.py
```bash
ssh node-1 "export PATH=/scratch/azureml/gaoxin/envs/u2c-verl/bin:\$PATH; \
    python3.10 -c \"import torch; print('GPU:', torch.cuda.device_count())\"; \
    python3.10 -c \"import verl; print('verl OK')\"; \
    python3.10 -c \"from paddleocr import PaddleOCR; print('paddle OK')\"; \
    python3.10 -c \"from playwright.sync_api import sync_playwright; print('pw OK')\""

ssh node-1 "nohup /opt/conda/envs/ptca/bin/python /blob/gaoxin/thinking.py </dev/null >/dev/null 2>&1 &"
```

---

## Instructions for Claude

### 执行流程

当用户说"部署 V-ReDO 环境"或类似触发词时：

1. **问集群别名**：「在哪个集群上部署？（如 c0、d0）」
2. **检查 SAS 有效性**：读 `~/.config/msra-skills/blob_sas.json` 的 `expires`
3. **检查连接**：`ssh frp-<alias> "echo OK"`
4. **读取 PAT**：从 CLAUDE.md 中获取 GitHub PAT
5. **执行 Phase 1**（node-0），全程通过 `ssh frp-<alias> "command"` 远程执行
6. **执行 Phase 2**（node-1 同步）
7. **汇报结果**

### 多集群并行

如果用户要求同时部署多个集群（如"C 和 D 都装"），使用 Agent 工具并行执行，每个集群一个 agent。

### 部分重装

如果只需要更新某个组件（如"重新下载 checkpoint"），只执行对应步骤，不需要全部重来。

### 监控长时间操作

- azcopy 下载和 rsync 用 nohup 后台执行，日志写到 `/tmp/`
- 设置 cron 定时检查进度
- images（86GB）传输最慢，约 15-30 分钟

### bashrc 内容

部署完成后，用户 `source ~/.bashrc` 即可使用训练环境和 claude。bashrc 应包含：
```bash
export PATH="/scratch/azureml/gaoxin/envs/u2c-verl/bin:$PATH"
export PYTHONPATH="/scratch/azureml/gaoxin/V-ReDO:$PYTHONPATH"
```

---

## 训练启动（参考）

部署完成后，训练启动方式参见 `/scratch/azureml/gaoxin/V-ReDO/docs/environment_setup.md` 的 Section 4。

```bash
# Debug 训练
cd /scratch/azureml/gaoxin/V-ReDO && bash scripts/debug_train.sh

# 完整训练
NNODES=2 TOTAL_EPOCHS=3 bash rl_verl/run_gdpo.sh
```

---

## 维护

| 事项 | 频率 | 操作 |
|------|------|------|
| Blob SAS 续期 | 每 7 天 | `blob-manager` skill |
| thinking.py 占卡确认 | 每日 | `ps aux \| grep thinking` |
| 节点重启后恢复 | 按需 | thinking.py + frpc + watchdog 全丢，需手动重启 |
