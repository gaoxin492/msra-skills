#!/bin/bash
# V-ReDO Environment Setup Script
# Usage:
#   Head node:   bash setup_node.sh --role head --sas-query "se=...&sig=..." --github-pat "ghp_..."
#   Worker node: bash setup_node.sh --role worker --head-node node-0

set -euo pipefail

# ===== Parse arguments =====
ROLE=""
SAS_QUERY=""
GITHUB_PAT=""
HEAD_NODE="node-0"
BLOB_BASE="https://yifanyang.blob.core.windows.net/yifanyang"
AZCOPY="/blob/gaoxin/bin/azcopy"
SCRATCH="/scratch/azureml/gaoxin"
HOME_DIR="/home/aiscuser"
ENV_PATH="${SCRATCH}/envs/u2c-verl"

while [[ $# -gt 0 ]]; do
    case $1 in
        --role) ROLE="$2"; shift 2 ;;
        --sas-query) SAS_QUERY="$2"; shift 2 ;;
        --github-pat) GITHUB_PAT="$2"; shift 2 ;;
        --head-node) HEAD_NODE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$ROLE" ]] && { echo "ERROR: --role required (head|worker)"; exit 1; }

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ===== Worker mode: rsync from head =====
if [[ "$ROLE" == "worker" ]]; then
    log "=== Worker mode: syncing from ${HEAD_NODE} ==="

    log "Step 1/5: rsync /scratch directories..."
    for dir in envs V-ReDO V-ReDO_final_checkpoint spec_train15k models; do
        rsync -a ${HEAD_NODE}:${SCRATCH}/${dir}/ ${SCRATCH}/${dir}/ && log "  ${dir} done"
    done

    log "Step 2/5: rsync home directory components..."
    # ⚠️ Use full paths, NOT ~
    rsync -a ${HEAD_NODE}:${HOME_DIR}/.paddleocr/ ${HOME_DIR}/.paddleocr/
    rsync -a ${HEAD_NODE}:${HOME_DIR}/.cache/ms-playwright/ ${HOME_DIR}/.cache/ms-playwright/
    rsync -a ${HEAD_NODE}:${HOME_DIR}/.azure/ ${HOME_DIR}/.azure/
    rsync -a ${HEAD_NODE}:${HOME_DIR}/.claude/ ${HOME_DIR}/.claude/ 2>/dev/null || true
    log "  home dirs done"

    log "Step 3/5: playwright system deps..."
    sudo apt-get install -y libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libxdamage1 libpango-1.0-0 libcairo2 >/dev/null 2>&1
    log "  playwright deps done"

    log "Step 4/5: az CLI + Claude Code..."
    which az >/dev/null 2>&1 || (curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash >/dev/null 2>&1)
    which claude >/dev/null 2>&1 || {
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
        sudo apt-get install -y nodejs >/dev/null 2>&1
        sudo npm install -g @anthropic-ai/claude-code >/dev/null 2>&1
    }
    log "  az CLI + Claude done"

    log "Step 5/5: verification..."
    export PATH="${ENV_PATH}/bin:$PATH"
    python3.10 -c "import torch; print('GPU:', torch.cuda.device_count())"
    python3.10 -c "import verl; print('verl:', verl.__version__)"
    python3.10 -c "from paddleocr import PaddleOCR; print('paddleocr OK')"
    python3.10 -c "from playwright.sync_api import sync_playwright; print('playwright OK')"

    log "=== Worker setup complete ==="
    exit 0
fi

# ===== Head mode =====
[[ -z "$SAS_QUERY" ]] && { echo "ERROR: --sas-query required for head mode"; exit 1; }
[[ -z "$GITHUB_PAT" ]] && { echo "ERROR: --github-pat required for head mode"; exit 1; }

log "=== Head node setup ==="

# Step 1: Create directories
log "Step 1/12: Creating directories..."
mkdir -p ${SCRATCH}/{envs,V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2,spec_train15k,models}

# Step 2: Parallel azcopy (big files)
log "Step 2/12: Starting parallel azcopy downloads..."

# ⚠️ CRITICAL: Path must be precise to avoid nesting!
${AZCOPY} cp "${BLOB_BASE}/gaoxin/d_sync/envs/u2c-verl/?${SAS_QUERY}" \
    ${SCRATCH}/envs/u2c-verl/ --recursive --log-level=ERROR &
PID_ENV=$!

${AZCOPY} cp "${BLOB_BASE}/gaoxin/spec_train15k/final/?${SAS_QUERY}" \
    ${SCRATCH}/spec_train15k/final/ --recursive --log-level=ERROR &
PID_IMAGES=$!

# ⚠️ CRITICAL: Only download checkpoint-639, NOT the entire directory (1.2TB)!
${AZCOPY} cp "${BLOB_BASE}/gaoxin/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/?${SAS_QUERY}" \
    ${SCRATCH}/V-ReDO_final_checkpoint/Qwen3-VL-4B_sft_mixed_v2/phase2/checkpoint-639/ --recursive --log-level=ERROR &
PID_CKPT=$!

log "  azcopy PIDs: env=$PID_ENV images=$PID_IMAGES ckpt=$PID_CKPT"

