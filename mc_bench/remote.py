"""Remote bootstrap + bench helpers via SSH."""
from __future__ import annotations

BOOTSTRAP = r'''
set -euxo pipefail
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip git curl jq 2>/dev/null || true
sudo systemctl enable --now docker || true
mkdir -p "$HOME/mc-bench" "$HOME/.cache/huggingface"
python3 -m venv "$HOME/mc-bench/venv"
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel
pip install -q 'openai>=1.40' 'aiohttp' 'numpy' 'transformers' 'datasets' 'pillow' 'pandas'
echo BOOTSTRAP_OK
'''

# Optimized profile: FP8 KV + prefix cache + large batch.
# DeepSeek-V4 requires fp8 KV (fp8_ds_mla) — do not fall back to auto KV.
# VLLM_MAX_MODEL_LEN / VLLM_EXTRA_ARGS optional; wait covers large HF pulls.
VLLM_SERVE = r'''
set -euxo pipefail
MODEL="{model}"
TP="{tp}"
PORT="{port}"
HF_TOKEN="{hf_token}"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
IMG="${{VLLM_IMAGE:-vllm/vllm-openai:v0.8.5}}"
MAX_LEN="${{VLLM_MAX_MODEL_LEN:-8192}}"
COMMON=(--model "$MODEL" --tensor-parallel-size "$TP" --max-model-len "$MAX_LEN" \
  --gpu-memory-utilization 0.92 --max-num-batched-tokens 16384 --enable-prefix-caching \
  --trust-remote-code --kv-cache-dtype fp8)
# VL / multimodal: text-only decode bench (set VLLM_TEXT_ONLY_MM=1)
if [[ "${{VLLM_TEXT_ONLY_MM:-0}}" == "1" ]]; then
  COMMON+=(--limit-mm-per-prompt '{{"image":0}}')
fi
# shellcheck disable=SC2206
if [[ -n "${{VLLM_EXTRA_ARGS:-}}" ]]; then
  # intentionally unquoted: space-separated extra flags
  EXTRA=( ${{VLLM_EXTRA_ARGS}} )
  COMMON+=("${{EXTRA[@]}}")
fi

_run() {{
  sudo docker rm -f vllm-bench >/dev/null 2>&1 || true
  sudo docker run -d --name vllm-bench --gpus all --shm-size 16g \
    -e "HUGGING_FACE_HUB_TOKEN=$HF_TOKEN" \
    -p ${{PORT}}:8000 \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    "$IMG" \
    "${{COMMON[@]}}"
}}

_wait() {{
  for i in $(seq 1 360); do
    if curl -sf "http://127.0.0.1:${{PORT}}/v1/models" >/dev/null; then
      return 0
    fi
    if ! sudo docker ps -q -f name=vllm-bench | grep -q .; then
      return 1
    fi
    sleep 10
  done
  return 1
}}

_run
if _wait; then
  echo VLLM_READY profile=fp8-kv
  exit 0
fi
sudo docker logs --tail 120 vllm-bench >&2 || true
exit 1
'''

VLLM_BENCH = r'''
set -euxo pipefail
MODEL="{model}"
PORT="{port}"
OUT="{out}"
CONC="{conc}"
. "$HOME/mc-bench/venv/bin/activate"
# Prefer vllm CLI if present in container; else use openai-compatible load via python
sudo docker exec vllm-bench vllm bench serve \
  --base-url "http://127.0.0.1:8000" \
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
  --result-filename "vllm-c${{CONC}}.json" || \
sudo docker exec vllm-bench vllm bench serve \
  --base-url "http://127.0.0.1:8000" \
  --endpoint-type openai-comp \
  --model "$MODEL" \
  --dataset-name random \
  --random-input-len 128 \
  --random-output-len 128 \
  --num-prompts $(( CONC * 5 )) \
  --max-concurrency "$CONC" \
  --request-rate inf \
  --save-result \
  --result-dir /tmp \
  --result-filename "vllm-c${{CONC}}.json" || true
sudo docker cp vllm-bench:/tmp/vllm-c${{CONC}}.json "$OUT" 2>/dev/null || \
  sudo docker logs vllm-bench 2>&1 | tail -200 > "${{OUT}}.log"
echo VLLM_BENCH_DONE
'''

SGLANG_SERVE = r'''
set -euxo pipefail
MODEL="{model}"
TP="{tp}"
PORT="{port}"
HF_TOKEN="{hf_token}"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
sudo docker rm -f sglang-bench >/dev/null 2>&1 || true
sudo docker run -d --name sglang-bench --gpus all --shm-size 16g \
  --ipc=host \
  -e "HUGGING_FACE_HUB_TOKEN=$HF_TOKEN" \
  -p ${{PORT}}:30000 \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  lmsysorg/sglang:latest \
  python3 -m sglang.launch_server \
  --model-path "$MODEL" \
  --tp-size "$TP" \
  --host 0.0.0.0 \
  --port 30000 \
  --context-length 8192
for i in $(seq 1 180); do
  if curl -sf "http://127.0.0.1:${{PORT}}/health" >/dev/null || curl -sf "http://127.0.0.1:${{PORT}}/v1/models" >/dev/null; then
    echo SGLANG_READY
    exit 0
  fi
  sleep 10
done
sudo docker logs --tail 100 sglang-bench >&2
exit 1
'''

SGLANG_BENCH = r'''
set -euxo pipefail
MODEL="{model}"
PORT="{port}"
OUT="{out}"
CONC="{conc}"
. "$HOME/mc-bench/venv/bin/activate"
pip install -q "sglang[all]" 2>/dev/null || pip install -q sglang
python3 -m sglang.bench_serving \
  --backend sglang \
  --host 127.0.0.1 \
  --port "$PORT" \
  --model "$MODEL" \
  --dataset-name random \
  --random-input-len 128 \
  --random-output-len 128 \
  --num-prompts $(( CONC * 5 )) \
  --max-concurrency "$CONC" \
  --request-rate inf \
  --output-file "$OUT" || \
python3 -m sglang.bench_serving \
  --backend sglang \
  --host 127.0.0.1 \
  --port "$PORT" \
  --model "$MODEL" \
  --dataset-name random \
  --random-input 128 \
  --random-output 128 \
  --num-prompts $(( CONC * 5 )) \
  --max-concurrency "$CONC" \
  --request-rate inf | tee "$OUT"
echo SGLANG_BENCH_DONE
'''

STOP_ENGINES = r'''
sudo docker rm -f vllm-bench sglang-bench >/dev/null 2>&1 || true
echo STOPPED
'''
