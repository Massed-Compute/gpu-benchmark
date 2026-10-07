#!/usr/bin/env bash
# autotrust/JEV-27B-VL bench on one GPU.
# System 1: POST /v1/decide (thinking off, strategy single). Headline is p50 latency and decisions/s.
#   Single-stream: 20 warmup + 200 timed, text then image. Text state strings differ.
#   Image requests reuse one PNG. The multimodal processor cache stays at the vLLM default (on).
#   Concurrent: 400 requests at client concurrency 8 (the server cap). decisions/s = completed / wall time.
# System 2: vllm bench serve, random 128 in / 128 out, c1 and c8.
# Prefix caching is off (the author's serve.sh turns it on); every timed request still has unique text.
# VLLM_USE_FLASHINFER_SAMPLER=0: the model's generation_config sets top_k/top_p, and the FlashInfer
# sampler JIT-builds a CUDA module at the first sampled request, which crashed the engine on these images.
# Public weights. If ~/.cache/huggingface/token exists, huggingface_hub reads that file itself.
# Env: SKU
set -euo pipefail
SKU=${SKU:?set SKU e.g. gpu_1x_a100}
REPO=${REPO:-autotrust/JEV-27B-VL}
REVISION=${REVISION:-f34b598d4ef4bcefd337bee8d8e7ddd3b7733ccc}
VLLM_VERSION=${VLLM_VERSION:-0.31.0}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/jev-27b-vl/${SKU}/bf16-vllm}
MODEL_DIR="$HOME/mc-bench/models/jev-27b-vl"
export REPO REVISION OUTDIR SKU MODEL_DIR
mkdir -p "$OUTDIR" "$HOME/mc-bench/models"
rm -f "$OUTDIR/DONE"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

for i in $(seq 1 10); do
  if sudo apt-get update -qq; then break; fi
  log "apt locked, retry $i"; sleep 15
done
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3.12-venv python3-pip curl jq

if [[ ! -x "$HOME/mc-bench/venv/bin/python" ]]; then
  python3 -m venv "$HOME/mc-bench/venv"
fi
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip
pip install -q "vllm==${VLLM_VERSION}"
pip install -q huggingface_hub pillow requests

if [[ ! -f "$MODEL_DIR/.revision" ]] || [[ "$(cat "$MODEL_DIR/.revision")" != "$REVISION" ]]; then
  log "snapshot $REPO@$REVISION"
  case "$MODEL_DIR" in
    "$HOME/mc-bench/models/"*) ;;
    *) log "refusing to clear model dir outside ~/mc-bench/models"; exit 1 ;;
  esac
  rm -rf -- "$MODEL_DIR"
  mkdir -p "$MODEL_DIR"
  python - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(os.environ["REPO"], revision=os.environ["REVISION"], local_dir=os.environ["MODEL_DIR"])
PY
  echo "$REVISION" > "$MODEL_DIR/.revision"
fi

{
  echo "vllm $(vllm --version 2>/dev/null | tail -1)"
  python - <<'PY'
import torch, transformers
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
print("transformers", transformers.__version__)
print("gpu", torch.cuda.get_device_name(0))
PY
  echo "revision $REVISION"
} | tee "$OUTDIR/versions.txt"

find "$MODEL_DIR" -name '*.safetensors' -printf '%s\n' | awk '{s+=$1} END {printf "safetensors_bytes %d\n", s}' \
  | tee -a "$OUTDIR/versions.txt"

log "serve"
VLLM_USE_FLASHINFER_SAMPLER=0 python "$MODEL_DIR/serve_decide.py" --model "$MODEL_DIR" --served-model-name "$REPO" \
  --enable-lora --max-lora-rank 32 --lora-modules jev-decision="$MODEL_DIR/adapter_vllm" \
  --logprobs-mode processed_logprobs --max-model-len 32768 --no-enable-prefix-caching \
  --limit-mm-per-prompt '{"image": 8}' --max-num-seqs 8 --trust-request-chat-template \
  --port 8000 > "$OUTDIR/serve.log" 2>&1 &
SERVE_PID=$!
SMI_PID=
trap 'kill "$SERVE_PID" 2>/dev/null || true; if [[ -n ${SMI_PID:-} ]]; then kill "$SMI_PID" 2>/dev/null || true; fi' EXIT

for i in $(seq 1 180); do
  if curl -sf localhost:8000/v1/models >/dev/null; then break; fi
  if ! kill -0 "$SERVE_PID" 2>/dev/null; then log "server exited"; tail -50 "$OUTDIR/serve.log"; exit 1; fi
  sleep 10
