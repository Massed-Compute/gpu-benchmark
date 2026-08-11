#!/usr/bin/env bash
# Muse Glimmer 30B Meta GGUF (kquant-dynamic) via llama.cpp CUDA.
# Needs llama.cpp master / b10353+ (LLM_ARCH_MUSE_GLIMMER).
#
# Emits (for results/raw):
#   llama-bench.json, gpu-split.txt, nvidia-smi-live.txt, nvidia-smi.txt,
#   SUMMARY.txt, llama-cpp-commit.txt, muse-arch-check.txt, DONE
#
# Multi-GPU: slash separators only (-ts 1/1/…, -dev CUDA0/…). Commas park weights on GPU0.
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
REPO=${REPO:-meta-models/Muse-Glimmer-30B-GGUF}
GGUF=${GGUF:-muse-glimmer-30B-kquant-dynamic.gguf}
NGPU=${NGPU:-$(nvidia-smi -L | wc -l | tr -d " ")}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/muse-glimmer-gguf-${NGPU}x}
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/mc-bench/venv"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" REPO GGUF OUTDIR NGPU

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  python3-venv python3-pip curl git cmake build-essential docker.io || true
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
git rev-parse HEAD | tee "$OUTDIR/llama-cpp-commit.txt"
grep -c LLM_ARCH_MUSE_GLIMMER src/llama-arch.cpp | tee "$OUTDIR/muse-arch-check.txt"

# CUDA arch: 89=Ada/L40S, 120=Blackwell
CUDA_ARCHS=${CUDA_ARCHS:-"89;120"}
TS=${TS:-$(python3 -c "print('/'.join(['1']*int('${NGPU}')))")}
DEVS=${DEVS:-$(python3 -c "print('/'.join([f'CUDA{i}' for i in range(int('${NGPU}'))]))")}
export TS DEVS GGUF
log "multi-GPU: ngpu=$NGPU tensor-split=$TS devices=$DEVS"
echo "ngpu=$NGPU ts=$TS devs=$DEVS" | tee "$OUTDIR/gpu-split.txt"

# Live VRAM sampler (must run during load/bench — post-exit smi is zeros).
SMI_CSV='index,name,memory.used,memory.total,utilization.gpu'
(
  for i in $(seq 1 240); do
    echo "=== sample $i $(date -u +%H:%M:%S) ==="
    nvidia-smi --query-gpu="$SMI_CSV" --format=csv
    sleep 2
  done
) > "$OUTDIR/nvidia-smi-live.txt" &
SMI_PID=$!

log "pull cuda devel + build llama-bench (arch=$CUDA_ARCHS)"
sudo docker pull nvidia/cuda:12.8.0-devel-ubuntu24.04
sudo mkdir -p "$OUTDIR" "$HOME/mc-bench/llama-build"
sudo chown -R "$(id -u)":"$(id -g)" "$OUTDIR" || true
set +e
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
'
BENCH_RC=$?
set -e
kill "$SMI_PID" 2>/dev/null || true
wait "$SMI_PID" 2>/dev/null || true

# Consistent five-field CSV snapshot (may be idle after unload — live file is source of truth).
nvidia-smi --query-gpu="$SMI_CSV" --format=csv | tee "$OUTDIR/nvidia-smi.txt"
sudo chown -R "$(id -u)":"$(id -g)" "$OUTDIR" "$HOME/mc-bench/llama-build" || true

python3 - <<'PY'
import json, os, sys
from pathlib import Path

out = Path(os.environ["OUTDIR"])
ngpu = int(os.environ["NGPU"])
d = json.load(open(out / "llama-bench.json"))
tg = next(x for x in d if x.get("n_gen") == 128)
pp = next(x for x in d if x.get("n_gen") == 0)

def parse_live_peaks(text: str):
    best = None
    for block in text.split("=== sample")[1:]:
        mems = []
        lines = [ln.strip() for ln in block.splitlines() if ln.strip()]
        used_idx = 2  # five-field CSV: index,name,memory.used,...
        body_start = 0
        for i, ln in enumerate(lines):
            low = ln.lower()
            if "memory.used" in low and "," in ln:
                cols = [c.strip() for c in low.split(",")]
                for j, c in enumerate(cols):
                    if "memory.used" in c:
                        used_idx = j
                        break
                body_start = i + 1
                break
        for ln in lines[body_start:]:
            if "MiB" not in ln or "," not in ln:
                continue
            if ln.lower().startswith("index"):
                continue
            parts = [p.strip() for p in ln.split(",")]
            if len(parts) <= used_idx:
                continue
            try:
                mems.append(int(parts[used_idx].split()[0]))
            except Exception:
                pass
        if mems and (best is None or sum(mems) > sum(best)):
            best = mems
    return best

live = (out / "nvidia-smi-live.txt").read_text()
peak = parse_live_peaks(live)
all_used = bool(peak) and len(peak) >= ngpu and min(peak) > 500
summary = (
    f"tg={tg['avg_ts']}\n"
    f"pp={pp['avg_ts']}\n"
    f"ts={tg.get('tensor_split')}\n"
    f"devices={tg.get('devices')}\n"
    f"peak={peak}\n"
    f"ALL_USED={all_used}\n"
)
(out / "SUMMARY.txt").write_text(summary)
print(summary)
if ngpu > 1 and not all_used:
    print(
        "ERROR: expected multi-GPU VRAM split on every card; "
        "check slash -ts/-dev (commas park weights on GPU0)",
        file=sys.stderr,
    )
    sys.exit(2)
PY

[[ $BENCH_RC -eq 0 ]] || exit "$BENCH_RC"
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
head -c 2000 "$OUTDIR/llama-bench.json" || true
