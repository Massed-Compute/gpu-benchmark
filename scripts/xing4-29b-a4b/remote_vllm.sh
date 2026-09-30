#!/usr/bin/env bash
# Xing4.0-29B-A4B BF16 via the vendor vLLM image (upstream has no Xing4_0).
# No prefix cache. No MTP. Env: OUTDIR, SKU. Token file is ~/.cache/huggingface/token.
set -euo pipefail
MODEL=${MODEL:-XingChen-AGI/Xing4.0-29B-A4B}
TP=${TP:-1}
VLLM_IMAGE=${VLLM_IMAGE:-quay.io/xingchen-agi/xingchen-inference-vllm:v0.29.1rc1-xing4_0}
OUTDIR=${OUTDIR:?OUTDIR required}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-8192}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

cleanup() { sudo docker rm -f vllm-bench >/dev/null 2>&1 || true; }
trap cleanup EXIT

if ! command -v docker >/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io curl ca-certificates
  sudo systemctl enable --now docker || true
fi
if ! sudo docker info 2>/dev/null | grep -qi nvidia; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvidia-container-toolkit || true
  sudo nvidia-ctk runtime configure --runtime=docker || true
  sudo systemctl restart docker || true
fi

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "pull $VLLM_IMAGE"
pulled=0
for _try in 1 2 3; do
  if sudo docker pull "$VLLM_IMAGE"; then
    pulled=1
    break
  fi
  log "docker pull failed, retry $_try"
  sleep 8
done
[[ "$pulled" == 1 ]]

start_server() {
  local len="$1"
  sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
  log "start vLLM len=$len tp=$TP mtp=${MTP:-0} util=0.92 prefix-cache off"
  local inner='vllm serve "$MODEL" --host 0.0.0.0 --port 8000 --trust-remote-code --served-model-name "$MODEL" --tensor-parallel-size "$TP" --max-model-len "$MAX_MODEL_LEN" --gpu-memory-utilization 0.92 --max-num-batched-tokens 16384 --max-num-seqs 64'
  if [[ "${MTP:-0}" == 1 ]]; then
    inner+=$' --speculative-config \'{"method":"mtp","num_speculative_tokens":1}\''
  fi
  sudo docker run -d --name vllm-bench --gpus all --ipc=host --shm-size 16g \
    --entrypoint bash \
    -e MODEL="$MODEL" \
    -e TP="$TP" \
    -e MAX_MODEL_LEN="$len" \
    -p 8000:8000 \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    "$VLLM_IMAGE" \
    -lc "$inner"
}

wait_ready() {
  local i
  for i in $(seq 1 720); do
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

USED_LEN="$MAX_MODEL_LEN"
start_server "$USED_LEN"
if ! wait_ready; then
  sudo docker logs --tail 200 vllm-bench >"$OUTDIR/vllm-serve-8192.fail.log" 2>&1 || true
  if [[ "$USED_LEN" == "8192" ]]; then
    log "8192 did not stay up; retry 4096 once"
    USED_LEN=4096
    start_server "$USED_LEN"
    if ! wait_ready; then
      sudo docker logs --tail 300 vllm-bench | tee "$OUTDIR/vllm-serve.fail.log" || true
      echo FAIL >"$OUTDIR/FAIL"
      exit 1
    fi
  else
    sudo docker logs --tail 300 vllm-bench | tee "$OUTDIR/vllm-serve.fail.log" || true
    echo FAIL >"$OUTDIR/FAIL"
    exit 1
  fi
fi
log VLLM_READY
echo "$USED_LEN" >"$OUTDIR/max-model-len.txt"
nvidia-smi --query-gpu=name,memory.used,memory.total,driver_version --format=csv | tee "$OUTDIR/nvidia-smi-ready.txt"
# First table captures wrote "mtp=off" and omitted tp (those servers are tp=1).
# This writer records mtp=0 for off and an explicit tp= line.
{
  echo "image=$VLLM_IMAGE"
  echo "max_model_len=$USED_LEN"
  echo "prefix_caching=off"
  echo "mtp=${MTP:-0}"
  echo "tp=$TP"
  echo "kv_cache_dtype=default"
  echo "gpu_memory_utilization=0.92"
  echo "max_num_batched_tokens=16384"
  echo "digests=$(sudo docker image inspect --format '{{json .RepoDigests}}' "$VLLM_IMAGE")"
  echo "image_id=$(sudo docker inspect --format '{{.Image}}' vllm-bench)"
  sudo docker exec vllm-bench vllm --version 2>/dev/null || true
} | tee "$OUTDIR/engine.txt"

# Full nvidia-smi while a request is on GPU.
(
  for _ in $(seq 1 180); do
    line=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null || true)
    util=${line%%,*}
    util=${util// /}
    if [[ "${util:-0}" =~ ^[0-9]+$ ]] && [[ "$util" -ge 40 ]]; then
      nvidia-smi >"$OUTDIR/nvidia-smi.txt"
      exit 0
    fi
    sleep 2
  done
) >/dev/null 2>&1 &
SMI_PID=$!

for CONC in 1 8 32; do
  log "vllm c$CONC"
  if ! sudo docker exec vllm-bench vllm bench serve \
    --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/completions \
    --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
    --num-prompts $(( CONC * 5 )) --max-concurrency "$CONC" --request-rate inf \
    --save-result --result-dir /tmp --result-filename "vllm-c${CONC}.json"
  then
    log "completions bench failed; trying chat endpoint"
    sudo docker exec vllm-bench vllm bench serve \
      --base-url http://127.0.0.1:8000 --backend openai-chat --endpoint /v1/chat/completions \
      --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
      --num-prompts $(( CONC * 5 )) --max-concurrency "$CONC" --request-rate inf \
      --save-result --result-dir /tmp --result-filename "vllm-c${CONC}.json"
  fi
  sudo docker cp "vllm-bench:/tmp/vllm-c${CONC}.json" "$OUTDIR/vllm-c${CONC}.json"
done
if [[ "${RERUN_C32:-0}" == 1 ]]; then
  log "vllm c32 rerun (server already warm)"
  sudo docker exec vllm-bench vllm bench serve \
    --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/completions \
    --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
    --num-prompts 160 --max-concurrency 32 --request-rate inf \
    --save-result --result-dir /tmp --result-filename vllm-c32-rerun.json
  sudo docker cp vllm-bench:/tmp/vllm-c32-rerun.json "$OUTDIR/vllm-c32-rerun.json"
fi
wait "$SMI_PID" || true
if [[ ! -s "$OUTDIR/nvidia-smi.txt" ]]; then
  nvidia-smi >"$OUTDIR/nvidia-smi.txt"
fi
[[ -s "$OUTDIR/vllm-c32.json" ]] || {
  echo "missing c32" | tee "$OUTDIR/FAIL"
  exit 1
}
echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
