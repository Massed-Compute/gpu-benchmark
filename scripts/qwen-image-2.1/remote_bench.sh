#!/usr/bin/env bash
# Qwen-Image-2.1 text-to-image via Diffusers QwenImage21Pipeline.
# Env: OUTDIR (required, unique per SKU), HF_TOKEN (optional), MODEL, STEPS, RESOLUTIONS
set -euo pipefail

MODEL=${MODEL:-Qwen/Qwen-Image-2.1}
OUTDIR=${OUTDIR:?OUTDIR required}
STEPS=${STEPS:-40}
RESOLUTIONS=${RESOLUTIONS:-1024x1024,2048x2048}
HF_TOKEN=${HF_TOKEN:-}

mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
if [[ -n "$HF_TOKEN" ]]; then
  install -m 600 /dev/null "$HOME/.cache/huggingface/token"
  printf '%s' "$HF_TOKEN" > "$HOME/.cache/huggingface/token"
  chmod 600 "$HOME/.cache/huggingface/token"
fi
export MODEL OUTDIR STEPS RESOLUTIONS
if [[ -n "$HF_TOKEN" ]]; then
  export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
else
  unset HF_TOKEN HUGGING_FACE_HUB_TOKEN || true
fi
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq || true
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip git curl ca-certificates || true
curl -LsSf https://astral.sh/uv/install.sh | sh || true
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || python3 -m pip install --user uv
export PATH="$HOME/.local/bin:$PATH"

cd "$HOME/mc-bench"
rm -rf diffusers
DIFFUSERS_COMMIT=${DIFFUSERS_COMMIT:-4ac08e940880fa906c36b944a42f420db4e24b26}
git clone --depth 1 https://github.com/huggingface/diffusers.git
if [[ "$(git -C diffusers rev-parse HEAD)" != "$DIFFUSERS_COMMIT" ]]; then
  git -C diffusers fetch --depth 1 origin "$DIFFUSERS_COMMIT"
  git -C diffusers checkout "$DIFFUSERS_COMMIT"
fi
git -C diffusers rev-parse HEAD | tee "$OUTDIR/diffusers-commit.txt"

rm -rf "$HOME/mc-bench/venv"
uv venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"

CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d ' ')
MAJOR=${CAP%%.*}
if [[ "${MAJOR:-0}" -ge 12 ]]; then
  TORCH_INDEX=https://download.pytorch.org/whl/cu128
else
  TORCH_INDEX=https://download.pytorch.org/whl/cu126
fi
log "torch index $TORCH_INDEX compute_cap=$CAP"
uv pip install 'torch==2.11.0' torchvision --index-url "$TORCH_INDEX"
uv pip install -e "$HOME/mc-bench/diffusers"
uv pip install 'transformers>=4.57.1' accelerate safetensors pillow sentencepiece protobuf

python3 - <<'PY'
import json, os, statistics, subprocess, threading, time
from pathlib import Path

import torch
from diffusers import QwenImage21Pipeline

out = Path(os.environ["OUTDIR"])
model_id = os.environ["MODEL"]
steps = int(os.environ.get("STEPS", "40"))
resolutions = []
for part in os.environ.get("RESOLUTIONS", "1024x1024").split(","):
    w, h = part.lower().split("x")
    resolutions.append((int(w), int(h)))

prompt = (
    "A ceramic espresso cup on a sunlit oak table, soft morning light, "
    "shallow depth of field, product photography, no text, no watermark, no logo"
)

def versions():
    import diffusers
    import transformers
    return {
        "torch": torch.__version__,
        "diffusers": diffusers.__version__,
        "transformers": transformers.__version__,
        "diffusers_commit": (out / "diffusers-commit.txt").read_text().strip(),
        "cuda": torch.version.cuda,
        "gpu": torch.cuda.get_device_name(0),
    }

samples = []
stop = threading.Event()
snap_once = {"done": False}

def poll():
    while not stop.is_set():
        try:
            line = subprocess.check_output(
                [
                    "nvidia-smi",
                    "--query-gpu=memory.used,memory.total,utilization.gpu",
                    "--format=csv,noheader,nounits",
                ],
                text=True,
            ).strip()
            samples.append(line)
            parts = [p.strip() for p in line.split(",")]
            util = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
            if util >= 50 and not snap_once["done"]:
                snap = subprocess.check_output(["nvidia-smi"], text=True)
                (out / "nvidia-smi-live.txt").write_text(snap)
                snap_once["done"] = True
        except Exception as exc:
            samples.append(f"error {exc}")
        stop.wait(2)

