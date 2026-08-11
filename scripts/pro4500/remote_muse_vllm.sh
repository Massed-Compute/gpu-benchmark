#!/usr/bin/env bash
# Muse Glimmer via official vLLM muse-glimmer image.
# MODEL env: HF id (BF16 / FP8 / NVFP4). EXTRA_ARGS optional.
set -euo pipefail
MODEL=${MODEL:-meta-models/Muse-Glimmer-30B}
TP=${TP:-1}
PORT=${PORT:-8000}
HF_TOKEN=${HF_TOKEN:-}
IMG=${VLLM_IMAGE:-vllm/vllm-openai:muse-glimmer}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/muse-glimmer-vllm}
MAX_LEN=${VLLM_MAX_MODEL_LEN:-8192}
EXTRA_ARGS=${VLLM_EXTRA_ARGS:-"--generation-config auto --enable-auto-tool-choice --tool-call-parser muse_glimmer --reasoning-parser muse_glimmer"}
mkdir -p "$OUTDIR" "$HOME/mc-bench/venv" "$HOME/.cache/huggingface"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip curl jq || true
sudo systemctl enable --now docker || true
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip 'openai>=1.40' aiohttp numpy

log "pull $IMG"
sudo docker pull "$IMG"

COMMON=(--model "$MODEL" --tensor-parallel-size "$TP" --max-model-len "$MAX_LEN"
  --gpu-memory-utilization 0.92 --max-num-batched-tokens 16384 --enable-prefix-caching
  --trust-remote-code --kv-cache-dtype fp8 --limit-mm-per-prompt '{"image":0}')
# shellcheck disable=SC2206
EXTRA=( $EXTRA_ARGS )
COMMON+=("${EXTRA[@]}")

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "serve $MODEL tp=$TP"
sudo docker run -d --name vllm-bench --gpus all --shm-size 16g \
  -e "HUGGING_FACE_HUB_TOKEN=$HF_TOKEN" \
  -p "${PORT}:8000" \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  "$IMG" \
  "${COMMON[@]}"

ready=0
for i in $(seq 1 360); do
  if curl -sf "http://127.0.0.1:${PORT}/v1/models" >/dev/null; then
    ready=1
    break
  fi
  if ! sudo docker ps -q -f name=vllm-bench | grep -q .; then
    log "container died"
    sudo docker logs --tail 200 vllm-bench | tee "$OUTDIR/serve-fail.log" || true
    exit 1
  fi
  sleep 10
done
[[ "$ready" == "1" ]] || { sudo docker logs --tail 200 vllm-bench | tee "$OUTDIR/serve-fail.log"; exit 1; }
log "VLLM_READY"

for conc in 1 8 32; do
  log "bench c$conc"
  sudo docker exec vllm-bench vllm bench serve \
    --base-url "http://127.0.0.1:8000" \
    --backend openai \
    --endpoint /v1/completions \
    --model "$MODEL" \
    --dataset-name random \
    --random-input-len 128 \
    --random-output-len 128 \
    --num-prompts $(( conc * 5 )) \
    --max-concurrency "$conc" \
    --request-rate inf \
    --save-result \
    --result-dir /tmp \
    --result-filename "vllm-c${conc}.json" \
    2>&1 | tee "$OUTDIR/bench-c${conc}.log" || true
  sudo docker cp "vllm-bench:/tmp/vllm-c${conc}.json" "$OUTDIR/vllm-c${conc}.json" 2>/dev/null || true
done

nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
ls -la "$OUTDIR"
