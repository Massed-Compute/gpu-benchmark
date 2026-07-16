#!/usr/bin/env bash
# Launch vLLM OpenAI-compatible server for benchmarking.
set -euo pipefail

MODEL_ID="${MODEL_ID:?set MODEL_ID}"
HF_TOKEN="${HF_TOKEN:-}"
TP="${TP:-$(nvidia-smi -L | wc -l | tr -d ' ')}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:v0.8.5}"
PORT="${PORT:-8000}"
CONTAINER_NAME="${CONTAINER_NAME:-vllm-bench}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

ENV_ARGS=()
if [[ -n "$HF_TOKEN" ]]; then
  ENV_ARGS+=(-e "HUGGING_FACE_HUB_TOKEN=$HF_TOKEN")
fi

echo "Starting vLLM"
echo "  model: $MODEL_ID"
echo "  tp:    $TP"
echo "  image: $VLLM_IMAGE"

docker run -d --name "$CONTAINER_NAME" --gpus all --shm-size 16g \
  "${ENV_ARGS[@]}" \
  -p "${PORT}:8000" \
  "$VLLM_IMAGE" \
  --model "$MODEL_ID" \
  --tensor-parallel-size "$TP" \
  --max-model-len "$MAX_MODEL_LEN"

echo "Waiting for /v1/models on :$PORT ..."
for i in $(seq 1 120); do
  if curl -sf "http://127.0.0.1:${PORT}/v1/models" >/dev/null; then
    echo "vLLM ready."
    exit 0
  fi
  sleep 5
done

echo "Timed out waiting for vLLM. Last logs:" >&2
docker logs --tail 80 "$CONTAINER_NAME" >&2
exit 1