log_lines = []

def log(msg):
    print(msg, flush=True)
    log_lines.append(msg)

meta = versions()
(out / "engine.json").write_text(json.dumps(meta, indent=2))
log(f"engine {json.dumps(meta)}")

t0 = time.perf_counter()
pipe = QwenImage21Pipeline.from_pretrained(model_id, torch_dtype=torch.bfloat16)
pipe = pipe.to("cuda")
load_s = time.perf_counter() - t0
log(f"loaded in {load_s:.1f}s")

results = []
showcase_saved = False
for width, height in resolutions:
    tag = f"{width}x{height}"
    torch.cuda.empty_cache()
    torch.cuda.reset_peak_memory_stats()
    try:
        log(f"warmup {tag}")
        _ = pipe(
            prompt=prompt,
            width=width,
            height=height,
            num_inference_steps=2,
            generator=torch.Generator("cuda").manual_seed(0),
        ).images[0]
        torch.cuda.synchronize()
        runs = []
        samples.clear()
        stop.clear()
        watcher = threading.Thread(target=poll, daemon=True)
        watcher.start()
        # one full snapshot while the timed loop is in flight
        for i in range(5):
            gen = torch.Generator("cuda").manual_seed(1000 + i)
            torch.cuda.synchronize()
            t1 = time.perf_counter()
            image = pipe(
                prompt=prompt,
                width=width,
                height=height,
                num_inference_steps=steps,
                generator=gen,
            ).images[0]
            torch.cuda.synchronize()
            dt = time.perf_counter() - t1
            runs.append({"latency_s": dt, "steps": steps, "seed": 1000 + i})
            log(f"{tag} run {i} {dt:.3f}s")
            if not showcase_saved:
                image.save(out / "showcase.png")
                showcase_saved = True
            image.save(out / f"sample-{tag}-{i}.png")
        stop.set()
        watcher.join(timeout=5)
        used = []
        for line in samples:
            parts = [p.strip() for p in line.split(",")]
            if parts and parts[0].isdigit():
                used.append(int(parts[0]))
        lat = [r["latency_s"] for r in runs]
        peak_alloc = torch.cuda.max_memory_allocated() / (1024 ** 3)
        row = {
            "resolution": tag,
            "width": width,
            "height": height,
            "steps": steps,
            "runs": runs,
            "mean_latency_s": statistics.mean(lat),
            "median_latency_s": statistics.median(lat),
            "images_per_s": 1.0 / statistics.mean(lat),
            "peak_allocated_gib": peak_alloc,
            "nvidia_smi_max_mib": max(used) if used else None,
            "nvidia_smi_samples": samples[:],
        }
        results.append(row)
        log(f"{tag} mean {row['mean_latency_s']:.3f}s peak_alloc {peak_alloc:.2f} GiB smi_max {row['nvidia_smi_max_mib']}")
    except torch.OutOfMemoryError as exc:
        stop.set()
        torch.cuda.empty_cache()
        results.append({"resolution": tag, "error": "oom", "detail": str(exc)[:500]})
        log(f"{tag} OOM")

payload = {
    "model": model_id,
    "engine": "diffusers.QwenImage21Pipeline",
    "dtype": "bfloat16",
    "prompt": prompt,
    "load_s": load_s,
    "warmup_steps": 2,
    "timed_steps": steps,
    "versions": meta,
    "results": results,
}
(out / "bench.json").write_text(json.dumps(payload, indent=2))
ok = any("mean_latency_s" in r for r in results)
if not ok:
    (out / "FAIL").write_text("no successful resolution\n")
    raise SystemExit(1)
# live sample from the last successful resolution, plus the in-loop snapshot
live = out / "nvidia-smi-live.txt"
if live.exists():
    (out / "nvidia-smi.txt").write_text(live.read_text())
else:
    (out / "nvidia-smi.txt").write_text(subprocess.check_output(["nvidia-smi"], text=True))
(out / "FAIL").unlink(missing_ok=True)
(out / "DONE").write_text("ok\n")
log("DONE")
PY
log DONE
