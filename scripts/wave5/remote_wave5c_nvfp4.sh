#!/usr/bin/env bash
# Wave 5c retry: Solar Open2 NVFP4 + Laguna-S NVFP4 (BF16 OOM on 2x96GB). Env: HF_TOKEN TP
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
TP=${TP:-2}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
export HF_TOKEN TP

run_one() {
  local slug=$1 model=$2
  local out=$HOME/mc-bench/out/$slug
  mkdir -p "$out"
  rm -f "$out/FAIL" "$out/DONE"
  echo "[$(date -u +%H:%M:%S)] === $slug ($model) tp=$TP ==="
  MODEL="$model" OUTDIR="$out" TP="$TP" MAX_MODEL_LEN=4096 \
    bash "$SCRIPT_DIR/remote_vllm_llm.sh" || {
      echo "[$(date -u +%H:%M:%S)] FAIL $slug" | tee "$out/FAIL"
      return 0
    }
}

run_one solar-open2-250b-a15b nota-ai/Solar-Open2-250B-Nota-NVFP4
run_one laguna-s-2.1 poolside/Laguna-S-2.1-NVFP4

echo DONE >"$HOME/mc-bench/out/WAVE5C_DONE"
echo "[$(date -u +%H:%M:%S)] WAVE5C_DONE"
