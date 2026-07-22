#!/usr/bin/env bash
# Mage-Flow T2I via microsoft/Mage mage_flow package. Env: HF_TOKEN OUTDIR
set -euo pipefail
MODEL=${MODEL:-microsoft/Mage-Flow}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/mage-flow}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" MODEL OUTDIR
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip git curl ninja-build build-essential || true
curl -LsSf https://astral.sh/uv/install.sh | sh || true
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || pip install -q uv

cd "$HOME/mc-bench"
rm -rf Mage
git clone --depth 1 https://github.com/microsoft/Mage.git
cd Mage/mage_flow
uv venv
# shellcheck disable=SC1091
. .venv/bin/activate
# CUDA 12.x torch first (MC image)
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126 || \
  uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128 || \
  uv pip install torch torchvision
uv pip install -r requirements.txt || true
uv pip install -e . --no-deps
uv pip install setuptools wheel ninja
uv pip install --no-build-isolation flash-attn==2.8.3 || log "flash-attn build failed; continuing"

log "Mage-Flow generate $MODEL"
python3 - <<'PY'
import json, os, statistics, time
from pathlib import Path
from mage_flow import MageFlowPipeline

out = Path(os.environ["OUTDIR"])
model_id = os.environ["MODEL"]
t0 = time.perf_counter()
pipe = MageFlowPipeline.from_pretrained(model_id, device="cuda")
load_s = time.perf_counter() - t0

prompt = (
    "A ceramic espresso cup on a sunlit oak table, soft morning light, "
    "shallow depth of field, product photography, no text, no watermark, no logo"
)
# warmup
_ = pipe.generate([prompt], num_inference_steps=4)
runs = []
for i in range(5):
    t0 = time.perf_counter()
    imgs = pipe.generate([prompt], num_inference_steps=20)
    dt = time.perf_counter() - t0
    runs.append({"latency_s": dt, "steps": 20})
    if i == 0:
        imgs[0].save(out / "showcase.png")

lat = [r["latency_s"] for r in runs]
result = {
    "model": model_id,
    "load_s": load_s,
    "engine": "mage_flow.MageFlowPipeline",
    "prompt": prompt,
    "runs": runs,
    "mean_latency_s": statistics.mean(lat),
    "median_latency_s": statistics.median(lat),
    "p95_latency_s": sorted(lat)[int(0.95 * (len(lat) - 1))],
}
(out / "bench.json").write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
PY
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
rm -f "$OUTDIR/FAIL"
echo DONE >"$OUTDIR/DONE"
log DONE