done
curl -sf localhost:8000/v1/models >/dev/null || { log "server not ready"; tail -50 "$OUTDIR/serve.log"; exit 1; }
log "ready"

nvidia-smi > "$OUTDIR/nvidia-smi.txt"
nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,memory.total --format=csv -lms 2000 \
  >> "$OUTDIR/nvidia-smi.txt" &
SMI_PID=$!

python - <<'PY'
import base64, io, json, os, statistics, threading, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests
from PIL import Image, ImageDraw

out = Path(os.environ["OUTDIR"])
URL = "http://localhost:8000/v1/decide"
_tls = threading.local()

def session():
    s = getattr(_tls, "session", None)
    if s is None:
        s = requests.Session()
        _tls.session = s
    return s

img = Image.new("RGB", (448, 448), (235, 235, 235))
d = ImageDraw.Draw(img)
d.rectangle((60, 260, 160, 360), fill=(200, 30, 30))
d.rectangle((300, 80, 380, 160), fill=(30, 60, 200))
buf = io.BytesIO()
img.save(buf, format="PNG")
IMAGE = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

def text_req(i):
    return {"kind": "choice", "thinking": "off", "strategy": "single",
            "state": f"Ticket {i}: customer says the card was charged twice for one order.",
            "question": "Which team should handle this?",
            "options": ["billing", "shipping", "tech support"]}

def image_req(i):
    return {"kind": "noul", "thinking": "off", "strategy": "single",
            "state": [f"Camera frame {i}.", {"image": IMAGE}],
            "question": "Is the red cube left of the blue cube?"}

def call(body):
    t0 = time.perf_counter()
    r = session().post(URL, json=body, timeout=300)
    dt = time.perf_counter() - t0
    r.raise_for_status()
    j = r.json()
    if "probabilities" not in j:
        raise RuntimeError(f"bad response: {j}")
    return dt * 1000.0, j

def pct(xs, q):
    xs = sorted(xs)
    k = (len(xs) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)

results = {"repo": os.environ["REPO"], "revision": os.environ["REVISION"], "sku": os.environ["SKU"]}
for name, make in (("text", text_req), ("image", image_req)):
    for i in range(20):
        call(make(-1 - i))
    lat, sample = [], None
    t_all = time.perf_counter()
    for i in range(200):
        ms, j = call(make(i))
        lat.append(ms)
        sample = sample or j
    wall = time.perf_counter() - t_all
    single = {"n": 200, "p50_ms": round(pct(lat, 0.5), 3), "p95_ms": round(pct(lat, 0.95), 3),
              "mean_ms": round(statistics.mean(lat), 3), "wall_s": round(wall, 3),
              "decisions_per_s": round(200 / wall, 3), "latencies_ms": [round(x, 3) for x in lat]}
    n = 400
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(lambda i: call(make(10_000 + i)), range(16)))
        t0 = time.perf_counter()
        conc_lat = [ms for ms, _ in ex.map(lambda i: call(make(20_000 + i)), range(n))]
        wall_c = time.perf_counter() - t0
    conc = {"n": n, "concurrency": 8, "wall_s": round(wall_c, 3), "decisions_per_s": round(n / wall_c, 3),
            "p50_ms": round(pct(conc_lat, 0.5), 3), "p95_ms": round(pct(conc_lat, 0.95), 3)}
    results[name] = {"single": single, "c8": conc, "sample_response": sample}
    print(name, json.dumps({"single_p50_ms": single["p50_ms"], "single_dps": single["decisions_per_s"],
                            "c8_dps": conc["decisions_per_s"]}))

(out / "decide-bench.json").write_text(json.dumps(results, indent=2))
PY

for c in 1 8; do
  n=$(( c == 1 ? 10 : 40 ))
  log "system2 c$c"
  vllm bench serve --backend openai --base-url http://localhost:8000 --model "$REPO" --tokenizer "$MODEL_DIR" \
    --dataset-name random --random-input-len 128 --random-output-len 128 --ignore-eos \
    --num-prompts "$n" --max-concurrency "$c" \
    --save-result --result-dir "$OUTDIR" --result-filename "vllm-c$c.json" > "$OUTDIR/vllm-c$c.txt" 2>&1
done

kill "$SMI_PID" 2>/dev/null || true
for f in decide-bench.json vllm-c1.json vllm-c8.json nvidia-smi.txt versions.txt; do
  [[ -s "$OUTDIR/$f" ]] || { log "missing $f"; exit 1; }
done
for c in 1 8; do
  jq -e '.completed > 0 and .failed == 0' "$OUTDIR/vllm-c$c.json" >/dev/null \
    || { log "system2 c$c had failed requests"; exit 1; }
done
touch "$OUTDIR/DONE"
log "done"
