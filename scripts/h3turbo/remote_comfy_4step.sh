#!/usr/bin/env bash
# MiniMax-H3 Turbo 4-step via core ComfyUI (MAR-88 redo).
# Lock: 1344x768, 4 steps, Euler, video shift 6, audio shift 3, 124 frames, seed 42.
# Env: HF_TOKEN (or ~/.cache/huggingface/token)
set -euo pipefail

HF_TOKEN=${HF_TOKEN:-}
if [[ -z "$HF_TOKEN" && -f "$HOME/.cache/huggingface/token" ]]; then
  tok=$(tr -d '[:space:]' <"$HOME/.cache/huggingface/token")
  HF_TOKEN=$tok
fi
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/h3-turbo-comfy}
COMFY="$HOME/mc-bench/ComfyUI"
UNET=minimax_h3_fl2va_pruned_int8_convrot.safetensors
TE=qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
VIDEO_VAE=minimax_h3_video_vae_fp16.safetensors
AUDIO_VAE=minimax_h3_audio_vae_fp32.safetensors
LORA=minimax_h3_fl2v_turbo_4step_v1.2_768p_comfyui_bf16.safetensors
WIDTH=1344
HEIGHT=768
STEPS=4
FRAMES=124
SEED=42
SHIFT_V=6
SHIFT_A=3
FPS=24

mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" HF_HUB_ENABLE_HF_TRANSFER=1
export OUTDIR UNET TE VIDEO_VAE AUDIO_VAE LORA WIDTH HEIGHT STEPS FRAMES SEED SHIFT_V SHIFT_A FPS COMFY

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

log "host $(hostname) gpu=$(nvidia-smi -L 2>/dev/null | head -1 || true)"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate" 2>/dev/null || true

if [[ "${SKIP_SETUP:-0}" != "1" ]]; then
free -h | tee "$OUTDIR/mem-before.txt"
df -h / | tee "$OUTDIR/disk-before.txt"
nvidia-smi | tee "$OUTDIR/nvidia-smi-boot.txt"

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  python3-venv python3-pip git curl jq ffmpeg libgl1 libglib2.0-0 || true

python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel huggingface_hub hf_transfer

if [[ ! -d "$COMFY/.git" ]]; then
  rm -rf "$COMFY"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI "$COMFY"
fi
pip install -q -r "$COMFY/requirements.txt"
pip install -q av opencv-python-headless || true

log "download Comfy-Org MiniMax-H3 + Turbo 4-step LoRA"
python3 - <<'PY'
from huggingface_hub import hf_hub_download
from pathlib import Path
import os, shutil

home = Path.home() / "mc-bench" / "ComfyUI" / "models"
dirs = {
    "diffusion_models": home / "diffusion_models",
    "text_encoders": home / "text_encoders",
    "vae": home / "vae",
    "loras": home / "loras",
}
for p in dirs.values():
    p.mkdir(parents=True, exist_ok=True)
token = os.environ.get("HF_TOKEN") or None

jobs = [
    ("Comfy-Org/MiniMax-H3", f"diffusion_models/{os.environ['UNET']}", dirs["diffusion_models"] / os.environ["UNET"]),
    ("Comfy-Org/MiniMax-H3", f"text_encoders/{os.environ['TE']}", dirs["text_encoders"] / os.environ["TE"]),
    ("Comfy-Org/MiniMax-H3", f"vae/{os.environ['VIDEO_VAE']}", dirs["vae"] / os.environ["VIDEO_VAE"]),
    ("Comfy-Org/MiniMax-H3", f"vae/{os.environ['AUDIO_VAE']}", dirs["vae"] / os.environ["AUDIO_VAE"]),
    ("lightx2v/Minimax-h3-Turbo", os.environ["LORA"], dirs["loras"] / os.environ["LORA"]),
]
for repo, rel, dest in jobs:
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print("have", dest, dest.stat().st_size, flush=True)
        continue
    print("fetch", repo, rel, flush=True)
    p = hf_hub_download(repo_id=repo, filename=rel, token=token)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() or dest.is_symlink():
        dest.unlink()
    try:
        os.link(p, dest)
    except OSError:
        os.replace(p, dest)
    print("ok", dest, dest.stat().st_size, flush=True)
