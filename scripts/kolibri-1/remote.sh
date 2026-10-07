#!/usr/bin/env bash
# Aleph-Alpha/Kolibri-1 FP8 bench on one GPU.
# Weights are float8_e4m3fn. Headline is sustained output token throughput from
# vllm bench serve (random 128 in / 128 out, ignore-eos, prefix caching off).
# The clock is client wall time against a long-lived server, including HTTP.
# c1, c8, and c32 share that server. Prompts are the vLLM random dataset.
# Env: SKU. Optional MAX_LEN (default 8192; one retry at 4096 is a separate run).
set -euo pipefail
SKU=${SKU:?set SKU}
REPO=${REPO:-Aleph-Alpha/Kolibri-1}
REVISION=${REVISION:-35bc4d3be745502227a67247de77d70e691614ee}
MAX_LEN=${MAX_LEN:-8192}
TP=${TP:-1}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/kolibri-1/${SKU}/fp8-vllm}
MODEL_DIR="$HOME/mc-bench/models/kolibri-1"
export REPO REVISION OUTDIR SKU MODEL_DIR MAX_LEN
mkdir -p "$OUTDIR" "$HOME/mc-bench/models"
rm -f "$OUTDIR/DONE"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if ! dpkg -s python3.12-venv >/dev/null 2>&1; then
  for i in $(seq 1 20); do
    if sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3.12-venv python3-pip curl jq; then
      break
    fi
    log "apt locked, retry $i"
    sleep 15
    if [[ "$i" == 20 ]]; then
      log "apt failed"
      exit 1
    fi
  done
fi

if [[ ! -x "$HOME/mc-bench/venv/bin/python" ]]; then
  python3 -m venv "$HOME/mc-bench/venv"
fi
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip
pip install -q 'aleph-alpha-inference>=1' huggingface_hub

if [[ ! -f "$MODEL_DIR/.revision" ]] || [[ "$(cat "$MODEL_DIR/.revision")" != "$REVISION" ]]; then
  log "snapshot $REPO@$REVISION"
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
import importlib.metadata as m
import torch
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
print("gpu", torch.cuda.get_device_name(0), "count", torch.cuda.device_count())
print("aleph-alpha-inference", m.version("aleph-alpha-inference"))
PY
  echo "revision $REVISION"
  echo "max_model_len $MAX_LEN"
  echo "tensor_parallel $TP"
} | tee "$OUTDIR/versions.txt"

find "$MODEL_DIR" -name '*.safetensors' -printf '%s\n' | awk '{s+=$1} END {printf "safetensors_bytes %d\n", s}' \
  | tee -a "$OUTDIR/versions.txt"

start_serve() {
  log "serve max_model_len=$MAX_LEN tp=$TP"
  # FlashInfer's sampler JIT needs nvcc, which this image does not ship.
  # Blackwell has no FlashAttention candidate, and its FlashInfer XQA kernel
  # is missing, so it uses Triton with fp8 KV. A100 (SM80) cannot store fp8
  # KV on Triton (needs SM89) or FlashAttention (fp8 KV needs FA3 on SM90 or
  # FA4 on SM100). FlashInfer attention JIT needs nvcc, which this image does
  # not ship. A100 therefore uses Triton with bfloat16 KV.
  if [[ "${SKU}" == *a100* ]]; then
    ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
    KV_DTYPE="${KV_DTYPE:-bfloat16}"
  fi
  ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
  KV_DTYPE="${KV_DTYPE:-fp8}"
  export VLLM_USE_FLASHINFER_SAMPLER=0
  export VLLM_ATTENTION_BACKEND="$ATTN_BACKEND"
  mkdir -p "$HOME/.config/vllm"
  echo "attention_backend $ATTN_BACKEND" | tee -a "$OUTDIR/versions.txt"
  echo "kv_cache_dtype $KV_DTYPE" | tee -a "$OUTDIR/versions.txt"
  vllm serve "$MODEL_DIR" \
    --served-model-name "$REPO" \
    --attention-backend "$ATTN_BACKEND" \
    --tensor-parallel-size "$TP" \
    --max-model-len "$MAX_LEN" \
    --gpu-memory-utilization 0.92 \
    --max-num-batched-tokens 16384 \
    --kv-cache-dtype "$KV_DTYPE" \
    --no-enable-prefix-caching \
    --port 8000 > "$OUTDIR/serve.log" 2>&1 &
  SERVE_PID=$!
}

wait_serve() {
  local i
  for i in $(seq 1 240); do
    if curl -sf localhost:8000/v1/models >/dev/null; then return 0; fi
    if ! kill -0 "$SERVE_PID" 2>/dev/null; then return 1; fi
    sleep 10
  done
  return 1
}

start_serve
trap 'kill $SERVE_PID 2>/dev/null || true; kill ${SMI_PID:-0} 2>/dev/null || true' EXIT
if ! wait_serve; then
  log "server failed at max_model_len=$MAX_LEN; retry 4096"
  tail -40 "$OUTDIR/serve.log" || true
  kill "$SERVE_PID" 2>/dev/null || true
  wait "$SERVE_PID" 2>/dev/null || true
  MAX_LEN=4096
  echo "max_model_len_retry $MAX_LEN" | tee -a "$OUTDIR/versions.txt"
  mv "$OUTDIR/serve.log" "$OUTDIR/serve-8192.log" || true
  start_serve
  if ! wait_serve; then
    log "server exited"
    tail -80 "$OUTDIR/serve.log"
    exit 1
  fi
fi
log "ready"

nvidia-smi > "$OUTDIR/nvidia-smi.txt"
nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,memory.total --format=csv -lms 5000 \
  >> "$OUTDIR/nvidia-smi.txt" &
SMI_PID=$!

bench_one() {
  local conc="$1"
  local prompts=$(( conc * 5 ))
  log "bench c${conc} prompts=${prompts}"
  vllm bench serve \
    --base-url "http://127.0.0.1:8000" \
    --backend openai \
    --endpoint /v1/completions \
    --model "$REPO" \
    --dataset-name random \
    --random-input-len 128 \
    --random-output-len 128 \
    --num-prompts "$prompts" \
    --max-concurrency "$conc" \
    --ignore-eos \
    --request-rate inf \
    --save-result \
    --result-dir "$OUTDIR" \
    --result-filename "vllm-c${conc}.json"
}

bench_one 1
bench_one 8
bench_one 32

python - <<'PY'
import json, os
from pathlib import Path
out = Path(os.environ["OUTDIR"])
ok = True
for conc in (1, 8, 32):
    p = out / f"vllm-c{conc}.json"
    if not p.exists() or p.stat().st_size < 50:
        print("missing", p.name)
        ok = False
        continue
    data = json.loads(p.read_text())
    thr = data.get("output_throughput")
    print(f"c{conc} output_throughput {thr}")
    if not thr:
        ok = False
if not ok:
    raise SystemExit(1)
PY

echo ok > "$OUTDIR/DONE"
log "done"
kill "$SMI_PID" 2>/dev/null || true
kill "$SERVE_PID" 2>/dev/null || true
trap - EXIT
wait "$SERVE_PID" 2>/dev/null || true
