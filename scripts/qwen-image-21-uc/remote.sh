#!/usr/bin/env bash
# Qwen-Image-2.1 uncensored Q8_0 via ComfyUI and leejet/ComfyUI-GGUF.
# Headline: mean seconds for one 1024x1024 still at 40 steps.
# One timed call is one still. Not token throughput. Not the BF16 diffusers page.
# Weights: qwen-image-2.1-UC-Q8_0.gguf + BF16 text encoder + BF16 VAE.
# Env: SKU
set -euo pipefail
SKU=${SKU:?set SKU e.g. gpu_1x_a6000}
REPO=${REPO:-abenzerps/Qwen-Image-2.1-Uncensored-GGUF}
REVISION=${REVISION:-6b34e59458d3eb7ba6a6f86a116aed5253dc02c3}
export REVISION
UNET=${UNET:-qwen-image-2.1-UC-Q8_0.gguf}
TE=${TE:-qwen3vl_8b_bf16.safetensors}
VAE=${VAE:-qwen_image_2.1_vae_bf16.safetensors}
COMFY_REV=${COMFY_REV:-7a5dad695fe1cae25efcb2550530fb20ef68da3d}
GGUF_REV=${GGUF_REV:-373048b8403a7820620065210a691263d4da0a61}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/qwen-image-21-uc/${SKU}/q8-bf16te}
COMFY=$HOME/mc-bench/ComfyUI
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/mc-bench/venv"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

for _ in 1 2 3 4 5 6 7 8 9 10; do
  sudo apt-get update -qq && break
  sleep 15
done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3.12-venv python3-pip git curl ca-certificates libgl1 libglib2.0-0

if [[ ! -d $HOME/mc-bench/venv/bin ]]; then
  python3.12 -m venv "$HOME/mc-bench/venv"
fi
# shellcheck disable=SC1091
source "$HOME/mc-bench/venv/bin/activate"
python -m pip install -q -U pip wheel
python -m pip install -q huggingface_hub gguf sentencepiece protobuf

pin_repo() {
  local url=$1 dest=$2 rev=$3
  if [[ ! -d $dest/.git ]]; then
    rm -rf "$dest"
    git clone --filter=blob:none "$url" "$dest"
  fi
  git -C "$dest" fetch --depth 1 origin "$rev"
  git -C "$dest" checkout --detach FETCH_HEAD
  git -C "$dest" rev-parse HEAD
}

log "pin ComfyUI $COMFY_REV"
pin_repo https://github.com/comfyanonymous/ComfyUI "$COMFY" "$COMFY_REV" | tee "$OUTDIR/comfy-rev.txt"
log "pin ComfyUI-GGUF $GGUF_REV"
pin_repo https://github.com/leejet/ComfyUI-GGUF "$COMFY/custom_nodes/ComfyUI-GGUF" "$GGUF_REV" | tee "$OUTDIR/gguf-rev.txt"

python -m pip install -q -r "$COMFY/requirements.txt"
python -m pip install -q -r "$COMFY/custom_nodes/ComfyUI-GGUF/requirements.txt"
python -m pip install -q torch==2.14.1 torchvision --index-url https://download.pytorch.org/whl/cu130
python - <<'PY' | tee "$OUTDIR/torch-version.txt"
import torch
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
PY

log "download Q8 GGUF, BF16 text encoder, BF16 VAE"
python - <<'PY'
import os, shutil
from pathlib import Path
from huggingface_hub import hf_hub_download

repo = os.environ.get("REPO", "abenzerps/Qwen-Image-2.1-Uncensored-GGUF")
comfy = Path.home() / "mc-bench" / "ComfyUI" / "models"
jobs = [
    (os.environ.get("UNET", "qwen-image-2.1-UC-Q8_0.gguf"), comfy / "diffusion_models"),
    ("text_encoders/" + os.environ.get("TE", "qwen3vl_8b_bf16.safetensors"), comfy / "text_encoders"),
    ("vae/" + os.environ.get("VAE", "qwen_image_2.1_vae_bf16.safetensors"), comfy / "vae"),
]
for rel, dest_dir in jobs:
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / Path(rel).name
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print("have", dest.name, dest.stat().st_size, flush=True)
        continue
    print("fetch", rel, flush=True)
    got = Path(hf_hub_download(repo_id=repo, filename=rel, revision=os.environ["REVISION"])).resolve(strict=True)
    if dest.is_symlink() or dest.exists():
        dest.unlink()
    try:
        os.link(got, dest)
    except OSError:
        shutil.copy2(got, dest)
    if not dest.is_file() or dest.stat().st_size < 1_000_000:
        raise SystemExit(f"weight missing after copy: {dest}")
    print("ok", dest.name, dest.stat().st_size, flush=True)
PY

