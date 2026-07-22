#!/usr/bin/env bash
# Wave 5b: Mage-Flow then FLUX ConvRot. Env: HF_TOKEN
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
export HF_TOKEN

mkdir -p "$HOME/mc-bench/out/mage-flow" "$HOME/mc-bench/out/flux-convrot"
echo "[$(date -u +%H:%M:%S)] === mage-flow ==="
OUTDIR=$HOME/mc-bench/out/mage-flow bash "$SCRIPT_DIR/remote_mage_flow.sh" || \
  echo FAIL | tee "$HOME/mc-bench/out/mage-flow/FAIL"

echo "[$(date -u +%H:%M:%S)] === flux-convrot ==="
OUTDIR=$HOME/mc-bench/out/flux-convrot bash "$SCRIPT_DIR/remote_flux_convrot.sh" || \
  echo FAIL | tee "$HOME/mc-bench/out/flux-convrot/FAIL"

echo DONE >"$HOME/mc-bench/out/WAVE5B_DONE"
echo "[$(date -u +%H:%M:%S)] WAVE5B_DONE"