print("WEIGHTS_OK", flush=True)
PY
echo WEIGHTS_OK >"$OUTDIR/WEIGHTS_OK"
df -h / | tee "$OUTDIR/disk-after-weights.txt"

# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
log "align torch torchvision torchaudio (same CUDA wheel)"
pip install -U torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130 || \
  pip install -U torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
python -c "import torch, torchaudio; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'ta', torchaudio.__version__, flush=True)"
fi

unset HF_TOKEN HUGGING_FACE_HUB_TOKEN
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"

log "start ComfyUI"
pkill -f "python.*main.py" >/dev/null 2>&1 || true
cd "$COMFY"
nohup "$HOME/mc-bench/venv/bin/python" main.py --listen 127.0.0.1 --port 8188 --cache-none >"$OUTDIR/comfy.log" 2>&1 &
echo $! >"$OUTDIR/comfy.pid"
for i in $(seq 1 120); do
  if curl -sf http://127.0.0.1:8188/system_stats >/dev/null; then break; fi
  sleep 2
done
curl -sf http://127.0.0.1:8188/system_stats >/dev/null || { tail -200 "$OUTDIR/comfy.log"; exit 1; }
log COMFY_READY
python3 - <<'PY'
import json, urllib.request
from pathlib import Path
info = json.loads(urllib.request.urlopen("http://127.0.0.1:8188/object_info").read())
keys = [k for k in sorted(info) if "MiniMax" in k or k in (
    "CreateVideo", "SaveVideo", "LoraLoaderModelOnly", "CLIPLoader",
    "UNETLoader", "VAELoader", "SamplerCustomAdvanced", "BasicGuider",
    "BasicScheduler", "KSamplerSelect", "RandomNoise", "VAEDecode",
    "VAEDecodeAudio", "MiniMaxH3ImageToVideo", "MiniMaxH3SigmaShift",
)]
out = Path.home() / "mc-bench/out/h3-turbo-comfy/object_info_minimax.json"
slim = {}
for k in keys:
    inp = info[k].get("input", {})
    slim[k] = {"required": list(inp.get("required", {})), "optional": list(inp.get("optional", {}))}
out.write_text(json.dumps(slim, indent=2) + "\n")
print("nodes", json.dumps(slim, indent=2))
missing = [n for n in ("MiniMaxH3ImageToVideo", "MiniMaxH3SigmaShift") if n not in info]
if missing:
    raise SystemExit("missing MiniMax nodes: " + ",".join(missing) + " available=" + ",".join(k for k in info if "iniMax" in k or "MiniMax" in k))
PY

log "queue 4-step T2V (cold then warm)"
python3 - <<'PY'
import json, os, time, uuid, urllib.request, subprocess, shutil, threading
from pathlib import Path

out = Path(os.environ["OUTDIR"])
unet = os.environ["UNET"]
te = os.environ["TE"]
video_vae = os.environ["VIDEO_VAE"]
audio_vae = os.environ["AUDIO_VAE"]
lora = os.environ["LORA"]
width = int(os.environ["WIDTH"])
height = int(os.environ["HEIGHT"])
steps = int(os.environ["STEPS"])
frames = int(os.environ["FRAMES"])
seed = int(os.environ["SEED"])
shift_v = float(os.environ["SHIFT_V"])
shift_a = float(os.environ["SHIFT_A"])
fps = float(os.environ["FPS"])

prompt_text = (
    "integrated_multimodal_description: A compact GPU accelerator module on a clean oak desk "
    "in soft daylight. Slow cinematic push-in. Practical photography, shallow depth of field, "
    "no text, no logos, no watermarks.\n"
    "overall_soundscape: Quiet room tone, faint HVAC hum, soft cloth rustle.\n"
    "non_diegetic_music: N/A"
)

info = json.loads(urllib.request.urlopen("http://127.0.0.1:8188/object_info").read())

def req_keys(name):
    return list(info[name]["input"].get("required", {}))

