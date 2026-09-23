#!/usr/bin/env bash
# convaiinnovations/laya (English ModernBERT-large RLAgent) GPU latency bench.
# Headline: p50 system_one latency (ms) and decisions/s. Not token throughput.
# Env: SKU HF_TOKEN(optional) OUTDIR
set -euo pipefail
SKU=${SKU:?set SKU e.g. gpu_1x_l40s}
REPO=${REPO:-convaiinnovations/laya}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/laya/${SKU}/english-default}
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/mc-bench/venv"
export HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-}" HF_TOKEN="${HF_TOKEN:-}" REPO OUTDIR SKU

if [[ -z "${HUGGING_FACE_HUB_TOKEN:-}" && -f "$HOME/.cache/huggingface/token" ]]; then
  tok=$(tr -d '[:space:]' < "$HOME/.cache/huggingface/token")
  export HUGGING_FACE_HUB_TOKEN="$tok"
fi

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
pip install -q torch --index-url https://download.pytorch.org/whl/cu128
pip install -q transformers safetensors huggingface_hub numpy

MODEL_DIR="$HOME/mc-bench/models/laya"
if [[ ! -f "$MODEL_DIR/model.safetensors" ]]; then
  log "snapshot $REPO"
  python - <<'PY'
from huggingface_hub import snapshot_download
import os
snapshot_download(
    os.environ["REPO"],
    local_dir=os.path.expanduser("~/mc-bench/models/laya"),
    token=(os.environ.get("HF_TOKEN") or None),
)
print("ok")
PY
fi

python3 - <<'PY' | tee "$OUTDIR/torch-version.txt"
import torch, transformers
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
print("gpu", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none")
print("transformers", transformers.__version__)
PY

SMI_CSV='timestamp,name,memory.used,memory.total,utilization.gpu'
(
  for i in $(seq 1 180); do
    echo "=== sample $i $(date -u +%H:%M:%S) ==="
    nvidia-smi --query-gpu="$SMI_CSV" --format=csv
    sleep 2
  done
) > "$OUTDIR/nvidia-smi.txt" &
SMI_PID=$!
trap 'kill $SMI_PID 2>/dev/null || true' EXIT

log "run RLAgent system_one latency"
python - <<'PY'
import json, os, statistics, sys, time
from pathlib import Path

import torch

model_dir = str(Path.home() / "mc-bench/models/laya")
sys.path.insert(0, model_dir)
from rl_agent_api import RLAgent  # noqa: E402

outdir = Path(os.environ["OUTDIR"])
sku = os.environ["SKU"]
agent = RLAgent(model_dir, device="cuda")

state = {
    "from": "user@acme.com",
    "subject": "Duplicate charge on invoice #4411",
    "body": "Hi, we were billed twice for March. Please refund the duplicate today or we will cancel our plan.",
}
questions = {
    "department": {
        "type": "choice",
        "instructions": "Which department should handle this?",
        "criteria": ["billing", "support", "sales", "legal"],
    },
    "urgency": {
        "type": "score",
        "instructions": "How urgent is this?",
        "criteria": ["low", "medium", "high", "critical"],
    },
    "churn_threat": {
        "type": "noul",
        "instructions": "Does the user threaten to cancel or leave?",
    },
    "refund_requested": {
        "type": "noul",
        "instructions": "Does the user explicitly request a refund?",
    },
}

for _ in range(20):
    agent.system_one(state, questions)
torch.cuda.synchronize()
torch.cuda.reset_peak_memory_stats()

times_ms = []
last = None
n = 200
for _ in range(n):
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    last = agent.system_one(state, questions)
    torch.cuda.synchronize()
    times_ms.append((time.perf_counter() - t0) * 1000.0)

times_ms.sort()
p50 = statistics.median(times_ms)
p95 = times_ms[int(0.95 * (n - 1))]
mean = sum(times_ms) / n
peak_mib = torch.cuda.max_memory_allocated() / (1024 * 1024)
peak_gib = peak_mib / 1024.0
dec_s = 1000.0 / p50 if p50 else None
payload = {
    "sku": sku,
    "repo": os.environ.get("REPO"),
    "checkpoint": "english-default model.safetensors",
    "encoder": "answerdotai/ModernBERT-large (config in encoder/)",
    "harness": "RLAgent.system_one single-stream, 20 warmup + 200 timed, CUDA sync both sides",
    "n_warmup": 20,
    "n_timed": n,
    "latency_ms_p50": p50,
    "latency_ms_p95": p95,
    "latency_ms_mean": mean,
    "latency_ms_min": times_ms[0],
    "latency_ms_max": times_ms[-1],
    "decisions_per_s": dec_s,
    "peak_allocated_mib": peak_mib,
    "peak_allocated_gib": peak_gib,
    "gpu": torch.cuda.get_device_name(0),
    "torch": torch.__version__,
    "sample_answers": {
        k: {kk: vv for kk, vv in v.items() if kk in ("type", "choice", "score", "confidence", "noul")}
        for k, v in ((last or {}).get("answers") or {}).items()
        if isinstance(v, dict)
    },
}
(outdir / "laya-bench.json").write_text(json.dumps(payload, indent=2))
(outdir / "model.txt").write_text(
    f"sku={sku}\nrepo={os.environ.get('REPO')}\ncheckpoint=english-default\n"
    f"p50_ms={p50:.3f}\ndecisions_per_s={dec_s:.3f}\npeak_mib={peak_mib:.1f}\n"
)
print(json.dumps({k: payload[k] for k in ("latency_ms_p50", "decisions_per_s", "peak_allocated_gib", "gpu")}, indent=2))
PY

[[ -s "$OUTDIR/laya-bench.json" ]]
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
kill "$SMI_PID" 2>/dev/null || true
trap - EXIT
ls -la "$OUTDIR"
