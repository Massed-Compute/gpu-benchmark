#!/usr/bin/env bash
# openai/gpt-oss-120b native MXFP4. One GPU. Prefix caching off.
# Headline is sustained output token throughput from vllm bench serve
# (random 128 in / 128 out, ignore-eos). c1, c8, and c32 share one server.
# The clock is client wall time against that server, including HTTP.
# Ampere (A100) cannot store fp8 KV on Triton, so KV is bfloat16.
# Env: SKU REVISION. Token file, if present, is ~/.cache/huggingface/token mode 600.
set -euo pipefail
SKU=${SKU:?set SKU}
REPO=${REPO:-openai/gpt-oss-120b}
REVISION=${REVISION:?set REVISION}
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:v0.32.0}
MAX_LEN=${MAX_LEN:-8192}
TP=${TP:-1}
VARIANT=mxfp4-1gpu
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/gpt-oss-120b/${SKU}/${VARIANT}}
LOGDIR=$HOME/mc-bench/logs/gpt-oss-120b
MODEL_DIR=${MODEL_DIR:-$HOME/mc-bench/models/gpt-oss-120b}
export REPO REVISION OUTDIR SKU
mkdir -p "$OUTDIR" "$MODEL_DIR" "$LOGDIR" "$HOME/.cache/huggingface"
rm -f "$OUTDIR/DONE" "$OUTDIR/FAIL" "$OUTDIR"/*fail.log
if [[ -f "$HOME/.cache/huggingface/token" ]]; then
  chmod 600 "$HOME/.cache/huggingface/token"
  mode=$(stat -c %a "$HOME/.cache/huggingface/token")
  if [[ "$mode" != "600" ]]; then
    echo "huggingface token mode is not 600" >&2
    exit 1
  fi
fi

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if ! command -v docker >/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io curl ca-certificates
  sudo systemctl enable --now docker
fi
if ! sudo docker info >/dev/null 2>&1; then
  sudo systemctl enable --now docker
fi
if ! sudo docker info 2>/dev/null | grep -qi nvidia; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
fi

log "pull $VLLM_IMAGE"
sudo docker pull "$VLLM_IMAGE"

if [[ ! -f "$MODEL_DIR/.revision" ]] || [[ "$(cat "$MODEL_DIR/.revision")" != "$REVISION" ]]; then
  log "snapshot $REPO@$REVISION"
  sudo docker run --rm --entrypoint python3 \
    -e REPO="$REPO" -e REVISION="$REVISION" \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    -v "$MODEL_DIR:/model" \
    "$VLLM_IMAGE" -c 'from huggingface_hub import snapshot_download; import os; snapshot_download(os.environ["REPO"], revision=os.environ["REVISION"], local_dir="/model", ignore_patterns=["original/**","metal/**"])'
  echo "$REVISION" > "$MODEL_DIR/.revision"
fi

{
  echo "image=$VLLM_IMAGE"
  echo "digests=$(sudo docker image inspect --format '{{json .RepoDigests}}' "$VLLM_IMAGE")"
  echo "revision=$REVISION"
  echo "sku=$SKU"
  echo "variant=$VARIANT"
  echo "tensor_parallel=$TP"
  echo "max_model_len=$MAX_LEN"
  echo "prefix_caching=off"
  echo "kv_cache_dtype=bfloat16"
  echo "attention_backend=TRITON_ATTN"
  echo "gpu_memory_utilization=0.92"
  echo "max_num_batched_tokens=16384"
  echo "quantization=mxfp4"
} | tee "$OUTDIR/engine.txt"
find "$MODEL_DIR" -name '*.safetensors' -printf '%s\n' | awk '{s+=$1} END {printf "safetensors_bytes %d\n", s}' | tee -a "$OUTDIR/engine.txt"

start_serve() {
  local len="$1"
  sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
  log "serve len=$len tp=$TP kv=bfloat16 prefix-cache off"
  sudo docker run -d --name vllm-bench --gpus all --ipc=host --shm-size 16g \
    -e VLLM_USE_FLASHINFER_SAMPLER=0 \
    -p 8000:8000 \
    -v "$MODEL_DIR:/model:ro" \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
    "$VLLM_IMAGE" \
    --model /model \
    --served-model-name "$REPO" \
    --trust-remote-code \
    --attention-backend TRITON_ATTN \
    --tensor-parallel-size "$TP" \
    --max-model-len "$len" \
    --gpu-memory-utilization 0.92 \
    --max-num-batched-tokens 16384 \
    --kv-cache-dtype bfloat16 \
    --no-enable-prefix-caching
}

wait_ready() {
  local i
  for i in $(seq 1 180); do
    if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then
      return 0
    fi
    if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
      return 1
    fi
    sleep 10
  done
  return 1
}

USED_LEN="$MAX_LEN"
start_serve "$USED_LEN"
if ! wait_ready; then
  sudo docker logs --tail 200 vllm-bench >"$LOGDIR/vllm-serve-8192.fail.log" 2>&1 || true
  log "8192 did not stay up; retry 4096 once"
  USED_LEN=4096
  start_serve "$USED_LEN"
  if ! wait_ready; then
    sudo docker logs --tail 300 vllm-bench >"$LOGDIR/vllm-serve.fail.log" 2>&1 || true
    rm -f "$OUTDIR"/*fail.log
    echo FAIL >"$OUTDIR/FAIL"
    exit 1
  fi
fi
echo "$USED_LEN" >"$OUTDIR/max-model-len.txt"
sed -i "s/^max_model_len=.*/max_model_len=${USED_LEN}/" "$OUTDIR/engine.txt"
sudo docker exec vllm-bench vllm --version >"$OUTDIR/vllm-version.txt" 2>&1 || true
log VLLM_READY

