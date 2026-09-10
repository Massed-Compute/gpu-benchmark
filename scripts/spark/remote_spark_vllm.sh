#!/usr/bin/env bash
# Spark-X2.5-4B vLLM bench via vllm-spark2-5-plugin. Env: HF_TOKEN [MODEL] [OUTDIR] [VLLM_IMAGE]
set -euo pipefail
MODEL=${MODEL:-XHToken/Spark-X2.5-4B}
TP=${TP:-1}
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:v0.28.0}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/spark}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-8192}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

cleanup() { sudo docker rm -f vllm-bench >/dev/null 2>&1 || true; }
trap cleanup EXIT

[[ "$TP" =~ ^[1-9][0-9]*$ ]] || { echo "TP must be a positive integer"; exit 1; }
[[ "$MAX_MODEL_LEN" =~ ^[1-9][0-9]*$ ]] || { echo "MAX_MODEL_LEN must be a positive integer"; exit 1; }

if ! command -v docker >/dev/null || ! "$HOME/mc-bench/venv/bin/python" -c "import openai" 2>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io python3-venv python3-pip curl jq
  sudo systemctl enable --now docker || true
  python3 -m venv "$HOME/mc-bench/venv"
  # shellcheck disable=SC1091
  . "$HOME/mc-bench/venv/bin/activate"
  pip install -q -U pip wheel 'openai>=1.40' aiohttp numpy
fi

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "pull $VLLM_IMAGE"
sudo docker pull "$VLLM_IMAGE"

log "start vLLM $MODEL with spark2_5 plugin tp=$TP maxlen=$MAX_MODEL_LEN"
sudo docker run -d --name vllm-bench --gpus all --ipc=host --shm-size 16g \
  --entrypoint bash \
  -e HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" \
  -e HF_TOKEN="$HF_TOKEN" \
  -e VLLM_PLUGINS=spark2_5 \
  -e MODEL="$MODEL" \
  -e TP="$TP" \
  -e MAX_MODEL_LEN="$MAX_MODEL_LEN" \
  -p 8000:8000 \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  "$VLLM_IMAGE" \
  -lc 'pip install -q vllm-spark2-5-plugin && \
    vllm serve "$MODEL" --host 0.0.0.0 --port 8000 --trust-remote-code \
      --served-model-name "$MODEL" --tensor-parallel-size "$TP" \
      --max-model-len "$MAX_MODEL_LEN" --gpu-memory-utilization 0.90 \
      --tool-call-parser spark25 --reasoning-parser qwen3'

ready=0
for i in $(seq 1 480); do
  if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
  if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
    sudo docker logs --tail 300 vllm-bench | tee "$OUTDIR/vllm-serve.fail.log" || true
    exit 1
  fi
  sleep 10
done
[[ $ready -eq 1 ]] || { sudo docker logs --tail 300 vllm-bench | tee "$OUTDIR/vllm-serve.timeout.log"; exit 1; }
log VLLM_READY
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
echo "$MODEL" >"$OUTDIR/model.txt"
{
  echo "image=$VLLM_IMAGE"
  sudo docker inspect --format '{{json .RepoDigests}}' vllm-bench 2>/dev/null || true
  sudo docker exec vllm-bench vllm --version 2>/dev/null || true
  sudo docker exec vllm-bench pip show vllm-spark2-5-plugin 2>/dev/null | awk '/^(Name|Version|Summary):/' || true
} | tee "$OUTDIR/engine.txt"

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
[[ -s "$OUTDIR/vllm-c32.json" ]] || {
  echo "missing $OUTDIR/vllm-c32.json after bench" | tee "$OUTDIR/FAIL"
  exit 1
}
echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
