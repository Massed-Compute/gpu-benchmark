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
SKU_LOWER=$(printf '%s' "$SKU" | tr '[:upper:]' '[:lower:]')
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
  # Decoder attention: Blackwell has no FlashAttention candidate and its
  # FlashInfer XQA kernel is missing, so the decoder is forced to Triton
  # with fp8 KV. The vision encoder can still select FLASH_ATTN on its own.
  # A100 (SM80) cannot store fp8 KV on Triton (needs SM89) or FlashAttention
  # (fp8 KV needs FA3 on SM90 or FA4 on SM100), and FlashInfer attention JIT
  # needs nvcc, so A100 is Triton with bfloat16 KV. A6000 is the same Ampere
  # constraint. L40, L40S, and 6000 Ada are SM89, so they get Triton with
  # fp8 KV. Hopper (H100, including NVL, and H200) is forced to FlashAttention
  # so fp8 KV uses FA3. Every other SKU is forced to Triton: an unset backend
  # auto-picked FlashInfer on L40S and died on the missing nvcc.
  local attn_args=()
  case "$SKU_LOWER" in
    *a100*|*a6000*)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
      KV_DTYPE="${KV_DTYPE:-bfloat16}"
      ;;
    *h100*|*h200*)
      ATTN_BACKEND="${ATTN_BACKEND:-FLASH_ATTN}"
      KV_DTYPE="${KV_DTYPE:-fp8}"
      ;;
    *l40*|*6000_ada*|*pro_6000_blackwell*)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
      KV_DTYPE="${KV_DTYPE:-fp8}"
      ;;
    *)
      ATTN_BACKEND="${ATTN_BACKEND:-TRITON_ATTN}"
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
  # Narrow, non-interactive. A password prompt would fail the run under set -e.
  if [[ -e "$HOME/.config/vllm" && ! -w "$HOME/.config/vllm" ]]; then
    sudo -n chown "$(id -u):$(id -g)" "$HOME/.config/vllm" || true
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
    if ! kill -0 "$SERVE_PID" 2>/dev/null; then return 1; fi
    # These runners target Linux. Require the new API process to own the
    # listener, even if an older server advertises exactly the same model.
    if python - "$SERVE_PID" "$REPO" <<'PY'
import json
import os
import sys
from pathlib import Path
from urllib.request import ProxyHandler, build_opener

def ready(pid, model):
    proc = Path("/proc")
    sockets = set()
    for fd in (proc / pid / "fd").iterdir():
        try:
            sockets.add(os.readlink(fd))
        except OSError:
            continue  # An unrelated descriptor may close while we inspect it.
    owns_port = False
    for protocol in ("tcp", "tcp6"):
        table = proc / "net" / protocol
        if not table.exists():
            continue
        for line in table.read_text().splitlines()[1:]:
            fields = line.split()
            if (fields[1].rsplit(":", 1)[1] == "1F40"
                    and fields[3] == "0A"
                    and "socket:[" + fields[9] + "]" in sockets):
                owns_port = True
    if not owns_port:
        return False
    opener = build_opener(ProxyHandler({}))
    with opener.open("http://127.0.0.1:8000/v1/models", timeout=3) as response:
        data = json.load(response)
    return any(item.get("id") == model for item in data.get("data", []))

try:
    is_ready = ready(sys.argv[1], sys.argv[2])
except (OSError, ValueError, KeyError, IndexError, TypeError, AttributeError):
    is_ready = False
raise SystemExit(0 if is_ready else 1)
PY
    then
      # The process can exit during the HTTP request. Never accept that result.
      if kill -0 "$SERVE_PID" 2>/dev/null; then return 0; fi
      return 1
    fi
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
