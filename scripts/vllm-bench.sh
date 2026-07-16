#!/usr/bin/env bash
# Run vLLM throughput benchmark against a local OpenAI-compatible server.
set -euo pipefail

MODEL_ID="${MODEL_ID:?set MODEL_ID}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
OUT_DIR="${OUT_DIR:-./results/raw}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
INPUT_LEN="${INPUT_LEN:-128}"
OUTPUT_LEN="${OUTPUT_LEN:-128}"
NUM_PROMPTS="${NUM_PROMPTS:-64}"

mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/${RUN_ID}-vllm-bench.json"

echo "Running vllm bench serve"
echo "  model: $MODEL_ID"
echo "  url:   $BASE_URL"
echo "  out:   $OUT_FILE"

# Requires vllm CLI on the host (or run inside the vLLM container).
vllm bench serve \
  --backend openai \
  --base-url "$BASE_URL" \
  --model "$MODEL_ID" \
  --dataset-name random \
  --input-len "$INPUT_LEN" \
  --output-len "$OUTPUT_LEN" \
  --num-prompts "$NUM_PROMPTS" \
  --save-result \
  --result-filename "$OUT_FILE"

echo "Saved: $OUT_FILE"
