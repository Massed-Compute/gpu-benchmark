#!/usr/bin/env bash
# MiniMax-H3 Turbo + LightX2V addons on a disposable mc-bench-h3turbo-* VM.
# ADDONS_HEAVY=1 (A100 / Blackwell) also pulls Qwen3.6-27B rewriter.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_XET_HIGH_PERFORMANCE=1
export HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-$(cat "$HOME/.cache/huggingface/token" 2>/dev/null || true)}"
export HF_TOKEN="${HUGGING_FACE_HUB_TOKEN:-}"
SKU="${SKU:-unknown}"
ADDONS_HEAVY="${ADDONS_HEAVY:-0}"
ROOT="$HOME/mc-bench"
MODELS="$ROOT/models"
OUT="$ROOT/out/h3turbo"
LOG="$HOME/h3turbo-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

[[ -n "${HF_TOKEN:-}" ]] || { log "missing HF_TOKEN"; exit 1; }
mkdir -p "$HOME/.cache/huggingface" "$MODELS" "$OUT" "$ROOT/configs"
printf '%s\n' "$HF_TOKEN" > "$HOME/.cache/huggingface/token"
chmod 600 "$HOME/.cache/huggingface/token"

log "sku=$SKU heavy=$ADDONS_HEAVY"
log "apt"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git curl jq ffmpeg python3-venv python3-pip build-essential \
  ca-certificates libsndfile1 || true

if ! command -v uv >/dev/null 2>&1; then
  mkdir -p "$HOME/.config" "$HOME/.local/bin" || true
  curl -LsSf https://astral.sh/uv/install.sh | sh || log "uv install skipped"
fi
export PATH="$HOME/.local/bin:$PATH"
log "venv"
rm -rf "$ROOT/venv"
python3 -m venv "$ROOT/venv"
# shellcheck disable=SC1091
source "$ROOT/venv/bin/activate"
python -m pip install -U pip wheel
python -m pip install -q 'huggingface_hub[hf_transfer,cli]'
hf() { "$ROOT/venv/bin/hf" "$@"; }

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | tee "$OUT/nvidia-smi-id.txt"

LX="$ROOT/LightX2V"
if [[ ! -d "$LX/.git" ]]; then
  log "clone LightX2V"
  git clone --depth 1 https://github.com/ModelTC/LightX2V.git "$LX"
fi
cd "$LX"
log "install LightX2V"
python -m pip install -v -e . || python -m pip install -v "git+https://github.com/ModelTC/LightX2V.git"
python -m pip install -q peft accelerate transformers bitsandbytes pillow soundfile pyzmq || true
python -m pip install -q sageattention || python -m pip install -q sageattention==2.1.1 || log "sageattention wheel missing; configs fall back inside bench"

log "MiniMax-H3 LightX2V layout (root transformer/vae, not nested FL2VA keys)"
hf download MiniMaxAI/MiniMax-H3 \
  --include "model_index.json" \
  --include "transformer/*" \
  --include "vae/*" \
  --include "audio_vae/*" \
  --include "text_encoder/*" \
  --include "tokenizer/*" \
  --include "processor/*" \
  --local-dir "$MODELS/MiniMax-H3"

log "Turbo LoRAs (4-step v1.2 768p, 8-step 768p, Ref2VA 4/8)"
hf download lightx2v/Minimax-h3-Turbo \
  minimax_h3_fl2v_turbo_4step_v1.2_768p_bf16.safetensors \
  minimax_h3_fl2v_turbo_8step_v1.0_768p_bf16.safetensors \
  minimax_h3_ref2v_turbo_4step_v0.1_bf16.safetensors \
  minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors \
  --local-dir "$MODELS/turbo"

log "Turbo SLA sparse-attention LoRA"
hf download lightx2v/Minimax-h3-Turbo-SLA \
  minimax_h3_fl2v_turbo_4step_v0.1_768p_sla_bf16.safetensors \
  --local-dir "$MODELS/turbo"

log "Prompt rewriter 8B (Qwen3-VL, multimodal)"
hf download lightx2v/MiniMax-H3-Prompt-Rewriter-LoRA-8B \
  --local-dir "$MODELS/rewriter-8b"
hf download Qwen/Qwen3-VL-8B-Instruct \
  --local-dir "$MODELS/Qwen3-VL-8B-Instruct"

if [[ "$ADDONS_HEAVY" == "1" ]]; then
  log "Prompt rewriter 27B (best T2VA text)"
  hf download lightx2v/MiniMax-H3-Prompt-Rewriter-LoRA \
    --local-dir "$MODELS/rewriter-27b"
  hf download Qwen/Qwen3.6-27B \
    --local-dir "$MODELS/Qwen3.6-27B"
fi

log "SeedVR2-3B finish"
hf download ByteDance-Seed/SeedVR2-3B \
  seedvr2_ema_3b.pth ema_vae.pth pos_emb.pt neg_emb.pt \
  --local-dir "$MODELS/seedvr2-3b"
if [[ ! -d "$ROOT/SeedVR/.git" ]]; then
  git clone --depth 1 https://github.com/ByteDance-Seed/SeedVR.git "$ROOT/SeedVR" || true
fi

if [[ -d "$HOME/h3turbo-configs" ]]; then
  cp -a "$HOME/h3turbo-configs/." "$ROOT/configs/"
fi

python3 - <<'PY'
from pathlib import Path
root = Path.home() / "mc-bench"
cfg_dir = root / "configs"
lora4 = root / "models/turbo/minimax_h3_fl2v_turbo_4step_v1.2_768p_bf16.safetensors"
lora8 = root / "models/turbo/minimax_h3_fl2v_turbo_8step_v1.0_768p_bf16.safetensors"
lorasla = root / "models/turbo/minimax_h3_fl2v_turbo_4step_v0.1_768p_sla_bf16.safetensors"
for name, token, path in [
    ("t2av_4step_768p_offload.json", "ADDON_LORA_4STEP", lora4),
    ("t2av_8step_768p_offload.json", "ADDON_LORA_8STEP", lora8),
    ("t2av_4step_768p_sla_offload.json", "ADDON_LORA_SLA", lorasla),
]:
    p = cfg_dir / name
    if not p.exists():
        continue
    text = p.read_text()
    p.write_text(text.replace(token, str(path)))
print("patched configs")
PY

log "weights on disk"
find "$MODELS" -name '*.safetensors' -o -name '*.pth' -o -name '*.pt' | \
  xargs -r du -h | sort -h | tee "$OUT/weights.txt"
touch "$OUT/DONE_WEIGHTS"
log "DONE_WEIGHTS"
