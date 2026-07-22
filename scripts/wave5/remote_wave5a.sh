#!/usr/bin/env bash
# Wave 5a: Nanbeige + Atlas-Coder + Laguna-XS.2 sequentially. Env: HF_TOKEN
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
export HF_TOKEN

run_one() {
  local slug=$1 model=$2
  local out=$HOME/mc-bench/out/$slug
  mkdir -p "$out"
  echo "[$(date -u +%H:%M:%S)] === $slug ($model) ==="
  MODEL="$model" OUTDIR="$out" bash "$SCRIPT_DIR/remote_vllm_llm.sh" || {
    echo "[$(date -u +%H:%M:%S)] FAIL $slug" | tee "$out/FAIL"
    return 0
  }
}

run_one nanbeige4-2-3b Nanbeige/Nanbeige4.2-3B
run_one atlas-coder-2-0.5b Siddh07ETH/Atlas-Coder-2-0.5B
run_one laguna-xs-2 poolside/Laguna-XS.2

echo DONE >"$HOME/mc-bench/out/WAVE5A_DONE"
echo "[$(date -u +%H:%M:%S)] WAVE5A_DONE"
