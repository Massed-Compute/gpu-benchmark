#!/usr/bin/env bash
# Aleph-Alpha/Kolibri-1 FP8 bench.
# Weights are float8_e4m3fn. Headline is sustained output token throughput from
# vllm bench serve (random 128 in / 128 out, ignore-eos, prefix caching off).
# The clock is client wall time against a long-lived server, including HTTP.
# c1, c8, and c32 share that server. Prompts are the vLLM random dataset.
# Env: SKU. Tensor parallel comes from TP (A100 SKU GPU count, otherwise 1).
# Optional MAX_LEN (default 8192). A failed server start fails the run.
set -euo pipefail
SKU=${SKU:?set SKU}
SKU_LOWER=$(printf '%s' "$SKU" | tr '[:upper:]' '[:lower:]')
REPO=${REPO:-Aleph-Alpha/Kolibri-1}
REVISION=${REVISION:-35bc4d3be745502227a67247de77d70e691614ee}
MAX_LEN=${MAX_LEN:-8192}
# TP is the tensor-parallel size. Preserve caller overrides; infer A100 GPU count.
if [[ -z "${TP:-}" ]]; then
  if [[ "$SKU_LOWER" == *a100* && "$SKU_LOWER" =~ ^gpu_([1-9][0-9]*)x_ ]]; then
    TP=${BASH_REMATCH[1]}
  else
    TP=1
  fi
fi
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
pip install -q 'aleph-alpha-inference==1.0.0' huggingface_hub

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
  # gpu_1x_h200_nvl omits --attention-backend unless ATTN_BACKEND is set, so
  # vLLM auto-selects FlashAttention. Blackwell has no FlashAttention candidate
  # and its FlashInfer XQA kernel is missing, so it is forced to Triton with
  # fp8 KV. A100 (SM80) cannot store fp8 KV on Triton (needs SM89) or
  # FlashAttention (fp8 KV needs FA3 on SM90 or FA4 on SM100), and FlashInfer
  # attention JIT needs nvcc, so A100 is Triton with bfloat16 KV.
  local attn_args=()
  case "$SKU_LOWER" in
    *a100*)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
      KV_DTYPE="${KV_DTYPE:-bfloat16}"
      ;;
    *pro_6000_blackwell*)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
      KV_DTYPE="${KV_DTYPE:-fp8}"
      ;;
    *)
      KV_DTYPE="${KV_DTYPE:-fp8}"
      ;;
  esac
  if [[ -n "${ATTN_BACKEND:-}" ]]; then
    attn_args=(--attention-backend "$ATTN_BACKEND")
    echo "attention_backend $ATTN_BACKEND" | tee -a "$OUTDIR/versions.txt"
  else
    echo "attention_backend unset" | tee -a "$OUTDIR/versions.txt"
  fi
  echo "kv_cache_dtype $KV_DTYPE" | tee -a "$OUTDIR/versions.txt"
  export VLLM_USE_FLASHINFER_SAMPLER=0
  # Fix only vLLM's directory, without prompting or aborting an unattended bench.
  # The published captures continued despite an unwritable config directory.
  if ! mkdir -p "$HOME/.config/vllm" 2>/dev/null || [[ ! -w "$HOME/.config/vllm" ]]; then
    if [[ -d "$HOME/.config/vllm" ]] && sudo -n chown "$(id -u):$(id -g)" "$HOME/.config/vllm" && [[ -w "$HOME/.config/vllm" ]]; then
      log "fixed vLLM config directory ownership"
    else
      log "warning: vLLM config directory is not writable; continuing without changing ~/.config ownership"
    fi
  fi
  # An unset backend has no args; preserve that under nounset on older Bash too.
  vllm serve "$MODEL_DIR" \
    --served-model-name "$REPO" \
    ${attn_args[@]+"${attn_args[@]}"} \
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

cleanup() {
  if [[ -n "${SERVE_PID:-}" ]]; then
    kill "$SERVE_PID" 2>/dev/null || true
  fi
  if [[ -n "${SMI_PID:-}" ]]; then
    kill "$SMI_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
start_serve
if ! wait_serve; then
  log "server exited at max_model_len=$MAX_LEN"
  tail -80 "$OUTDIR/serve.log" || true
  exit 1
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
    print(f"c{conc} output_throughput {thr} completed {data.get('completed')} failed {data.get('failed')}")
    if not thr or data.get("failed") != 0 or data.get("completed") != conc * 5:
        ok = False
if not ok:
    raise SystemExit(1)
PY

echo ok > "$OUTDIR/DONE"
log "done"
cleanup
trap - EXIT
if [[ -n "${SERVE_PID:-}" ]]; then
  wait "$SERVE_PID" 2>/dev/null || true
fi
