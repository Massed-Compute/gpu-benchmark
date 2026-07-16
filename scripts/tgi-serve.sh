#!/usr/bin/env bash
# Launch Hugging Face TGI for an LLM inference benchmark on Massed Compute.
set -euo pipefail

MODEL_ID="${MODEL_ID:?set MODEL_ID e.g. meta-llama/Llama-3.3-70B-Instruct}"
HF_TOKEN="${HF_TOKEN:?set HF_TOKEN}"
NUM_SHARD="${NUM_SHARD:-$(nvidia-smi -L | wc -l | tr -d ' ')}"
TGI_IMAGE="${TGI_IMAGE:-ghcr.io/huggingface/text-generation-inference:3.0.1}"
PORT="${PORT:-8080}"
SHM_SIZE="${SHM_SIZE:-16g}"
DATA_DIR="${DATA_DIR:-$HOME/tgi-data}"
CONTAINER_NAME="${CONTAINER_NAME:-tgi-bench}"

mkdir -p "$DATA_DIR"

echo "Starting TGI"
echo "  model:  $MODEL_ID"
echo "  shards: $NUM_SHARD"
echo "  image:  $TGI_IMAGE"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d --name "$CONTAINER_NAME" --gpus all --shm-size "$SHM_SIZE" \
  -e HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" \
  -p "${PORT}:80" \
  -v "${DATA_DIR}:/data" \
  "$TGI_IMAGE" \
  --model-id "$MODEL_ID" \
  --sharded true \
  --num-shard "$NUM_SHARD"

echo "Waiting for /health on :$PORT ..."
for i in $(seq 1 120); do
  if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null; then
    echo "TGI ready."
    exit 0
  fi
  sleep 5
done

echo "Timed out waiting for TGI. Last logs:" >&2
docker logs --tail 80 "$CONTAINER_NAME" >&2
exit 1
