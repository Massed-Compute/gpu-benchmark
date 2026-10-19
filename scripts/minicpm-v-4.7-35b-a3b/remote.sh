#!/usr/bin/env bash
# openbmb/MiniCPM-V-4.7-35B-A3B bench.
# Weights are BF16. Architecture MiniCPMV4_7ForConditionalGeneration is in
# vLLM 0.32.0, and the repo has no modeling .py, so trust-remote-code is off.
# The server allows one image per prompt so the multimodal loader stays in the
# path the page credits. The timed requests are text completions.
# Headline is sustained output token throughput from vllm bench serve
# (random 128 in / 128 out, ignore-eos, prefix caching off).
# The clock is client wall time against a long-lived server, including HTTP.
# c1, c8, and c32 share that server. Prompts are the vLLM random dataset.
# Env: SKU. Tensor parallel stays 1 (one GPU per VM).
# Optional MAX_LEN (default 8192). A failed server start fails the run.
set -euo pipefail
SKU=${SKU:?set SKU}
REPO=${REPO:-openbmb/MiniCPM-V-4.7-35B-A3B}
REVISION=${REVISION:-896c2d454672476a7b45dcc5e3f0c700a0218577}
VLLM_VERSION=${VLLM_VERSION:-0.32.0}
MAX_LEN=${MAX_LEN:-8192}
TP=${TP:-1}
QUANT=bf16
VARIANT=bf16-vllm
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/minicpm-v-4.7-35b-a3b/${SKU}/${VARIANT}}
MODEL_DIR="$HOME/mc-bench/models/minicpm-v-4.7-35b-a3b"
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
pip install -q "vllm==${VLLM_VERSION}" huggingface_hub

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
import torch
print("torch", torch.__version__)
print("cuda", torch.version.cuda)
print("gpu", torch.cuda.get_device_name(0), "count", torch.cuda.device_count())
PY
  echo "revision $REVISION"
  echo "max_model_len $MAX_LEN"
  echo "tensor_parallel $TP"
  echo "quantization $QUANT"
} | tee "$OUTDIR/versions.txt"

find "$MODEL_DIR" -name '*.safetensors' -printf '%s\n' | awk '{s+=$1} END {printf "safetensors_bytes %d\n", s}' \
  | tee -a "$OUTDIR/versions.txt"

start_serve() {
  log "serve max_model_len=$MAX_LEN tp=$TP quant=$QUANT"
  # FlashInfer's sampler and prefill JIT need nvcc, which this image does not ship.
  # Leaving the backend unset on L40S picked FlashInfer and died in flashinfer.jit.
  # Blackwell has no FlashAttention candidate and its FlashInfer XQA kernel is
  # missing, so it is forced to Triton with fp8 KV. A100 (SM80) cannot store
  # fp8 KV on Triton (needs SM89) or FlashAttention (fp8 KV needs FA3 on SM90
  # or FA4 on SM100), and FlashInfer attention JIT needs nvcc, so A100 is
  # Triton with bfloat16 KV. H100 is SM90: force FlashAttention so fp8 KV uses
  # FA3 and the server does not JIT FlashInfer.
  local attn_args=()
  case "$SKU" in
    *a100*|*A100*)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
      KV_DTYPE="${KV_DTYPE:-bfloat16}"
      ;;
    *pro_6000_blackwell*)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
      KV_DTYPE="${KV_DTYPE:-fp8}"
      ;;
    *h100*|*H100*)
      ATTN_BACKEND="${ATTN_BACKEND:-FLASH_ATTN}"
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
  if [[ -e "$HOME/.config" && ! -w "$HOME/.config" ]] || [[ -e "$HOME/.config/vllm" && ! -w "$HOME/.config/vllm" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.config"
  fi
  mkdir -p "$HOME/.config/vllm"
  vllm serve "$MODEL_DIR" \
    --served-model-name "$REPO" \
    "${attn_args[@]}" \
    --tensor-parallel-size "$TP" \
    --max-model-len "$MAX_LEN" \
    --gpu-memory-utilization 0.92 \
    --max-num-batched-tokens 16384 \
    --kv-cache-dtype "$KV_DTYPE" \
    --limit-mm-per-prompt '{"image": 1}' \
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
