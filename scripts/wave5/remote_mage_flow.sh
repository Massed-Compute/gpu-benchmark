#!/usr/bin/env bash
# microsoft/Mage-Flow Diffusers T2I latency + word-free showcase.
# Env: HF_TOKEN OUTDIR [MODEL] [STEPS] [WIDTH] [HEIGHT]
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/mage-flow}
MODEL=${MODEL:-microsoft/Mage-Flow}
STEPS=${STEPS:-28}
WIDTH=${WIDTH:-1024}
HEIGHT=${HEIGHT:-1024}
SEED=${SEED:-42}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip git curl || true
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel
pip install -q -U torch torchvision --index-url https://download.pytorch.org/whl/cu128 || pip install -q -U torch torchvision
pip install -q -U 'git+https://github.com/huggingface/diffusers' transformers accelerate sentencepiece protobuf pillow huggingface_hub

log "bench $MODEL"
export OUTDIR MODEL STEPS WIDTH HEIGHT SEED
python3 - <<'PY'
import json, os, time, torch
from pathlib import Path

out = Path(os.environ["OUTDIR"])
model_id = os.environ["MODEL"]
steps = int(os.environ["STEPS"])
w = int(os.environ["WIDTH"]); h = int(os.environ["HEIGHT"])
seed = int(os.environ["SEED"])

pipe = None
err = None
dtype = torch.bfloat16 if torch.cuda.is_available() else torch.float32
for attempt in range(3):
    try:
        try:
            from diffusers import MageFlowPipeline as Pipe
        except Exception:
            from diffusers import DiffusionPipeline as Pipe
        pipe = Pipe.from_pretrained(model_id, torch_dtype=dtype, trust_remote_code=True)
        pipe = pipe.to("cuda")
        break
    except Exception as e:
        err = e
        print("load fail", e)
        time.sleep(2)
if pipe is None:
    # last resort: clone custom code from HF repo into cwd
    from huggingface_hub import snapshot_download
    from diffusers import DiffusionPipeline
    local = snapshot_download(model_id, token=os.environ.get("HF_TOKEN") or True)
    pipe = DiffusionPipeline.from_pretrained(local, torch_dtype=dtype, trust_remote_code=True)
    pipe = pipe.to("cuda")
    if pipe is None:
        raise SystemExit(f"failed to load {model_id}: {err}")

prompt = (
    "a sleek matte-black compact accelerator module on a light oak desk, "
    "product photography, soft natural window light, abstract geometric mark only, "
    "absolutely no text, no letters, no numbers, no watermark, no logo overlay, no caption, no typography"
)
negative = "text, letters, words, caption, watermark, logo overlay, typography, writing, sign, label"

# warmup
g = torch.Generator(device="cuda").manual_seed(0)
_ = pipe(prompt=prompt, negative_prompt=negative, num_inference_steps=max(4, steps//4),
         width=w, height=h, generator=g).images[0]
torch.cuda.synchronize()

latencies = []
images = []
for i in range(4):
    g = torch.Generator(device="cuda").manual_seed(seed + i)
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    img = pipe(prompt=prompt, negative_prompt=negative, num_inference_steps=steps,
               width=w, height=h, generator=g).images[0]
    torch.cuda.synchronize()
    dt = time.perf_counter() - t0
    latencies.append(dt)
    images.append(img)
    print(f"seed={seed+i} latency={dt:.3f}s")

mean = sum(latencies)/len(latencies)
peak = torch.cuda.max_memory_allocated() / (1024**3) if torch.cuda.is_available() else 0
# pick mid seed as showcase
images[1].save(out / "showcase.png")
images[0].save(out / "cand-0.png")
images[2].save(out / "cand-2.png")
meta = {
    "model": model_id,
    "steps": steps,
    "width": w,
    "height": h,
    "latencies_s": latencies,
    "mean_latency_s": mean,
    "images_per_s": 1.0/mean if mean else 0,
    "peak_vram_gb": peak,
    "prompt_note": "word-free product still",
}
(out / "t2i-bench.json").write_text(json.dumps(meta, indent=2))
print(json.dumps(meta, indent=2))
nvidia = os.popen("nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv").read()
(out / "nvidia-smi.txt").write_text(nvidia)
print(nvidia)
PY

echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
