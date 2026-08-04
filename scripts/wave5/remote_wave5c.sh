#!/usr/bin/env bash
# Wave 5c: Solar Open2 NVFP4 (Upstage Docker) + Laguna-S-2.1-NVFP4 (vLLM).
# BF16 Solar/Laguna-S OOMs on 2×96GB — use the NVFP4 paths that produced the published pages.
# Env: HF_TOKEN TP
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
TP=${TP:-2}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
export HF_TOKEN TP

mkdir -p "$HOME/mc-bench/out/solar-open2-250b-a15b" "$HOME/mc-bench/out/laguna-s-2.1"

echo "[$(date -u +%H:%M:%S)] === solar-open2-250b-a15b (NVFP4 / Upstage Docker) tp=$TP ==="
MODEL=nota-ai/Solar-Open2-250B-Nota-NVFP4 \
  OUTDIR="$HOME/mc-bench/out/solar-open2-250b-a15b" \
  TP="$TP" \
  bash "$SCRIPT_DIR/remote_solar_upstage.sh" || {
    echo "[$(date -u +%H:%M:%S)] FAIL solar-open2-250b-a15b" | tee "$HOME/mc-bench/out/solar-open2-250b-a15b/FAIL"
  }

echo "[$(date -u +%H:%M:%S)] === laguna-s-2.1 (NVFP4) tp=$TP ==="
MODEL=poolside/Laguna-S-2.1-NVFP4 \
  OUTDIR="$HOME/mc-bench/out/laguna-s-2.1" \
  TP="$TP" \
  MAX_MODEL_LEN=4096 \
  bash "$SCRIPT_DIR/remote_vllm_llm.sh" || {
    echo "[$(date -u +%H:%M:%S)] FAIL laguna-s-2.1" | tee "$HOME/mc-bench/out/laguna-s-2.1/FAIL"
  }

echo DONE >"$HOME/mc-bench/out/WAVE5C_DONE"
echo "[$(date -u +%H:%M:%S)] WAVE5C_DONE"
