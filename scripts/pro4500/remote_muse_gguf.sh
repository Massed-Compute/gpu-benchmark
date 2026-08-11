#!/usr/bin/env bash
# Muse Glimmer 30B Meta GGUF (kquant-dynamic) via llama.cpp CUDA.
# Needs llama.cpp master / b10353+ (LLM_ARCH_MUSE_GLIMMER).
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/muse-glimmer-gguf}
REPO=${REPO:-meta-models/Muse-Glimmer-30B-GGUF}
GGUF=${GGUF:-muse-glimmer-30B-kquant-dynamic.gguf}
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/mc-bench/venv"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" REPO GGUF

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip curl git cmake build-essential || true
sudo systemctl enable --now docker || true
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

if [[ ! -d "$HOME/mc-bench/llama.cpp/.git" ]]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$HOME/mc-bench/llama.cpp"
fi
cd "$HOME/mc-bench/llama.cpp"
if ! grep -q LLM_ARCH_MUSE_GLIMMER src/llama-arch.cpp 2>/dev/null; then
  log "checkout lacks Muse Glimmer — fetch latest master"
  git fetch --depth 1 origin master && git checkout -f FETCH_HEAD
fi
grep -c LLM_ARCH_MUSE_GLIMMER src/llama-arch.cpp | tee "$OUTDIR/muse-arch-check.txt"

# CUDA arch: 89=Ada/L40S, 120=Blackwell
CUDA_ARCHS=${CUDA_ARCHS:-"89;120"}
# Force equal layer split across every visible GPU (required for 2x/4x/8x).
# llama-bench uses slash separators: -ts 1/1/1/1 and -dev CUDA0/CUDA1/...
NGPU=${NGPU:-$(nvidia-smi -L | wc -l | tr -d " ")}
TS=${TS:-$(python3 -c "print('/'.join(['1']*int('${NGPU}')))")}
DEVS=${DEVS:-$(python3 -c "print('/'.join([f'CUDA{i}' for i in range(int('${NGPU}'))]))")}
export OUTDIR NGPU TS DEVS GGUF
log "multi-GPU: ngpu=$NGPU tensor-split=$TS devices=$DEVS"
echo "ngpu=$NGPU ts=$TS devs=$DEVS" | tee "$OUTDIR/gpu-split.txt"

log "pull cuda devel + build llama-bench (arch=$CUDA_ARCHS)"
sudo docker pull nvidia/cuda:12.8.0-devel-ubuntu24.04
# Ensure host can write sidecar files even if docker creates root-owned JSON.
sudo mkdir -p "$OUTDIR" "$HOME/mc-bench/llama-build"
sudo chown -R "$(id -u)":"$(id -g)" "$OUTDIR" || true
sudo docker run --rm --gpus all \
  -v "$HOME/mc-bench/llama.cpp:/src" \
  -v "$HOME/mc-bench/models:/models:ro" \
  -v "$OUTDIR:/out" \
  -v "$HOME/mc-bench/llama-build:/build" \
  -e CUDA_ARCHS="$CUDA_ARCHS" \
  -e TS="$TS" \
  -e DEVS="$DEVS" \
  -e GGUF="$GGUF" \
  nvidia/cuda:12.8.0-devel-ubuntu24.04 \
  bash -lc '
set -euo pipefail
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cmake git build-essential curl libcurl4-openssl-dev
cmake -S /src -B /build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DGGML_CCACHE=OFF -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHS"
cmake --build /build -j "$(nproc)" --target llama-bench
/build/bin/llama-bench -m /models/"$GGUF" -ngl 99 -sm layer -ts "$TS" -dev "$DEVS" -p 128 -n 128 -r 5 -o json \
  | tee /out/llama-bench.json
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv | tee /out/nvidia-smi.txt
echo DONE > /out/DONE
'
sudo chown -R "$(id -u)":"$(id -g)" "$OUTDIR" "$HOME/mc-bench/llama-build" || true
log "DONE $OUTDIR"
head -c 2000 "$OUTDIR/llama-bench.json" || true
# Require every visible GPU to show meaningful VRAM (layer split actually engaged).
python3 - <<'PY'
import json, os, sys
from pathlib import Path
out = Path(os.path.expanduser(os.environ.get("OUTDIR", "~/mc-bench/out/muse-glimmer-gguf")))
d = json.load(open(out / "llama-bench.json"))
r = next(x for x in d if x.get("n_gen") == 128)
print("tensor_split", r.get("tensor_split"), "devices", r.get("devices"), "tg", r.get("avg_ts"))
smi = (out / "nvidia-smi.txt").read_text()
mems = []
for ln in smi.splitlines():
    if "MiB" in ln and "," in ln and not ln.lower().startswith("index"):
        try:
            mems.append(int(ln.split(",")[2].split()[0]))
        except Exception:
            pass
print("post_bench_mem_mib", mems)
ngpu = int(os.environ.get("NGPU", "1"))
if ngpu > 1 and (not mems or len(mems) < ngpu or min(mems) < 500):
    print("WARN: expected multi-GPU VRAM split; check -ts/-dev slash syntax", file=sys.stderr)
PY
