#!/usr/bin/env bash
# Solar Open2 NVFP4 via host vLLM + fla-core (docker image lacks fla). Env: HF_TOKEN OUTDIR TP
set -euo pipefail
MODEL=${MODEL:-nota-ai/Solar-Open2-250B-Nota-NVFP4}
TP=${TP:-2}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/solar-open2-250b-a15b}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip curl jq || true
python3 -m venv "$HOME/mc-bench/venv-solar"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv-solar/bin/activate"
pip install -q -U pip wheel
pip install -q -U 'fla-core' 'vllm' 'openai>=1.40' aiohttp numpy huggingface_hub

sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
pkill -f "vllm serve" >/dev/null 2>&1 || true
log "serve $MODEL tp=$TP (host vllm+fla)"
nohup "$HOME/mc-bench/venv-solar/bin/vllm" serve "$MODEL" \
  --tensor-parallel-size "$TP" --max-model-len "$MAX_MODEL_LEN" \
  --gpu-memory-utilization 0.90 --trust-remote-code --dtype auto \
  --port 8000 >"$OUTDIR/vllm-serve.log" 2>&1 &
echo $! >"$OUTDIR/vllm.pid"

ready=0
for i in $(seq 1 600); do
  if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then ready=1; break; fi
  if ! kill -0 "$(cat "$OUTDIR/vllm.pid")" 2>/dev/null; then
    tail -200 "$OUTDIR/vllm-serve.log" | tee "$OUTDIR/vllm-serve.fail.log"
    exit 1
  fi
  sleep 10
done
[[ $ready -eq 1 ]] || { tail -200 "$OUTDIR/vllm-serve.log" | tee "$OUTDIR/vllm-serve.timeout.log"; exit 1; }
log VLLM_READY
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
echo "$MODEL" >"$OUTDIR/model.txt"

for CONC in 1 8 32; do
  log "vllm c$CONC"
  "$HOME/mc-bench/venv-solar/bin/vllm" bench serve \
    --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/completions \
    --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
    --num-prompts $(( CONC * 5 )) --max-concurrency "$CONC" --request-rate inf \
    --save-result --result-dir "$OUTDIR" --result-filename "vllm-c${CONC}.json" \
  || "$HOME/mc-bench/venv-solar/bin/vllm" bench serve \
    --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/chat/completions \
    --model "$MODEL" --dataset-name random --random-input-len 128 --random-output-len 128 \
    --num-prompts $(( CONC * 5 )) --max-concurrency "$CONC" --request-rate inf \
    --save-result --result-dir "$OUTDIR" --result-filename "vllm-c${CONC}.json" || true
done
kill "$(cat "$OUTDIR/vllm.pid")" 2>/dev/null || true
rm -f "$OUTDIR/FAIL"
echo DONE >"$OUTDIR/DONE"
log "DONE $OUTDIR"
