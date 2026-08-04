#!/usr/bin/env bash
# Wave 5a: Nanbeige (transformers) + Atlas (PEFT merge + transformers/SDPA) + Laguna-XS.2 (vLLM).
# Env: HF_TOKEN
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
export HF_TOKEN

mkdir -p \
  "$HOME/mc-bench/out/nanbeige4-2-3b" \
  "$HOME/mc-bench/out/atlas-coder-2-0.5b" \
  "$HOME/mc-bench/out/laguna-xs-2"

echo "[$(date -u +%H:%M:%S)] === nanbeige4-2-3b (transformers) ==="
MODEL=Nanbeige/Nanbeige4.2-3B OUTDIR="$HOME/mc-bench/out/nanbeige4-2-3b" \
  bash "$SCRIPT_DIR/remote_nanbeige_hf.sh" || {
    echo "[$(date -u +%H:%M:%S)] FAIL nanbeige4-2-3b" | tee "$HOME/mc-bench/out/nanbeige4-2-3b/FAIL"
  }

# remote_atlas_a6000.sh merges PEFT if needed, then benches with attn_implementation=sdpa.
echo "[$(date -u +%H:%M:%S)] === atlas-coder-2-0.5b (merge + transformers/SDPA) ==="
OUTDIR="$HOME/mc-bench/out/atlas-coder-2-0.5b" \
  bash "$SCRIPT_DIR/remote_atlas_a6000.sh" || {
    echo "[$(date -u +%H:%M:%S)] FAIL atlas-coder-2-0.5b" | tee "$HOME/mc-bench/out/atlas-coder-2-0.5b/FAIL"
  }

echo "[$(date -u +%H:%M:%S)] === laguna-xs-2 (vLLM) ==="
MODEL=poolside/Laguna-XS.2 OUTDIR="$HOME/mc-bench/out/laguna-xs-2" \
  bash "$SCRIPT_DIR/remote_vllm_llm.sh" || {
    echo "[$(date -u +%H:%M:%S)] FAIL laguna-xs-2" | tee "$HOME/mc-bench/out/laguna-xs-2/FAIL"
  }

echo DONE >"$HOME/mc-bench/out/WAVE5A_DONE"
echo "[$(date -u +%H:%M:%S)] WAVE5A_DONE"
