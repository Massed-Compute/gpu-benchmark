#!/usr/bin/env bash
# FLUX.1-dev INT8 ConvRot via ComfyUI — packing bench, word-free showcase.
# Env: HF_TOKEN OUTDIR
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/flux-convrot}
REPO=${REPO:-SearchingMan/FLUX.1-dev-ConvRot}
WEIGHT=${WEIGHT:-FLUX.1-dev-int8_convrot.safetensors}
STEPS=${STEPS:-20}
WIDTH=${WIDTH:-1024}
HEIGHT=${HEIGHT:-1024}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" HF_HUB_ENABLE_HF_TRANSFER=1

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  python3-venv python3-pip git curl jq libgl1 libglib2.0-0 || true
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel huggingface_hub hf_transfer
pip install -q -U torch torchvision --index-url https://download.pytorch.org/whl/cu128 || pip install -q -U torch torchvision

COMFY="$HOME/mc-bench/ComfyUI"
if [[ ! -d "$COMFY" ]]; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI "$COMFY"
fi
pip install -q -r "$COMFY/requirements.txt"

log "download ConvRot INT8 + TE/VAE"
python3 - <<'PY'
from huggingface_hub import hf_hub_download
from pathlib import Path
import os, shutil
home = Path.home() / "mc-bench" / "ComfyUI" / "models"
for sub in ("unet", "diffusion_models", "clip", "text_encoders", "vae"):
    (home / sub).mkdir(parents=True, exist_ok=True)
token = os.environ.get("HF_TOKEN") or True
repo = os.environ.get("REPO", "SearchingMan/FLUX.1-dev-ConvRot")
w = os.environ.get("WEIGHT", "FLUX.1-dev-int8_convrot.safetensors")
p = hf_hub_download(repo, w, token=token)
dest = home / "unet" / w
if not dest.exists():
    shutil.copy2(p, dest)
print("unet", dest, dest.stat().st_size)
# shared FLUX TE/VAE from Comfy-Org
for repo2, files, sub in [
    ("comfyanonymous/flux_text_encoders", ["clip_l.safetensors", "t5xxl_fp8_e4m3fn.safetensors"], "clip"),
    ("black-forest-labs/FLUX.1-dev", ["ae.safetensors"], "vae"),
]:
    for f in files:
        try:
            p = hf_hub_download(repo2, f, token=token)
            d = home / sub / f
            if not d.exists():
                shutil.copy2(p, d)
            print(sub, d)
        except Exception as e:
            print("skip", repo2, f, e)
# also try ConvRot TE if present
try:
    p = hf_hub_download(repo, "t5xxl_flux1_int8_convrot.safetensors", token=token)
    d = home / "clip" / "t5xxl_flux1_int8_convrot.safetensors"
    if not d.exists():
        shutil.copy2(p, d)
    print("TE convrot", d)
except Exception as e:
    print("no convrot TE", e)
PY

log "start ComfyUI"
pkill -f "python.*main.py" >/dev/null 2>&1 || true
cd "$COMFY"
nohup "$HOME/mc-bench/venv/bin/python" main.py --listen 127.0.0.1 --port 8188 >"$OUTDIR/comfy.log" 2>&1 &
echo $! >"$OUTDIR/comfy.pid"
for i in $(seq 1 90); do
  if curl -sf http://127.0.0.1:8188/system_stats >/dev/null; then break; fi
  sleep 2
done
curl -sf http://127.0.0.1:8188/system_stats >/dev/null || { tail -100 "$OUTDIR/comfy.log"; exit 1; }
log COMFY_READY

export OUTDIR WEIGHT STEPS WIDTH HEIGHT
python3 - <<'PY'
import json, os, time, uuid, urllib.request
from pathlib import Path

out = Path(os.environ["OUTDIR"])
weight = os.environ["WEIGHT"]
steps = int(os.environ["STEPS"])
w = int(os.environ["WIDTH"]); h = int(os.environ["HEIGHT"])
prompt_text = (
    "a sleek matte-black compact accelerator module on a light oak desk, "
    "product photography, soft natural window light, abstract geometric mark only, "
    "absolutely no text, no letters, no numbers, no watermark, no logo overlay, no caption, no typography"
)
neg = "text, letters, words, caption, watermark, logo overlay, typography, writing, sign, label"

def queue(workflow):
    data = json.dumps({"prompt": workflow, "client_id": str(uuid.uuid4())}).encode()
    req = urllib.request.Request("http://127.0.0.1:8188/prompt", data=data, headers={"Content-Type":"application/json"})
    return json.loads(urllib.request.urlopen(req).read())["prompt_id"]

def wait(pid, timeout=600):
    t0 = time.time()
    while time.time() - t0 < timeout:
        hist = json.loads(urllib.request.urlopen("http://127.0.0.1:8188/history/"+pid).read())
        if pid in hist:
            return hist[pid]
        time.sleep(1)
    raise TimeoutError(pid)

def build(seed):
    # Minimal FLUX graph; node ids stable
    te = "t5xxl_fp8_e4m3fn.safetensors"
    if (Path.home()/"mc-bench/ComfyUI/models/clip/t5xxl_flux1_int8_convrot.safetensors").exists():
        te = "t5xxl_flux1_int8_convrot.safetensors"
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": weight, "weight_dtype": "default"}},
        "2": {"class_type": "DualCLIPLoader", "inputs": {"clip_name1": "clip_l.safetensors", "clip_name2": te, "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt_text}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": neg}},
        "6": {"class_type": "EmptySD3LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "7": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["4", 0], "guidance": 3.5}},
        "8": {"class_type": "KSampler", "inputs": {
            "model": ["1", 0], "seed": seed, "steps": steps, "cfg": 1.0,
            "sampler_name": "euler", "scheduler": "simple", "positive": ["7", 0],
            "negative": ["5", 0], "latent_image": ["6", 0], "denoise": 1.0
        }},
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": f"flux_convrot_{seed}"}},
    }

# warmup
wait(queue(build(1)))
latencies = []
for i, seed in enumerate([11, 22, 33, 44]):
    t0 = time.perf_counter()
    hist = wait(queue(build(seed)))
    dt = time.perf_counter() - t0
    latencies.append(dt)
    print(f"seed={seed} latency={dt:.3f}s")
    # copy last image
    outs = hist.get("outputs", {}).get("10", {}).get("images", [])
    if outs:
        src = Path.home()/"mc-bench/ComfyUI/output"/outs[0]["filename"]
        dest = out / f"cand-{i}.png"
        if src.exists():
            dest.write_bytes(src.read_bytes())
            if i == 1:
                (out / "showcase.png").write_bytes(src.read_bytes())

mean = sum(latencies)/len(latencies)
import subprocess
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
meta = {
    "model": "SearchingMan/FLUX.1-dev-ConvRot",
    "weight": weight,
    "packing": "INT8 ConvRot (not a new base)",
    "steps": steps, "width": w, "height": h,
    "latencies_s": latencies,
    "mean_latency_s": mean,
    "images_per_s": 1.0/mean if mean else 0,
    "peak_vram_gb": round(peak_vram_gb, 1),
}
(out / "t2i-bench.json").write_text(json.dumps(meta, indent=2) + "\n")
print(json.dumps(meta, indent=2))
PY

echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
