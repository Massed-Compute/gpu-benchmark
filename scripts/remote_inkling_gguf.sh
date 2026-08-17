#!/usr/bin/env bash
# unsloth/Inkling-Small-GGUF via llama.cpp in CUDA devel container (SM120)
# Env: HF_TOKEN QUANT OUTDIR NGL
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
MODEL_REPO=${MODEL_REPO:-unsloth/Inkling-Small-GGUF}
QUANT=${QUANT:-UD-IQ1_S}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/inkling-small/$QUANT}
NGL=${NGL:-99}
REBUILD=${REBUILD:-0}
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/.cache/huggingface" "$HOME/mc-bench/llama-build"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" HF_XET_HIGH_PERFORMANCE=1

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git curl jq python3-venv python3-pip
sudo systemctl enable --now docker || true

if [[ ! -x "$HOME/mc-bench/venv/bin/python" ]]; then
  python3 -m venv "$HOME/mc-bench/venv"
fi
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel huggingface_hub

MODEL_ROOT="$HOME/mc-bench/models/Inkling-Small-GGUF"
MODEL_DIR="$MODEL_ROOT/$QUANT"
if ! find "$MODEL_DIR" -name '*.gguf' 2>/dev/null | grep -q .; then
  log "download $MODEL_REPO $QUANT"
  QUANT="$QUANT" MODEL_REPO="$MODEL_REPO" python - <<'PY'
from huggingface_hub import snapshot_download
import os
snapshot_download(
  repo_id=os.environ["MODEL_REPO"],
  allow_patterns=[f"{os.environ['QUANT']}/*"],
  local_dir=os.path.expanduser("~/mc-bench/models/Inkling-Small-GGUF"),
  token=os.environ.get("HF_TOKEN") or None,
)
print("download_ok")
PY
fi

MODEL_PATH=$(find "$MODEL_DIR" -name '*-00001-of-*.gguf' | head -1)
[[ -n "$MODEL_PATH" ]] || MODEL_PATH=$(find "$MODEL_DIR" -name '*.gguf' | head -1)
[[ -n "$MODEL_PATH" ]] || { log "missing gguf in $MODEL_DIR"; exit 1; }
# path inside container mount
MODEL_REL=${MODEL_PATH/#$HOME\/mc-bench\/models\//}
log "model=$MODEL_PATH size=$(du -sh "$MODEL_DIR" | awk '{print $1}')"

LLAMA="$HOME/mc-bench/llama.cpp"
if [[ ! -d "$LLAMA/.git" ]]; then
  log "clone llama.cpp"
  rm -rf "$LLAMA"
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA"
fi
cd "$LLAMA"
git fetch --depth 1 origin pull/25731/head:inkling-pr || true
git checkout inkling-pr 2>/dev/null || log "using currently checked-out ref (PR not applied)"
LLAMA_REV=$(git -C "$LLAMA" rev-parse HEAD)
LLAMA_BRANCH=$(git -C "$LLAMA" rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)
log "llama.cpp rev=$LLAMA_REV branch=$LLAMA_BRANCH"
if [[ "$REBUILD" == "1" ]]; then
  log "REBUILD=1 — clearing /build cache"
  rm -rf "$HOME/mc-bench/llama-build"
fi
mkdir -p "$HOME/mc-bench/llama-build"

log "pull cuda devel + build/run llama-bench"
sudo docker pull nvidia/cuda:12.8.0-devel-ubuntu24.04
# Sample VRAM while llama-bench runs (post-exit nvidia-smi is always 0 MiB used).
(
  while true; do
    date -u +%Y-%m-%dT%H:%M:%SZ
    nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv
    sleep 2
  done
) > "$OUTDIR/nvidia-smi.txt" &
SMI_PID=$!
cleanup_smi(){ kill "$SMI_PID" 2>/dev/null || true; }
trap cleanup_smi EXIT

sudo docker run --rm --gpus all \
  -v "$LLAMA:/src" \
  -v "$HOME/mc-bench/models:/models:ro" \
  -v "$OUTDIR:/out" \
  -v "$HOME/mc-bench/llama-build:/build" \
  nvidia/cuda:12.8.0-devel-ubuntu24.04 \
  bash -lc '
set -euo pipefail
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cmake git build-essential curl libcurl4-openssl-dev
if [[ ! -x /build/bin/llama-bench ]]; then
  cmake -S /src -B /build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DGGML_CCACHE=OFF -DCMAKE_CUDA_ARCHITECTURES="120"
  cmake --build /build -j "$(nproc)" --target llama-bench
fi
/build/bin/llama-bench -m /models/'"$MODEL_REL"' -ngl '"$NGL"' -p 128 -n 128 -r 5 -o json | tee /out/llama-bench.json
'
cleanup_smi
trap - EXIT

{
  echo "QUANT=$QUANT"
  echo "MODEL_REL=$MODEL_REL"
  echo "LLAMA_REV=$LLAMA_REV"
  echo "LLAMA_BRANCH=$LLAMA_BRANCH"
} > "$OUTDIR/meta.txt"
echo DONE > "$OUTDIR/DONE"
log "DONE"
ls -la "$OUTDIR"
cat "$OUTDIR/meta.txt" || true
