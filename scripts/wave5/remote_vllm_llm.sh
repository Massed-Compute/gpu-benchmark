#!/usr/bin/env bash
# Generic vLLM LLM bench. Env: HF_TOKEN MODEL OUTDIR [TP] [MAX_MODEL_LEN] [VLLM_IMAGE]
set -euo pipefail
MODEL=${MODEL:?MODEL required}
TP=${TP:-1}
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:nightly}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/llm}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}
EXTRA_ARGS=${EXTRA_ARGS:-}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if ! command -v docker >/dev/null || ! "$HOME/mc-bench/venv/bin/python" -c "import openai" 2>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip curl jq
  sudo systemctl enable --now docker || true
  python3 -m venv "$HOME/mc-bench/venv"
  # shellcheck disable=SC1091
  . "$HOME/mc-bench/venv/bin/activate"
  pip install -q -U pip wheel 'openai>=1.40' aiohttp numpy
fi

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
log "pull $VLLM_IMAGE"
sudo docker pull "$VLLM_IMAGE"

log "start vLLM $MODEL tp=$TP"
# shellcheck disable=SC2086
sudo docker run -d --name vllm-bench --gpus all --shm-size 16g \
  -e HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" \
  -p 8000:8000 \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  "$VLLM_IMAGE" \
  --model "$MODEL" --tensor-parallel-size "$TP" --max-model-len "$MAX_MODEL_LEN" \
  --gpu-memory-utilization 0.90 --trust-remote-code --dtype auto $EXTRA_ARGS

ready=0
for i in $(seq 1 480); do
  if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
  if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench$'; then
    sudo docker logs --tail 300 vllm-bench | tee "$OUTDIR/vllm-serve.fail.log" || true
    exit 1
  fi
  sleep 10
done
[[ $ready -eq 1 ]] || { sudo docker logs --tail 300 vllm-bench | tee "$OUTDIR/vllm-serve.timeout.log"; exit 1; }
log VLLM_READY
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
echo "$MODEL" >"$OUTDIR/model.txt"

for CONC in 1 8 32; do
  log "vllm c$CONC"
  if ! sudo docker exec vllm-bench vllm bench serve \
    --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/completions \
    --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
    --num-prompts $(( CONC * 5 )) --max-concurrency "$CONC" --request-rate inf \
    --save-result --result-dir /tmp --result-filename "vllm-c${CONC}.json"
  then
    log "completions bench failed; trying chat endpoint"
    sudo docker exec vllm-bench vllm bench serve \
      --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/chat/completions \
      --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
      --num-prompts $(( CONC * 5 )) --max-concurrency "$CONC" --request-rate inf \
      --save-result --result-dir /tmp --result-filename "vllm-c${CONC}.json"
  fi
  sudo docker cp "vllm-bench:/tmp/vllm-c${CONC}.json" "$OUTDIR/vllm-c${CONC}.json"
done
# Require headline concurrency artifact before DONE.
[[ -s "$OUTDIR/vllm-c32.json" ]] || {
  echo "missing $OUTDIR/vllm-c32.json after bench" | tee "$OUTDIR/FAIL"
  sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
  exit 1
}
sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
