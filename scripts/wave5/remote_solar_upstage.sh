#!/usr/bin/env bash
# Solar Open2 via Upstage Docker image (working config from live Wave 5 run).
# Env: HF_TOKEN OUTDIR MODEL TP
set -euo pipefail
MODEL=${MODEL:-nota-ai/Solar-Open2-250B-Nota-NVFP4}
TP=${TP:-2}
HF_TOKEN=${HF_TOKEN:-$(cat "$HOME/.cache/huggingface/token" 2>/dev/null || true)}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/solar-open2-250b-a15b}
PORT=${PORT:-8000}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" HF_HUB_ENABLE_HF_TRANSFER=1
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq || true
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates python3-venv python3-pip || true

USE_DOCKER=0
if command -v docker >/dev/null 2>&1; then
  USE_DOCKER=1
fi

# Working flags from published bench: cutlass MoE, TP only (no EP), eager, no custom AR.
SERVE_ARGS=(
  "$MODEL"
  --served-model-name solar-open2-250b
  --tensor-parallel-size "$TP"
  --moe-backend cutlass
  --max-model-len 4096
  --enforce-eager
  --disable-custom-all-reduce
  --default-chat-template-kwargs '{"think_render_option":"preserved"}'
  --reasoning-parser solar_open2
  --tool-call-parser solar_open2
  --enable-auto-tool-choice
  --host 0.0.0.0 --port 8000
)

if [[ "$USE_DOCKER" -eq 1 ]]; then
  log "pull upstage/vllm-solar-open2"
  sudo docker pull upstage/vllm-solar-open2
  sudo docker rm -f solar-open2 2>/dev/null || true
  log "start docker serve $MODEL tp=$TP moe=cutlass (no EP)"
  sudo docker run -d --name solar-open2 --gpus all --ipc=host \
    -p "$PORT:8000" \
    -e HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" \
    -e HF_TOKEN="$HF_TOKEN" \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    upstage/vllm-solar-open2 \
    "${SERVE_ARGS[@]}"
else
  log "no docker — install Upstage vLLM fork via uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh || true
  export PATH="$HOME/.local/bin:$PATH"
  python3 -m venv "$HOME/mc-bench/venv-solar"
  # shellcheck disable=SC1091
  . "$HOME/mc-bench/venv-solar/bin/activate"
  pip install -q -U pip wheel uv
  export VLLM_PRECOMPILED_WHEEL_LOCATION="https://github.com/vllm-project/vllm/releases/download/v0.22.0/vllm-0.22.0%2Bcu129-cp38-abi3-manylinux_2_28_x86_64.whl"
  export VLLM_USE_PRECOMPILED=1
  uv pip install --reinstall-package vllm --torch-backend=cu129 \
    "git+https://github.com/UpstageAI/vllm.git@v0.22.0-solar-open2"
  pkill -f "vllm serve" || true
  sleep 2
  # port arg for bare vllm uses $PORT
  nohup vllm serve "$MODEL" \
    --served-model-name solar-open2-250b \
    --tensor-parallel-size "$TP" \
    --moe-backend cutlass \
    --max-model-len 4096 \
    --enforce-eager \
    --disable-custom-all-reduce \
    --default-chat-template-kwargs '{"think_render_option":"preserved"}' \
    --reasoning-parser solar_open2 \
    --tool-call-parser solar_open2 \
    --enable-auto-tool-choice \
    --host 0.0.0.0 --port "$PORT" \
    >"$OUTDIR/vllm.log" 2>&1 &
  echo $! >"$OUTDIR/vllm.pid"
fi

python3 -m venv "$HOME/mc-bench/venv-bench"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv-bench/bin/activate"
pip install -q -U pip openai

log "wait for /v1/models"
for i in $(seq 1 240); do
  if curl -sf "http://127.0.0.1:$PORT/v1/models" >/dev/null; then
    log "ready after ~$((i*10))s"
    break
  fi
  if [[ "$USE_DOCKER" -eq 1 ]]; then
    sudo docker logs --tail 20 solar-open2 >>"$OUTDIR/vllm.log" 2>&1 || true
  fi
  if [[ $i -eq 240 ]]; then
    if [[ "$USE_DOCKER" -eq 1 ]]; then sudo docker logs solar-open2 2>&1 | tee "$OUTDIR/FAIL"; else tail -120 "$OUTDIR/vllm.log" | tee "$OUTDIR/FAIL"; fi
    exit 1
  fi
  sleep 10
done

for c in 1 8 32; do
  log "bench c=$c"
  C="$c" OUTDIR="$OUTDIR" MODEL="$MODEL" TP="$TP" PORT="$PORT" python3 - <<'PY'
import json, os, time, statistics
from concurrent.futures import ThreadPoolExecutor, as_completed
from openai import OpenAI
c = int(os.environ["C"])
port = os.environ["PORT"]
client = OpenAI(base_url=f"http://127.0.0.1:{port}/v1", api_key="EMPTY")
prompt = "Explain GPU inference throughput in two sentences."
out = os.environ["OUTDIR"]

def one():
    t0 = time.perf_counter()
    r = client.chat.completions.create(
        model="solar-open2-250b",
        messages=[{"role":"user","content":prompt}],
        max_tokens=128,
        temperature=0,
    )
    dt = time.perf_counter() - t0
    usage = r.usage
    n = (usage.completion_tokens if usage else 128) or 128
    return {"latency_s": dt, "new_tokens": n, "tok_s": n/dt if dt else 0}

one()
wall0 = time.perf_counter()
with ThreadPoolExecutor(max_workers=c) as ex:
    futs = [ex.submit(one) for _ in range(max(c * 2, 4))]
    runs = [f.result() for f in as_completed(futs)]
wall = time.perf_counter() - wall0
mean_tok = statistics.mean(r["tok_s"] for r in runs)
agg = sum(r["new_tokens"] for r in runs) / wall if wall else 0
mean_lat_ms = statistics.mean(r["latency_s"] for r in runs) * 1000
doc = {
    "engine": "vllm-upstage-solar-open2-docker",
    "model": os.environ["MODEL"],
    "tp": int(os.environ["TP"]),
    "max_concurrency": c,
    "output_throughput": agg,
    "single_stream_tok_s_mean": mean_tok,
    "mean_e2e_latency_ms": mean_lat_ms,
    "ttft_measured": False,
    "note": "Custom ThreadPool chat harness (not vllm bench serve). TTFT not measured.",
    "runs": runs,
}
open(f"{out}/vllm-c{c}.json", "w").write(json.dumps(doc, indent=2) + "\n")
print(json.dumps({k: doc[k] for k in doc if k != "runs"}, indent=2))
PY
done

nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
echo "$MODEL" >"$OUTDIR/model.txt"
# Match committed provenance format from the published Wave 5 run.
echo "upstage/vllm-solar-open2 docker; moe_backend=cutlass; tp=$TP; max_model_len=4096" >"$OUTDIR/engine.txt"
if [[ "$USE_DOCKER" -eq 1 ]]; then sudo docker rm -f solar-open2 || true; else pkill -f "vllm serve" || true; fi
rm -f "$OUTDIR/FAIL"
echo DONE >"$OUTDIR/DONE"
log DONE
