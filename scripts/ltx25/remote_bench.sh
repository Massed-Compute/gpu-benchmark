#!/usr/bin/env bash
# LTX-2.5 DistilledPipeline T2V bench on a disposable mc-bench-ltx25-* VM.
# Locked clip: 1024x1536, 121 frames, 24 fps, seed 42, official distilled BF16 pack.
set -euo pipefail

SKU=${SKU:?set SKU e.g. gpu_1x_l40s}
HF_TOKEN=${HF_TOKEN:?set HF_TOKEN}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/ltx25}
REPO_DIR=${REPO_DIR:-$HOME/mc-bench/LTX-2}
MODELS=${MODELS:-$REPO_DIR/models/ltx-2.5}
HEIGHT=${HEIGHT:-1024}
WIDTH=${WIDTH:-1536}
NUM_FRAMES=${NUM_FRAMES:-121}
FPS=${FPS:-24}
SEED=${SEED:-42}
PROMPT=${PROMPT:-'A compact GPU accelerator module on a clean desk in soft daylight, camera slowly pushes in, quiet fan whir and room tone, no text no logos no watermarks.'}

export HF_TOKEN HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_HUB_ENABLE_HF_TRANSFER=1
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface"
printf '%s\n' "$HF_TOKEN" > "$HOME/.cache/huggingface/token"
chmod 600 "$HOME/.cache/huggingface/token"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
export PATH="$HOME/.local/bin:$PATH"

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git curl jq ffmpeg python3-venv python3-pip build-essential || true

if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/Lightricks/LTX-2.git "$REPO_DIR"
fi
cd "$REPO_DIR"

log "uv sync"
if ! uv sync --extra natten; then
  log "natten extra failed; falling back to uv sync"
  uv sync
fi

log "download distilled BF16 pack (~66 GiB)"
if uv run hf download Lightricks/LTX-2.5 \
  diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors \
  text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors \
  vae/ltx-2.5-video-vae-bf16.safetensors \
  vae/ltx-2.5-audio-vae-bf16.safetensors \
  latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
  --local-dir "$MODELS"; then
  :
else
  uv run huggingface-cli download Lightricks/LTX-2.5 \
    diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors \
    text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors \
    vae/ltx-2.5-video-vae-bf16.safetensors \
    vae/ltx-2.5-audio-vae-bf16.safetensors \
    latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors \
    --local-dir "$MODELS"
fi

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | tee "$OUTDIR/nvidia-smi-id.txt"
uv run python - <<'PY' | tee "$OUTDIR/torch.txt" || true
import torch
print("torch", torch.__version__, "cuda", torch.version.cuda, "avail", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu", torch.cuda.get_device_name(0))
PY

run_one() {
  local label=$1
  shift
  local mp4="$OUTDIR/${label}.mp4"
  local logf="$OUTDIR/${label}.log"
  local vramf="$OUTDIR/${label}.vram.csv"
  rm -f "$mp4"
  : > "$vramf"
  local smi_pid=""
  (
    while true; do
      nvidia-smi --query-gpu=timestamp,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits >> "$vramf" || true
      sleep 1
    done
  ) &
  smi_pid=$!
  local t0 t1 rc
  t0=$(date +%s.%N)
  set +e
  uv run python -m ltx_pipelines.distilled \
    --transformer-path       "$MODELS/diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors" \
    --text-encoder-path      "$MODELS/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors" \
    --video-vae-path         "$MODELS/vae/ltx-2.5-video-vae-bf16.safetensors" \
    --audio-vae-path         "$MODELS/vae/ltx-2.5-audio-vae-bf16.safetensors" \
    --spatial-upsampler-path "$MODELS/latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" \
    --height "$HEIGHT" --width "$WIDTH" --num-frames "$NUM_FRAMES" --frame-rate "$FPS" \
    --seed "$SEED" --prompt "$PROMPT" --output-path "$mp4" \
    "$@" >"$logf" 2>&1
  rc=$?
  set -e
  t1=$(date +%s.%N)
  kill "$smi_pid" 2>/dev/null || true
  wait "$smi_pid" 2>/dev/null || true
  python3 - "$OUTDIR" "$label" "$SKU" "$rc" "$t0" "$t1" "$mp4" "$HEIGHT" "$WIDTH" "$NUM_FRAMES" "$FPS" "$SEED" <<'PY'
import csv, json, os, subprocess, sys
from pathlib import Path
outdir, label, sku, rc, t0, t1, mp4, h, w, nf, fps, seed = sys.argv[1:13]
rc = int(rc)
wall = float(t1) - float(t0)
peak = 0.0
vramf = Path(outdir) / f"{label}.vram.csv"
if vramf.exists():
    for row in csv.reader(vramf.read_text().splitlines()):
        if not row:
            continue
        try:
            peak = max(peak, float(row[1].strip()))
        except Exception:
            pass
ffprobe = {}
p = Path(mp4)
if p.exists() and p.stat().st_size > 1024:
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(p)],
            text=True,
        )
        ffprobe = json.loads(out)
    except Exception as e:
        ffprobe = {"error": str(e)}
    still = Path(outdir) / f"{label}.png"
    subprocess.call(["ffmpeg", "-y", "-ss", "1.5", "-i", str(p), "-frames:v", "1", str(still)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
blob = {
    "sku": sku,
    "label": label,
    "status": "ok" if rc == 0 and p.exists() and p.stat().st_size > 1024 else "fail",
    "exit_code": rc,
    "wall_s": round(wall, 3),
    "peak_vram_mib": peak,
    "peak_vram_gib": round(peak / 1024.0, 2) if peak else None,
    "mp4": str(p) if p.exists() else None,
    "mp4_bytes": p.stat().st_size if p.exists() else 0,
    "height": int(h), "width": int(w), "num_frames": int(nf),
    "fps": float(fps), "seed": int(seed),
    "ffprobe": ffprobe,
    "extra_args": os.environ.get("LTX_EXTRA_ARGS", ""),
}
Path(outdir, f"{label}.json").write_text(json.dumps(blob, indent=2) + "\n")
print(json.dumps(blob, indent=2))
sys.exit(0 if blob["status"] == "ok" else 1)
PY
}

log "cold run (native BF16, no offload)"
if run_one cold; then
  log "warm run (native BF16)"
  run_one warm || true
else
  log "native failed; retry fp8-cast + cpu offload (L40S / OOM path)"
  export LTX_EXTRA_ARGS="fp8-cast,cpu-offload"
  if run_one cold_fp8 --quantization fp8-cast --offload cpu; then
    run_one warm_fp8 --quantization fp8-cast --offload cpu || true
  fi
fi

python3 - "$OUTDIR" "$SKU" <<'PY'
import json, sys
from pathlib import Path
outdir, sku = Path(sys.argv[1]), sys.argv[2]
rows = []
for p in sorted(outdir.glob("*.json")):
    if p.name in ("summary.json", "plan.json"):
        continue
    try:
        rows.append(json.loads(p.read_text()))
    except Exception:
        pass
summary = {"sku": sku, "engine": "ltx-pipelines.distilled", "hf_id": "Lightricks/LTX-2.5",
           "checkpoint": "ltx-2.5-22b-distilled-transformer-bf16", "runs": rows}
(outdir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print("wrote", outdir / "summary.json")
PY

log "done"
touch "$OUTDIR/DONE"