def opt_keys(name):
    return list(info[name]["input"].get("optional", {}))

def queue(workflow):
    data = json.dumps({"prompt": workflow, "client_id": str(uuid.uuid4())}).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8188/prompt",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    raw = urllib.request.urlopen(req).read()
    resp = json.loads(raw)
    if "error" in resp or "node_errors" in resp and resp["node_errors"]:
        raise RuntimeError(json.dumps(resp)[:4000])
    return resp["prompt_id"]

def wait(pid, timeout=3600):
    t0 = time.time()
    last_err = None
    while time.time() - t0 < timeout:
        try:
            hist = json.loads(urllib.request.urlopen("http://127.0.0.1:8188/history/" + pid).read())
        except Exception as e:
            last_err = e
            time.sleep(2)
            continue
        if pid in hist:
            st = (hist[pid].get("status") or {})
            if not st.get("completed"):
                time.sleep(2)
                continue
            if st.get("status_str") not in (None, "success"):
                raise RuntimeError(f"{pid} status={st}")
            return hist[pid]
        time.sleep(2)
    raise TimeoutError(f"{pid} last={last_err}")

def build():
    clip_in = {"clip_name": te, "type": "minimax"}
    if "device" in req_keys("CLIPLoader") or "device" in opt_keys("CLIPLoader"):
        clip_in["device"] = "default"
    save_in = {"video": ["12", 0], "filename_prefix": "h3turbo_4step"}
    for k, v in (("format", "auto"), ("codec", "auto")):
        if k in req_keys("SaveVideo") or k in opt_keys("SaveVideo"):
            save_in[k] = v
    create_in = {"images": ["10", 0], "fps": fps}
    if "audio" in req_keys("CreateVideo") or "audio" in opt_keys("CreateVideo"):
        create_in["audio"] = ["11", 0]
    unet_in = {"unet_name": unet}
    if "weight_dtype" in req_keys("UNETLoader") or "weight_dtype" in opt_keys("UNETLoader"):
        unet_in["weight_dtype"] = "default"
    lora_in = {"model": ["1", 0], "lora_name": lora}
    if "strength_model" in req_keys("LoraLoaderModelOnly") or "strength_model" in opt_keys("LoraLoaderModelOnly"):
        lora_in["strength_model"] = 1.0
    h3_in = {
        "clip": ["4", 0],
        "vae": ["5", 0],
        "prompt": prompt_text,
        "width": width,
        "height": height,
        "length": frames,
    }
    wf = {
        "1": {"class_type": "UNETLoader", "inputs": unet_in},
        "2": {"class_type": "LoraLoaderModelOnly", "inputs": lora_in},
        "3": {"class_type": "MiniMaxH3SigmaShift", "inputs": {
            "model": ["2", 0], "shift_video": shift_v, "shift_audio": shift_a,
        }},
        "4": {"class_type": "CLIPLoader", "inputs": clip_in},
        "5": {"class_type": "VAELoader", "inputs": {"vae_name": video_vae}},
        "6": {"class_type": "VAELoader", "inputs": {"vae_name": audio_vae}},
        "7": {"class_type": "MiniMaxH3ImageToVideo", "inputs": h3_in},
        "8": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "9": {"class_type": "BasicGuider", "inputs": {"model": ["3", 0], "conditioning": ["7", 0]}},
        "13": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "14": {"class_type": "BasicScheduler", "inputs": {
            "model": ["3", 0], "scheduler": "simple", "steps": steps, "denoise": 1.0,
        }},
        "15": {"class_type": "SamplerCustomAdvanced", "inputs": {
            "noise": ["8", 0],
            "guider": ["9", 0],
            "sampler": ["13", 0],
            "sigmas": ["14", 0],
            "latent_image": ["7", 1],
        }},
        "10": {"class_type": "VAEDecode", "inputs": {"samples": ["15", 0], "vae": ["5", 0]}},
        "11": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["15", 0], "vae": ["6", 0]}},
        "12": {"class_type": "CreateVideo", "inputs": create_in},
        "16": {"class_type": "SaveVideo", "inputs": save_in},
    }
    (out / "workflow-api.json").write_text(json.dumps(wf, indent=2) + "\n")
    return wf

