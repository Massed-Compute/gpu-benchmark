#!/usr/bin/env bash
# Qwen/Qwen3.6-35B-A3B multimodal MoE — text-only vLLM bench
set -euo pipefail
MODEL=${MODEL:-Qwen/Qwen3.6-35B-A3B}
TP=${TP:-1}
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:nightly}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/qwen3.6-35b-a3b}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-8192}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if ! "$HOME/mc-bench/venv/bin/python" -c "import openai" 2>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip curl jq
  sudo systemctl enable --now docker || true
  python3 -m venv "$HOME/mc-bench/venv"
  . "$HOME/mc-bench/venv/bin/activate"
  pip install -q -U pip wheel 'openai>=1.40' aiohttp numpy
fi

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "pull $VLLM_IMAGE"
sudo docker pull "$VLLM_IMAGE"

start_vllm() {
  local extra=("$@")
  sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
  sudo docker run -d --name vllm-bench --gpus all --shm-size 16g \
    -e HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" \
    -p 8000:8000 \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    "$VLLM_IMAGE" \
    --model "$MODEL" --tensor-parallel-size "$TP" --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization 0.92 --max-num-batched-tokens 16384 --enable-prefix-caching \
    --trust-remote-code --dtype auto --max-num-seqs 128 \
    "${extra[@]}"
}

log "start vLLM $MODEL (fp8-kv + mm-limit)"
start_vllm --kv-cache-dtype fp8 --limit-mm-per-prompt '{"image":0}'

ready=0
for i in $(seq 1 360); do
  if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
  if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
    sudo docker logs --tail 120 vllm-bench | tee "$OUTDIR/vllm-serve.fail.log" || true
    log "retry without fp8 kv"
    start_vllm --limit-mm-per-prompt '{"image":0}'
    for j in $(seq 1 240); do
      if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
      if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
        sudo docker logs --tail 200 vllm-bench | tee "$OUTDIR/vllm-serve.fail2.log" || true
        # last try: no mm limit
        log "retry without mm limit"
        start_vllm
        for k in $(seq 1 180); do
          if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
          if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
            sudo docker logs --tail 200 vllm-bench | tee "$OUTDIR/vllm-serve.fail3.log" || true
            exit 1
          fi
          sleep 10
        done
        break
      fi
      sleep 10
    done
    break
  fi
  sleep 10
done
[[ $ready -eq 1 ]] || { sudo docker logs --tail 200 vllm-bench; exit 1; }
log VLLM_READY
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"

for CONC in 1 8 32; do
  log "bench c$CONC"
  sudo docker exec vllm-bench vllm bench serve \
    --base-url http://127.0.0.1:8000 \
    --backend openai \
    --endpoint /v1/completions \
    --model "$MODEL" \
    --dataset-name random \
    --random-input-len 128 \
    --random-output-len 128 \
    --num-prompts $(( CONC * 5 )) \
    --max-concurrency "$CONC" \
    --request-rate inf \
    --save-result \
    --result-dir /tmp \
    --result-filename "vllm-c${CONC}.json" || true
  sudo docker cp "vllm-bench:/tmp/vllm-c${CONC}.json" "$OUTDIR/vllm-c${CONC}.json" 2>/dev/null || true
done

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
echo DONE > "$OUTDIR/DONE"
log "DONE $OUTDIR"
