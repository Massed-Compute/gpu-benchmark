#!/usr/bin/env bash
# Run TGI text-generation-benchmark and capture stdout for later parsing.
set -euo pipefail

MODEL_ID="${MODEL_ID:?set MODEL_ID}"
CONTAINER_NAME="${CONTAINER_NAME:-tgi-bench}"
OUT_DIR="${OUT_DIR:-./results/raw}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
TOKENIZER_NAME="${TOKENIZER_NAME:-$MODEL_ID}"

mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/${RUN_ID}-tgi-benchmark.txt"

echo "Running text-generation-benchmark in $CONTAINER_NAME"
echo "  tokenizer: $TOKENIZER_NAME"
echo "  output:    $OUT_FILE"

# Non-interactive dump: pipe through script so TUI output is still captured.
docker exec -i "$CONTAINER_NAME" \
  text-generation-benchmark --tokenizer-name "$TOKENIZER_NAME" \
  | tee "$OUT_FILE"

echo
echo "Saved: $OUT_FILE"
echo "Next: parse into JSON with scripts/parse_tgi_output.py"
