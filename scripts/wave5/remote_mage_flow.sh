#!/usr/bin/env bash
# Mage-Flow T2I via microsoft/Mage mage_flow package with SDPA attention.
# Env: HF_TOKEN OUTDIR
set -euo pipefail
MODEL=${MODEL:-microsoft/Mage-Flow}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/mage-flow}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" MODEL OUTDIR
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq || true
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
# CUDA 12.x torch first (MC image). Prefer cu129 on Blackwell hosts.
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu129 || \
  uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128 || \
  uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126 || \
  uv pip install torch torchvision
uv pip install -r requirements.txt || true
uv pip install -e . --no-deps
uv pip install setuptools wheel ninja
# flash-attn often fails to build on newer GPUs; published benches used SDPA.
uv pip install --no-build-isolation flash-attn==2.8.3 || log "flash-attn build failed; using SDPA"

log "Mage-Flow generate $MODEL (attn=sdpa)"
python3 - <<'PY'
import json, os, statistics, time, subprocess
from pathlib import Path

# Force SDPA before pipeline import (matches published Wave 5 numbers).
try:
    from mage_flow.models.modules import _attn_backend as ab
    if hasattr(ab, "set_attn_backend"):
        ab.set_attn_backend("sdpa")
    elif hasattr(ab, "_set_attn_backend"):
        ab._set_attn_backend("sdpa")
    else:
        # Fall back: patch default resolver used by generate_images.
        import mage_flow.models.modules._attn_backend as mod
        if hasattr(mod, "resolve_attn_backend"):
            _orig = mod.resolve_attn_backend
            def resolve_attn_backend(*a, **k):
                return "sdpa"
            mod.resolve_attn_backend = resolve_attn_backend
except Exception as e:
    print("attn backend patch warn:", e)

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
mean_lat = statistics.mean(lat)
# VRAM while model still loaded
smi = subprocess.check_output(
    ["nvidia-smi", "--query-gpu=name,memory.used,memory.total", "--format=csv"],
    text=True,
)
(out / "nvidia-smi.txt").write_text(smi)
peak_vram_gb = 0.0
for line in smi.splitlines():
    if "MiB" in line and not line.startswith("name"):
        parts = [x.strip() for x in line.split(",")]
        if len(parts) >= 2 and "MiB" in parts[1]:
            peak_vram_gb = float(parts[1].replace("MiB", "").strip()) / 1024.0
            break
result = {
    "model": model_id,
    "load_s": load_s,
    "engine": "mage_flow.MageFlowPipeline+sdpa",
    "attn": "sdpa",
    "prompt": prompt,
    "width": 1024,
    "height": 1024,
    "steps": 20,
    "runs": runs,
    "mean_latency_s": mean_lat,
    "median_latency_s": statistics.median(lat),
    "p95_latency_s": sorted(lat)[int(0.95 * (len(lat) - 1))],
    "images_per_s": (1.0 / mean_lat) if mean_lat else 0.0,
    "peak_vram_gb": peak_vram_gb,
}
(out / "bench.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
PY
rm -f "$OUTDIR/FAIL"
echo DONE >"$OUTDIR/DONE"
log DONE
