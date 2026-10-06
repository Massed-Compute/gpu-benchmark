#!/usr/bin/env bash
# Cloudflare/clef decision-model bench.
# Headline: p50 systemone latency (ms) and decisions/s. Not token throughput.
# One systemone() call is one decision (three typed questions per forward).
# Workloads: text state, then the same questions with one generated image.
# A public snapshot. If ~/.cache/huggingface/token exists, huggingface_hub reads that file itself.
# Env: SKU
set -euo pipefail
SKU=${SKU:?set SKU e.g. gpu_1x_a6000}
REPO=${REPO:-Cloudflare/clef}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/clef/${SKU}/bf16-systemone}
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/mc-bench/venv"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  python3.12-venv python3-pip curl git jq || true
if [[ ! -x "$HOME/mc-bench/venv/bin/python" ]]; then
  python3 -m venv "$HOME/mc-bench/venv"
fi
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip
pip install -q 'transformers==5.10.2' accelerate safetensors huggingface_hub pillow
pip install -q torch==2.14.1 torchvision --index-url https://download.pytorch.org/whl/cu130

MODEL_DIR="$HOME/mc-bench/models/clef"
if [[ ! -f "$MODEL_DIR/joint_head.safetensors" ]]; then
  log "snapshot $REPO"
  python - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(
    os.environ.get("REPO", "Cloudflare/clef"),
    local_dir=os.path.expanduser("~/mc-bench/models/clef"),
)
print("ok")
PY
fi
export REPO OUTDIR SKU MODEL_DIR

python3 - <<'PY' | tee "$OUTDIR/torch-version.txt"
import torch, transformers
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
print("gpu", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none")
print("transformers", transformers.__version__)
PY

log "load + time systemone"
python - <<'PY'
import copy, json, os, statistics, subprocess, time
from pathlib import Path

import torch
from PIL import Image, ImageDraw

model_dir = os.path.expanduser("~/mc-bench/models/clef")
import sys
sys.path.insert(0, model_dir)
from joint_schema_model import load_release_model, systemone

from huggingface_hub import HfApi

sku = os.environ["SKU"]
outdir = Path(os.environ["OUTDIR"])
repo = os.environ.get("REPO", "Cloudflare/clef")
sha = HfApi().model_info(repo).sha

log_path = outdir / "nvidia-smi.txt"
smi_csv = "timestamp,name,memory.used,memory.total,utilization.gpu"

def sample_smi(tag):
    proc = subprocess.run(
        ["nvidia-smi", f"--query-gpu={smi_csv}", "--format=csv"],
        check=False, capture_output=True, text=True,
    )
    with log_path.open("a") as fh:
        fh.write(f"=== {tag} ===\n")
        fh.write(proc.stdout)
        if proc.stderr:
            fh.write(proc.stderr)

questions = {
    "department": {
        "type": "choice",
        "instructions": "Which team should handle the message?",
        "criteria": {"billing": "Payments or invoices", "technical": "Bugs or outages"},
    },
    "urgency": {"type": "score", "criteria": ["Can wait", "This week", "Today"]},
    "outage": {"type": "noul", "instructions": "Is a service down?"},
}
text_request = {
    "model": "clef",
    "state": "Our checkout started returning errors and orders are blocked.",
    "questions": questions,
}

image = Image.new("RGB", (512, 512), (236, 236, 236))
draw = ImageDraw.Draw(image)
draw.rectangle((40, 40, 470, 470), outline=(20, 20, 20), width=4)
draw.rectangle((80, 180, 430, 280), fill=(30, 30, 30))
image_request = {
    "model": "clef",
    "state": "Our checkout started returning errors and orders are blocked.",
    "images": [image],
    "questions": questions,
}

print("loading", flush=True)
model, processor = load_release_model(model_dir, device="cuda", dtype=torch.bfloat16)
torch.cuda.synchronize()
sample_smi("after-load")
allocated_after_load_gib = round(torch.cuda.memory_allocated() / (1024 ** 3), 3)
print("allocated_after_load_gib", allocated_after_load_gib, flush=True)

def time_calls(make_request, label, n_warmup=20, n_timed=200):
    smoke = None
    for i in range(n_warmup):
        resp = systemone(model, processor, make_request())
        if i == 0:
            smoke = resp.get("answers")
        torch.cuda.synchronize()
    torch.cuda.reset_peak_memory_stats()
    sample_smi(f"{label}-live-start")
    times = []
    for i in range(n_timed):
        torch.cuda.synchronize()
        t0 = time.perf_counter()
        systemone(model, processor, make_request())
        torch.cuda.synchronize()
        times.append((time.perf_counter() - t0) * 1000.0)
        if i == n_timed // 2:
            sample_smi(f"{label}-live-mid")
    times.sort()
    p50 = statistics.median(times)
    p95 = times[int(0.95 * (n_timed - 1))]
    peak_mib = torch.cuda.max_memory_allocated() / (1024 * 1024)
    sample_smi(f"{label}-live-end")
    return {
        "label": label,
        "n_warmup": n_warmup,
        "n_timed": n_timed,
        "questions_per_call": 3,
        "latency_ms_p50": round(p50, 3),
        "latency_ms_p95": round(p95, 3),
        "latency_ms_min": round(times[0], 3),
        "latency_ms_max": round(times[-1], 3),
        "decisions_per_s": round(1000.0 / p50, 3),
        "peak_allocated_mib": round(peak_mib, 1),
        "peak_allocated_gib": round(peak_mib / 1024.0, 3),
        "smoke_answers": smoke,
    }

payload = {
    "model": repo,
    "revision": sha,
    "sku": sku,
    "dtype": "bfloat16",
    "harness": "systemone single-stream, 20 warmup + 200 timed, CUDA sync both sides",
    "allocated_after_load_gib": allocated_after_load_gib,
    "gpu": torch.cuda.get_device_name(0),
    "torch": torch.__version__,
    "transformers": __import__("transformers").__version__,
    "text": time_calls(lambda: copy.deepcopy(text_request), "text"),
    "image": time_calls(lambda: dict(copy.deepcopy(image_request), images=[image.copy()]), "image"),
}
out = outdir / "clef-bench.json"
out.write_text(json.dumps(payload, indent=2) + "\n")
print(json.dumps({
    "text_p50_ms": payload["text"]["latency_ms_p50"],
    "text_decisions_per_s": payload["text"]["decisions_per_s"],
    "image_p50_ms": payload["image"]["latency_ms_p50"],
    "image_decisions_per_s": payload["image"]["decisions_per_s"],
    "peak_gib_image": payload["image"]["peak_allocated_gib"],
    "revision": sha,
}, indent=2))
PY

test -s "$OUTDIR/clef-bench.json"
test -s "$OUTDIR/nvidia-smi.txt"
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