# Step 3: Git clone (while azcopy runs)
log "Step 3/12: Cloning V-ReDO..."
if [[ ! -d "${SCRATCH}/V-ReDO/.git" ]]; then
    cd ${SCRATCH}
    git clone https://gaoxin492:${GITHUB_PAT}@github.com/gaoxin492/V-ReDO.git
else
    cd ${SCRATCH}/V-ReDO && git pull
fi
log "  clone done"

# Step 4: PaddleOCR + Playwright
log "Step 4/12: Downloading PaddleOCR + Playwright..."
${AZCOPY} cp "${BLOB_BASE}/gaoxin/d_sync/paddleocr/?${SAS_QUERY}" \
    ${HOME_DIR}/.paddleocr/ --recursive --log-level=ERROR
${AZCOPY} cp "${BLOB_BASE}/gaoxin/d_sync/ms-playwright/?${SAS_QUERY}" \
    ${HOME_DIR}/.cache/ms-playwright/ --recursive --log-level=ERROR
log "  PaddleOCR + Playwright done"

# Wait for env to finish before patching
log "Waiting for conda env download..."
wait $PID_ENV
log "  env download complete"

# Step 5: Playwright system deps
log "Step 5/12: Installing playwright system deps..."
sudo apt-get install -y libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libxdamage1 libpango-1.0-0 libcairo2 >/dev/null 2>&1
log "  playwright deps done"

# Step 6: Apply verl patch
log "Step 6/12: Applying verl patch..."
bash ${SCRATCH}/V-ReDO/verl_patches/apply_verl_patch.sh \
    ${ENV_PATH}/lib/python3.10/site-packages/verl 2>&1 | tail -5
log "  verl patch done"

# Step 7: az CLI
log "Step 7/12: Installing az CLI..."
which az >/dev/null 2>&1 || (curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash >/dev/null 2>&1)
log "  az CLI done (azure creds must be copied separately)"

# Step 8: .env file
log "Step 8/12: Creating .env..."
cat > ${SCRATCH}/V-ReDO/.env << 'EOF'
VLM_REWARD_BASE_URL=https://searchagent20.cognitiveservices.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-12-01-preview
VLM_REWARD_API_KEY=unused
VLM_REWARD_MODEL=gpt-4o-mini
VLM_REWARD_CONCURRENCY=16
EOF
log "  .env done"

# Step 9: Claude Code + bashrc
log "Step 9/12: Installing Claude Code..."
which claude >/dev/null 2>&1 || {
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y nodejs >/dev/null 2>&1
    sudo npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
}

# bashrc (idempotent)
if ! grep -q 'V-ReDO environment' ${HOME_DIR}/.bashrc 2>/dev/null; then
    cat >> ${HOME_DIR}/.bashrc << 'RCEOF'

# V-ReDO environment
export PATH="/scratch/azureml/gaoxin/envs/u2c-verl/bin:$PATH"
export PYTHONPATH="/scratch/azureml/gaoxin/V-ReDO:$PYTHONPATH"
RCEOF
fi
log "  Claude + bashrc done"

# Step 10: Base models
log "Step 10/12: Downloading base models..."
${AZCOPY} cp "${BLOB_BASE}/gaoxin/models/Qwen3-VL-4B-Instruct/?${SAS_QUERY}" \
    ${SCRATCH}/models/Qwen3-VL-4B-Instruct/ --recursive --log-level=ERROR &
${AZCOPY} cp "${BLOB_BASE}/gaoxin/models/Qwen3-VL-8B-Instruct/?${SAS_QUERY}" \
    ${SCRATCH}/models/Qwen3-VL-8B-Instruct/ --recursive --log-level=ERROR &
wait
log "  base models done"

# Wait for remaining downloads
log "Waiting for all downloads to complete..."
wait $PID_IMAGES 2>/dev/null || true
wait $PID_CKPT 2>/dev/null || true
log "  all downloads complete"

# Step 11: Verification
log "Step 11/12: Verification..."
export PATH="${ENV_PATH}/bin:$PATH"
python3.10 -c "import torch; print('GPU:', torch.cuda.device_count())"
python3.10 -c "import verl; print('verl:', verl.__version__)"
python3.10 -c "from paddleocr import PaddleOCR; print('paddleocr OK')"
python3.10 -c "from playwright.sync_api import sync_playwright; print('playwright OK')"
which az && echo "az CLI OK"
which claude && echo "Claude OK"
ls ${SCRATCH}/models/Qwen3-VL-4B-Instruct/*.safetensors >/dev/null 2>&1 && echo "4B model OK"
ls ${SCRATCH}/models/Qwen3-VL-8B-Instruct/*.safetensors >/dev/null 2>&1 && echo "8B model OK"

# Step 12: thinking.py
log "Step 12/12: Starting thinking.py..."
nohup /opt/conda/envs/ptca/bin/python /blob/gaoxin/thinking.py </dev/null >/dev/null 2>&1 &
log "  thinking.py started (PID: $!)"

log "=== Head node setup complete ==="
log "Next: copy ~/.azure/ creds, ~/.claude/settings.json, then run on worker:"
log "  ssh node-1 'bash ${SCRATCH}/V-ReDO/scripts/setup_node.sh --role worker'"
