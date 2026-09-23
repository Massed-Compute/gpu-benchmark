#!/usr/bin/env bash
# Ternary-Bonsai-2-27B PQ2_0 via PrismML llama.cpp CUDA (stock llama.cpp cannot load these files).
# Env: SKU CUDA_ARCHS HF_TOKEN(optional) OUTDIR
set -euo pipefail
SKU=${SKU:?set SKU e.g. gpu_1x_l40s}
REPO=${REPO:-prism-ml/Ternary-Bonsai-2-27B-gguf}
GGUF=${GGUF:-Ternary-Bonsai-2-27B-PQ2_0.gguf}
LLAMA_GIT=${LLAMA_GIT:-https://github.com/PrismML-Eng/llama.cpp}
CUDA_ARCHS=${CUDA_ARCHS:-native}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/ternary-bonsai-2-27b-gguf/${SKU}/PQ2_0}
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/mc-bench/venv" "$HOME/mc-bench/llama-build"
export HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-}" HF_TOKEN="${HF_TOKEN:-}" REPO GGUF OUTDIR SKU

if [[ -z "${HUGGING_FACE_HUB_TOKEN:-}" && -f "$HOME/.cache/huggingface/token" ]]; then
  tok=$(tr -d '[:space:]' < "$HOME/.cache/huggingface/token")
  export HUGGING_FACE_HUB_TOKEN="$tok"
fi
# huggingface_hub reads HUGGING_FACE_HUB_TOKEN from the file or env

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  python3.12-venv python3-pip curl git jq || true
sudo systemctl enable --now docker || true
rm -rf "$HOME/mc-bench/venv"
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip huggingface_hub

MODEL_PATH="$HOME/mc-bench/models/$GGUF"
if [[ ! -f "$MODEL_PATH" ]]; then
  log "download $REPO/$GGUF"
  python - <<'PY'
from huggingface_hub import hf_hub_download
import os
p = hf_hub_download(
    os.environ["REPO"],
    os.environ["GGUF"],
    local_dir=os.path.expanduser("~/mc-bench/models"),
    token=(os.environ.get("HF_TOKEN") or None),
)
print(p)
PY
fi
[[ -f "$MODEL_PATH" ]] || MODEL_PATH=$(find "$HOME/mc-bench/models" -name "$GGUF" | head -1)
log "model=$MODEL_PATH $(du -h "$MODEL_PATH" | awk '{print $1}')"
echo "sku=$SKU" > "$OUTDIR/model.txt"
echo "repo=$REPO" >> "$OUTDIR/model.txt"
echo "gguf=$GGUF" >> "$OUTDIR/model.txt"
echo "file=$(basename "$MODEL_PATH")" >> "$OUTDIR/model.txt"
stat -c 'bytes=%s' "$MODEL_PATH" >> "$OUTDIR/model.txt" || true

LLAMA="$HOME/mc-bench/prism-llama.cpp"
if [[ ! -d "$LLAMA/.git" ]]; then
  log "clone PrismML llama.cpp"
  rm -rf "$LLAMA"
  git clone --depth 1 "$LLAMA_GIT" "$LLAMA"
fi
git -C "$LLAMA" rev-parse HEAD | tee "$OUTDIR/llama-cpp-commit.txt"
git -C "$LLAMA" remote get-url origin | tee -a "$OUTDIR/llama-cpp-commit.txt"

SMI_CSV='timestamp,name,memory.used,memory.total,utilization.gpu'
(
  for i in $(seq 1 360); do
    echo "=== sample $i $(date -u +%H:%M:%S) ==="
    nvidia-smi --query-gpu="$SMI_CSV" --format=csv
    sleep 2
  done
) > "$OUTDIR/nvidia-smi.txt" &
SMI_PID=$!
trap 'kill $SMI_PID 2>/dev/null || true' EXIT

log "pull cuda devel + build llama-bench arch=$CUDA_ARCHS"
sudo docker pull nvidia/cuda:12.8.0-devel-ubuntu24.04

run_bench() {
  local fa_flag=$1
  local json_out=$2
  sudo docker run --rm --gpus all \
    -e CUDA_ARCHS="$CUDA_ARCHS" \
    -e GGUF="$GGUF" \
    -e FA_FLAG="$fa_flag" \
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
  cmake -S /src -B /build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DGGML_CCACHE=OFF -DCMAKE_CUDA_ARCHITECTURES="'"$CUDA_ARCHS"'"
  cmake --build /build -j "$(nproc)" --target llama-bench
fi
/build/bin/llama-bench -h > /out/llama-bench-help.txt 2>&1 || true
set +e
if [[ "$FA_FLAG" == "1" ]]; then
  /build/bin/llama-bench -m /models/'"$GGUF"' -ngl 99 -fa 1 -p 128,512 -n 128 -r 5 -o json | tee /out/'"$json_out"'
else
  /build/bin/llama-bench -m /models/'"$GGUF"' -ngl 99 -p 128,512 -n 128 -r 5 -o json | tee /out/'"$json_out"'
fi
ec=$?
set -e
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv | tee /out/nvidia-smi-end.txt
exit $ec
'
}

if ! run_bench 1 llama-bench.json; then
  log "llama-bench -fa 1 failed; retry without flash-attn"
  rm -f "$OUTDIR/llama-bench.json"
  run_bench 0 llama-bench.json
  echo "flash_attn=0" >> "$OUTDIR/model.txt"
else
  echo "flash_attn=1" >> "$OUTDIR/model.txt"
fi

python3 - <<'PY' || true
import json, pathlib
p = pathlib.Path.home() / "mc-bench/out"
# find json via OUTDIR env
import os
j = pathlib.Path(os.environ["OUTDIR"]) / "llama-bench.json"
raw = j.read_text().strip()
# llama-bench may wrap JSON in logs; extract last json array/object
start = max(raw.rfind("["), raw.rfind("{"))
data = json.loads(raw[start:])
rows = data if isinstance(data, list) else data.get("results", [data])
out = []
for r in rows:
    out.append({
        "n_prompt": r.get("n_prompt"),
        "n_gen": r.get("n_gen"),
        "avg_ts": r.get("avg_ts") or r.get("avg_tokens_per_second"),
        "backend": r.get("backend"),
        "model_type": r.get("n_params") or r.get("model_type"),
    })
pathlib.Path(os.environ["OUTDIR"], "summary.json").write_text(json.dumps(out, indent=2))
print("summary rows", len(out))
PY

[[ -s "$OUTDIR/llama-bench.json" ]]
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
kill "$SMI_PID" 2>/dev/null || true
trap - EXIT
ls -la "$OUTDIR"