nvidia-smi >"$OUTDIR/nvidia-smi.txt"
(
  for _ in $(seq 1 240); do
    line=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null || true)
    util=${line%%,*}
    util=${util// /}
    if [[ "${util:-0}" =~ ^[0-9]+$ ]] && [[ "$util" -ge 20 ]]; then
      nvidia-smi >"$OUTDIR/nvidia-smi.txt.tmp" && mv "$OUTDIR/nvidia-smi.txt.tmp" "$OUTDIR/nvidia-smi.txt"
    fi
    sleep 2
  done
) >/dev/null 2>&1 &
SMI_PID=$!

bench_json_ok() {
  sudo docker exec -e BENCH_JSON="$1" vllm-bench python3 -c '
import json, os, sys
path = os.environ["BENCH_JSON"]
try:
    with open(path) as handle:
        data = json.load(handle)
except Exception:
    sys.exit(1)
sys.exit(0 if data.get("failed") == 0 else 1)
'
}

bench_one() {
  local conc="$1"
  local prompts=$(( conc * 5 ))
  local comp="/tmp/vllm-c${conc}.json"
  local chat="/tmp/vllm-c${conc}-chat.json"
  local comp_rc=0
  log "bench c${conc} prompts=${prompts}"
  sudo docker exec -e HF_HOME=/tmp/hfhome -e HF_HUB_CACHE=/tmp/hfhome/hub vllm-bench vllm bench serve \
    --base-url http://127.0.0.1:8000 \
    --backend openai \
    --endpoint /v1/completions \
    --model "$REPO" \
    --tokenizer /model \
    --trust-remote-code \
    --dataset-name random \
    --random-input-len 128 \
    --random-output-len 128 \
    --num-prompts "$prompts" \
    --max-concurrency "$conc" \
    --ignore-eos \
    --request-rate inf \
    --save-result \
    --result-dir /tmp \
    --result-filename "vllm-c${conc}.json" || comp_rc=$?
  if [[ "$comp_rc" -ne 0 ]] || ! bench_json_ok "$comp"; then
    sudo docker exec vllm-bench rm -f "$comp"
    log "completions failed; chat endpoint c${conc}"
    sudo docker exec -e HF_HOME=/tmp/hfhome -e HF_HUB_CACHE=/tmp/hfhome/hub vllm-bench vllm bench serve \
      --base-url http://127.0.0.1:8000 \
      --backend openai-chat \
      --endpoint /v1/chat/completions \
      --model "$REPO" \
      --tokenizer /model \
      --trust-remote-code \
      --dataset-name random \
      --random-input-len 128 \
      --random-output-len 128 \
      --num-prompts "$prompts" \
      --max-concurrency "$conc" \
      --ignore-eos \
      --request-rate inf \
      --save-result \
      --result-dir /tmp \
      --result-filename "vllm-c${conc}-chat.json"
    if ! bench_json_ok "$chat"; then
      log "chat result failed c${conc}"
      exit 1
    fi
    sudo docker cp "vllm-bench:${chat}" "$OUTDIR/vllm-c${conc}.json"
  else
    sudo docker cp "vllm-bench:${comp}" "$OUTDIR/vllm-c${conc}.json"
  fi
}

bench_one 1
bench_one 8
bench_one 32

kill "$SMI_PID" 2>/dev/null || true
wait "$SMI_PID" 2>/dev/null || true
rm -f "$OUTDIR/nvidia-smi.txt.tmp"
if [[ ! -s "$OUTDIR/nvidia-smi.txt" ]]; then
  nvidia-smi >"$OUTDIR/nvidia-smi.txt" || true
fi

python3 - <<'PY'
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
    failed = data.get("failed")
    completed = data.get("completed")
    total_output_tokens = data.get("total_output_tokens")
    print(f"c{conc} output_throughput {thr} completed {completed} failed {failed}")
    if (
        not thr
        or failed != 0
        or completed != conc * 5
        or total_output_tokens != conc * 5 * 128
    ):
        ok = False
if not ok:
    raise SystemExit(1)
PY

rm -f "$OUTDIR"/*fail.log
echo ok >"$OUTDIR/DONE"
sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "DONE $OUTDIR"