export REPO UNET TE VAE OUTDIR COMFY SKU
nvidia-smi >"$OUTDIR/nvidia-smi.txt"

log "start ComfyUI"
pkill -f "python.*main.py" >/dev/null 2>&1 || true
cd "$COMFY"
nohup "$HOME/mc-bench/venv/bin/python" main.py --listen 127.0.0.1 --port 8188 --cache-none >"$OUTDIR/comfy.log" 2>&1 &
echo $! >"$OUTDIR/comfy.pid"
ready=0
for _ in $(seq 1 180); do
  if curl -sf http://127.0.0.1:8188/system_stats >/dev/null; then ready=1; break; fi
  sleep 2
done
if [[ $ready != 1 ]]; then
  tail -n 120 "$OUTDIR/comfy.log" || true
  exit 1
fi
log "ComfyUI ready"

if [[ "${SAMPLE_ONLY:-0}" == "1" ]]; then
  export SAMPLE_PROMPT
  python - <<'PY'
import json, os, time, urllib.request, shutil
from pathlib import Path

out = Path(os.environ["OUTDIR"])
prompt = os.environ["SAMPLE_PROMPT"]
unet, te, vae = os.environ["UNET"], os.environ["TE"], os.environ["VAE"]

def post(path, payload=None, timeout=60):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request("http://127.0.0.1:8188" + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())

graph = {
    "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": unet}},
    "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": te, "type": "qwen_image", "device": "default"}},
    "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
    "4": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": "auto", "dtype": "default"}},
    "5": {"class_type": "TextEncodeQwenImage21", "inputs": {"clip": ["2", 0], "prompt": prompt, "negative_prompt": "", "resolution": 1024}},
    "6": {"class_type": "EmptyLatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
    "7": {"class_type": "KSampler", "inputs": {
        "model": ["4", 0], "positive": ["5", 0], "negative": ["5", 1], "latent_image": ["6", 0],
        "seed": 42, "steps": 40, "cfg": 1.0, "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0,
    }},
    "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 0]}},
    "9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": "qwenuc_sample"}},
}
queued = post("/prompt", {"prompt": graph})
prompt_id = queued["prompt_id"]
hist = None
deadline = time.perf_counter() + 900
while time.perf_counter() < deadline:
    blob = post(f"/history/{prompt_id}")
    if prompt_id in blob:
        hist = blob[prompt_id]
        status = hist.get("status") or {}
        if status.get("completed") or status.get("status_str") in ("success", "error"):
            break
    time.sleep(1)
if not hist or (hist.get("status") or {}).get("status_str") == "error":
    raise SystemExit(json.dumps((hist or {}).get("status", {}))[:2000])
images = []
for node in (hist.get("outputs") or {}).values():
    images.extend(node.get("images") or [])
if not images:
    raise SystemExit("no image in history")
src = Path.home() / "mc-bench" / "ComfyUI" / "output" / images[0]["filename"]
if images[0].get("subfolder"):
    src = Path.home() / "mc-bench" / "ComfyUI" / "output" / images[0]["subfolder"] / images[0]["filename"]
dest = out / "sample-1024.png"
shutil.copy2(src, dest)
print("SAMPLE", dest, dest.stat().st_size)
PY
  log "sample written"
  exit 0
fi

python - <<'PY'
import json, os, time, urllib.request, subprocess, threading
from pathlib import Path

out = Path(os.environ["OUTDIR"])
unet = os.environ["UNET"]
te = os.environ["TE"]
vae = os.environ["VAE"]
prompt = "ceramic espresso cup on sunlit oak, shallow depth of field, no text in the image."
steps = 40
seed = 42
warmup_n = 2
timed_n = 5
resolutions = [(1024, 1024), (2048, 2048)]

def post(path, payload=None, timeout=30):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8188" + path,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())

info = post("/object_info", timeout=120)
missing = [n for n in ("UnetLoaderGGUF", "CLIPLoader", "VAELoader", "TextEncodeQwenImage21", "QwenImage21Cache", "KSampler", "EmptyLatentImage", "VAEDecode", "SaveImage") if n not in info]
if missing:
    raise SystemExit("missing nodes: " + ",".join(missing))

stop = threading.Event()
smi_lines = []

def sample_smi():
    while not stop.is_set():
        try:
            line = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=timestamp,memory.used,utilization.gpu,memory.total", "--format=csv,noheader,nounits"],
                text=True,
            ).strip()
        except subprocess.CalledProcessError:
            line = ""
        if line:
            smi_lines.append(line)
        stop.wait(2)