peak = {"vram_mb": 0}

def vram_loop(stop):
    while not stop.wait(1.0):
        try:
            raw = subprocess.check_output(
                ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                text=True,
            ).strip().splitlines()[0]
            mb = float(raw)
            if mb > peak["vram_mb"]:
                peak["vram_mb"] = mb
        except Exception:
            pass

stop = threading.Event()
th = threading.Thread(target=vram_loop, args=(stop,), daemon=True)
th.start()

wf = build()
print("queue cold", flush=True)
t0 = time.perf_counter()
hist_cold = wait(queue(wf))
cold_s = time.perf_counter() - t0
print(f"cold_s={cold_s:.3f}", flush=True)
(out / "history-cold.json").write_text(json.dumps(hist_cold, default=str)[:200000])

print("queue warm", flush=True)
t1 = time.perf_counter()
hist_warm = wait(queue(wf))
warm_s = time.perf_counter() - t1
print(f"warm_s={warm_s:.3f}", flush=True)
(out / "history-warm.json").write_text(json.dumps(hist_warm, default=str)[:200000])
stop.set()

smi = subprocess.check_output(
    ["nvidia-smi", "--query-gpu=name,memory.used,memory.total", "--format=csv"],
    text=True,
)
(out / "nvidia-smi.txt").write_text(smi)
gpu_name = "unknown"
vram_total_gb = 0.0
for line in smi.splitlines():
    if "MiB" in line and not line.startswith("name"):
        parts = [x.strip() for x in line.split(",")]
        gpu_name = parts[0]
        if len(parts) >= 3 and "MiB" in parts[2]:
            vram_total_gb = float(parts[2].replace("MiB", "").strip()) / 1024.0
        break

def copy_video(hist, dest_name):
    outputs = hist.get("outputs") or {}
    for node in outputs.values():
        for key in ("gifs", "videos", "images"):
            for item in node.get(key) or []:
                fn = item.get("filename")
                sub = item.get("subfolder") or ""
                src = Path.home() / "mc-bench/ComfyUI/output" / sub / fn if fn else None
                if src and src.exists() and src.suffix.lower() in {".mp4", ".webm", ".mkv", ".mov"}:
                    dest = out / dest_name
                    dest.write_bytes(src.read_bytes())
                    return dest
    raise FileNotFoundError(f"no video in history for {dest_name}")

vid = copy_video(hist_warm, "warm_4step.mp4")
still = out / "showcase.png"
if vid and vid.exists():
    subprocess.run(
        ["ffmpeg", "-y", "-ss", "2", "-i", str(vid), "-frames:v", "1", str(still)],
        check=False, capture_output=True,
    )
    if not still.exists():
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(vid), "-frames:v", "1", str(still)],
            check=False, capture_output=True,
        )

mem = subprocess.check_output(["free", "-g"], text=True)
(out / "mem-after.txt").write_text(mem)

meta = {
    "engine": "ComfyUI + MiniMax-H3 core nodes + LightX2V 4-step Turbo LoRA v1.2",
    "base": "Comfy-Org/MiniMax-H3 minimax_h3_fl2va_pruned_int8_convrot",
    "lora": lora,
    "text_encoder": te,
    "lock": {
        "width": width, "height": height, "steps": steps, "frames": frames,
        "fps": fps, "seed": seed, "sampler": "euler", "scheduler": "simple",
        "video_flow_shift": shift_v, "audio_flow_shift": shift_a,
    },
    "gpu_name": gpu_name,
    "cold_s": round(cold_s, 3),
    "warm_s": round(warm_s, 3),
    "peak_vram_gb": round(peak["vram_mb"] / 1024.0, 2),
    "vram_total_gb": round(vram_total_gb, 1),
    "video": str(vid) if vid else None,
    "still": str(still) if still.exists() else None,
}
(out / "bench.json").write_text(json.dumps(meta, indent=2) + "\n")
print(json.dumps(meta, indent=2), flush=True)
if not vid:
    raise SystemExit("no video output")
PY

echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
cat "$OUTDIR/bench.json"
