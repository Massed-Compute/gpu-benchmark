#!/usr/bin/env bash
# Live bench: Qwen/Qwen3-235B-A22B-FP8 on 4x RTX PRO 6000 Blackwell.
# Random 128/128, request-rate=inf, concurrency 1/8/32. No prefix cache.
# DONE only after each JSON has output_throughput and zero failures.
set -euo pipefail
cleanup() { sudo docker rm -f vllm-bench >/dev/null 2>&1 || true; }
trap cleanup EXIT

MODEL=Qwen/Qwen3-235B-A22B-FP8
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:v0.27.1}
TP=4
MAX_MODEL_LEN=8192
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/qwen3-235b-a22b-fp8/4xBlackwell-fp8}
tag=${VLLM_IMAGE##*:}
if [[ "$tag" == "latest" ]]; then
  echo "refuse floating image tag" >&2
  exit 1
fi

mkdir -p "$OUTDIR" "$HOME/.cache/huggingface"
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if ! command -v docker >/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io curl
  sudo systemctl enable --now docker
fi

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "pull $VLLM_IMAGE"
sudo docker pull "$VLLM_IMAGE"
sudo docker image inspect "$VLLM_IMAGE" --format '{{index .RepoDigests 0}}' | tee "$OUTDIR/image-digest.txt"
{
  echo "model=$MODEL"
  echo "tp=$TP"
  echo "max_model_len=$MAX_MODEL_LEN"
  echo "kv_cache_dtype=fp8"
  echo "prefix_caching=off"
  echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} | tee "$OUTDIR/serve-args.txt"

nvidia-smi --query-gpu=timestamp,name,memory.used,memory.total,driver_version --format=csv \
  | tee "$OUTDIR/nvidia-smi-idle.txt"

start_server() {
  local extra=("$@")
  sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
  sudo docker run -d --name vllm-bench --gpus all --shm-size 32g --ipc=host \
    -e VLLM_USE_DEEP_GEMM=0 \
    -e VLLM_MOE_USE_DEEP_GEMM=0 \
    -p 127.0.0.1:8000:8000 \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    "$VLLM_IMAGE" \
    --model "$MODEL" \
    --tensor-parallel-size "$TP" \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization 0.92 \
    --max-num-batched-tokens 16384 \
    --trust-remote-code \
    "${extra[@]}"
}

# Qwen block-FP8 uses float scales. vLLM's DeepGEMM default is UE8M0 and
# crashes this GPU with "Unknown SF transformation".
log "start vLLM tp=$TP moe=triton deepgemm=0"
start_server --kv-cache-dtype fp8 --moe-backend triton
echo "fp8 moe=triton deepgemm=0" > "$OUTDIR/kv-cache-dtype.txt"

ready=0
for i in $(seq 1 1440); do
  if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
  if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
    sudo docker logs --tail 200 vllm-bench | tee "$HOME/mc-bench/vllm-serve.fail.log" || true
    exit 1
  fi
  if (( i % 4 == 0 )); then
    log "waiting for serve ($((i * 15))s)"
    nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader | tr '\n' ' '
    echo
    du -sh "$HOME/.cache/huggingface" 2>/dev/null || true
  fi
  sleep 15
done
if [[ $ready -ne 1 ]]; then
  sudo docker logs --tail 200 vllm-bench | tee "$HOME/mc-bench/vllm-serve.timeout.log" || true
  exit 1
fi
log VLLM_READY
sudo docker exec vllm-bench python3 -c 'import vllm; print(vllm.__version__)' | tee "$OUTDIR/vllm-version.txt"
date -u +%Y-%m-%dT%H:%M:%SZ | tee "$OUTDIR/serve-ready-utc.txt"

for CONC in 1 8 32; do
  log "vllm c$CONC"
  (
    while true; do
      nvidia-smi --query-gpu=timestamp,name,memory.used,memory.total,utilization.gpu --format=csv
      sleep 2
    done
  ) > "$OUTDIR/nvidia-smi-c${CONC}.txt" &
  SMI_PID=$!
  sudo docker exec vllm-bench vllm bench serve \
    --base-url http://127.0.0.1:8000 \
    --backend openai \
    --endpoint /v1/completions \
    --model "$MODEL" \
    --dataset-name random \
    --random-input-len 128 \
    --random-output-len 128 \
    --num-prompts $(( CONC * 5 )) \
    --max-concurrency "$CONC" \
    --request-rate inf \
    --save-result \
    --result-dir /tmp \
    --result-filename "vllm-c${CONC}.json"
  sudo docker cp "vllm-bench:/tmp/vllm-c${CONC}.json" "$OUTDIR/vllm-c${CONC}.json"
  kill "$SMI_PID" || true
  wait "$SMI_PID" || true
  python3 - "$OUTDIR/vllm-c${CONC}.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
completed = int(data.get("completed") or 0)
failed = int(data.get("failed") or 0)
ot = data.get("output_throughput")
if completed < 1 or failed or not isinstance(ot, (int, float)):
    raise SystemExit(f"bad bench json {path}: completed={completed} failed={failed} output_throughput={ot}")
print(f"{path} completed={completed} failed={failed} output_throughput={ot}")
PY
done

cp "$OUTDIR/nvidia-smi-c32.txt" "$OUTDIR/nvidia-smi.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUTDIR/finished-utc.txt"
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