def graph(width, height, call_i):
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": unet}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": te, "type": "qwen_image", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
        "4": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": "auto", "dtype": "default"}},
        "5": {"class_type": "TextEncodeQwenImage21", "inputs": {
            "clip": ["2", 0], "prompt": prompt, "negative_prompt": "", "resolution": width,
        }},
        "6": {"class_type": "EmptyLatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "7": {"class_type": "KSampler", "inputs": {
            "model": ["4", 0], "positive": ["5", 0], "negative": ["5", 1], "latent_image": ["6", 0],
            "seed": seed, "steps": steps, "cfg": 1.0, "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0,
        }},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 0]}},
        "9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": f"qwenuc_{width}_{call_i}"}},
    }

def run_once(width, height, call_i):
    started = time.perf_counter()
    queued = post("/prompt", {"prompt": graph(width, height, call_i)})
    prompt_id = queued["prompt_id"]
    deadline = time.perf_counter() + 3600
    hist = None
    while time.perf_counter() < deadline:
        blob = post(f"/history/{prompt_id}", timeout=60)
        if prompt_id in blob:
            hist = blob[prompt_id]
            status = hist.get("status") or {}
            if status.get("completed") or status.get("status_str") in ("success", "error"):
                break
        time.sleep(1)
    wall = time.perf_counter() - started
    if not hist:
        raise RuntimeError(f"no history for {width} call {call_i}")
    status = hist.get("status") or {}
    if status.get("status_str") == "error" or not status.get("completed"):
        msgs = status.get("messages") or []
        raise RuntimeError(json.dumps(msgs)[:2000])
    exec_s = None
    start_ms = end_ms = None
    for kind, payload in status.get("messages") or []:
        if kind == "execution_start":
            start_ms = payload.get("timestamp")
        elif kind == "execution_success":
            end_ms = payload.get("timestamp")
    if start_ms and end_ms:
        exec_s = (end_ms - start_ms) / 1000.0
    return {"wall_s": round(wall, 3), "execution_s": None if exec_s is None else round(exec_s, 3)}

results = []
errors = []
sampler = threading.Thread(target=sample_smi, daemon=True)
sampler.start()
try:
    for width, height in resolutions:
        row = {"width": width, "height": height, "steps": steps, "warmup": [], "timed": []}
        try:
            for i in range(warmup_n):
                row["warmup"].append(run_once(width, height, f"w{i}"))
            for i in range(timed_n):
                row["timed"].append(run_once(width, height, f"t{i}"))
        except Exception as exc:
            row["error"] = str(exc)
            errors.append({"width": width, "height": height, "error": str(exc)})
            results.append(row)
            continue
        times = [c["execution_s"] if c["execution_s"] is not None else c["wall_s"] for c in row["timed"]]
        times_sorted = sorted(times)
        mean = sum(times) / len(times)
        row["mean_s"] = round(mean, 3)
        row["p50_s"] = round(times_sorted[len(times_sorted)//2], 3)
        row["images_per_s"] = round(1.0 / mean, 6) if mean else None
        results.append(row)
finally:
    stop.set()
    sampler.join(timeout=5)

smi_path = out / "nvidia-smi.txt"
with smi_path.open("a") as fh:
    fh.write("\n# during generation\n")
    for line in smi_lines:
        fh.write(line + "\n")

used = []
for line in smi_lines:
    parts = [p.strip() for p in line.split(",")]
    if len(parts) >= 2:
        try:
            used.append(float(parts[1]))
        except ValueError:
            pass
peak_mib = max(used) if used else None

import torch
report = {
    "model": "abenzerps/Qwen-Image-2.1-Uncensored-GGUF",
    "file": unet,
    "text_encoder": te,
    "vae": vae,
    "engine": "ComfyUI UnetLoaderGGUF + TextEncodeQwenImage21 + KSampler",
    "sku": os.environ["SKU"],
    "prompt": prompt,
    "steps": steps,
    "cfg": 1.0,
    "sampler": "euler",
    "scheduler": "simple",
    "seed": seed,
    "warmup_n": warmup_n,
    "timed_n": timed_n,
    "clock": "ComfyUI execution_start to execution_success; wall_s is the HTTP wait",
    "torch": torch.__version__,
    "comfy_rev": (out / "comfy-rev.txt").read_text().strip().splitlines()[-1],
    "gguf_rev": (out / "gguf-rev.txt").read_text().strip().splitlines()[-1],
    "peak_vram_mib": peak_mib,
    "results": results,
    "errors": errors,
}
(out / "bench.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"peak_vram_mib": peak_mib, "rows": [{k: r.get(k) for k in ("width", "mean_s", "error")} for r in results]}, indent=2))
ok_1024 = any(r.get("width") == 1024 and r.get("mean_s") for r in results)
if not ok_1024:
    raise SystemExit("1024 run did not finish")
PY

test -s "$OUTDIR/bench.json"
test -s "$OUTDIR/nvidia-smi.txt"
log "done"
touch "$OUTDIR/DONE"
