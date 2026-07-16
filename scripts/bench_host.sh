#!/usr/bin/env bash
# Usage: bench_host.sh IP SKU TP VLLM_IMAGE MODEL TAG PRICE
set -euo pipefail
KEY=${KEY:-$HOME/.ssh/songtree_massedcompute}
HF=${HF:-$(tr -d '\n' < ~/.cache/huggingface/token)}
IP=$1; SKU=$2; TP=$3; VLLM_IMAGE=$4; MODEL=$5; TAG=$6; PRICE=${7:-0}
ROOT=${ROOT:-/Users/gabemills/Developer/Projects/Active/gpu-benchmark}
OUT="$ROOT/results/raw/$TAG/$SKU/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT" "$ROOT/results/raw/logs"
LOG="$ROOT/results/raw/logs/bench-$TAG-$SKU.log"
exec > >(tee -a "$LOG") 2>&1
echo "[$(date -u +%H:%M:%S)] START $SKU $IP $MODEL image=$VLLM_IMAGE"

ssh_cmd(){ ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 "Ubuntu@$IP" "$@"; }

# bootstrap if needed
ssh_cmd bash -s <<'REMOTE'
set -euxo pipefail
if ! "$HOME/mc-bench/venv/bin/python" -c "import openai,aiohttp,numpy" 2>/dev/null; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip curl jq
  sudo systemctl enable --now docker || true
  mkdir -p "$HOME/mc-bench" "$HOME/.cache/huggingface"
  rm -rf "$HOME/mc-bench/venv"
  python3 -m venv "$HOME/mc-bench/venv"
  . "$HOME/mc-bench/venv/bin/activate"
  pip install -q -U pip wheel
  pip install -q 'openai>=1.40' aiohttp numpy
fi
echo BOOT_OK
REMOTE

# vLLM
ssh_cmd bash -s <<REMOTE
set -euo pipefail
set +x
export HUGGING_FACE_HUB_TOKEN='$HF'
set -x
sudo docker rm -f vllm-bench sglang-bench >/dev/null 2>&1 || true
sudo docker pull $VLLM_IMAGE >/dev/null
sudo docker run -d --name vllm-bench --gpus all --shm-size 16g \
  -e HUGGING_FACE_HUB_TOKEN=\$HUGGING_FACE_HUB_TOKEN \
  -p 8000:8000 \
  -v "\$HOME/.cache/huggingface:/root/.cache/huggingface" \
  $VLLM_IMAGE \
  --model '$MODEL' --tensor-parallel-size $TP --max-model-len 4096 --gpu-memory-utilization 0.90 --trust-remote-code
for i in \$(seq 1 240); do
  if curl -sf http://127.0.0.1:8000/v1/models >/dev/null; then echo VLLM_READY; exit 0; fi
  if ! sudo docker ps --format '{{.Names}}' | grep -q '^vllm-bench\$'; then sudo docker logs --tail 100 vllm-bench >&2 || true; exit 1; fi
  sleep 10
done
sudo docker logs --tail 120 vllm-bench >&2; exit 1
REMOTE

for CONC in 1 8 32; do
  echo "[$(date -u +%H:%M:%S)] vllm c$CONC"
  ssh_cmd bash -s <<REMOTE > "$OUT/vllm-c${CONC}.txt" 2>&1
set -euxo pipefail
sudo docker exec vllm-bench vllm bench serve \
  --base-url http://127.0.0.1:8000 --backend openai --endpoint /v1/completions \
  --model '$MODEL' --dataset-name random --random-input-len 128 --random-output-len 128 \
  --num-prompts \$(( $CONC * 5 )) --max-concurrency $CONC --request-rate inf \
  --save-result --result-dir /tmp --result-filename vllm-c${CONC}.json \
|| sudo docker exec vllm-bench vllm bench serve \
  --base-url http://127.0.0.1:8000 --endpoint-type openai-comp \
  --model '$MODEL' --dataset-name random --random-input-len 128 --random-output-len 128 \
  --num-prompts \$(( $CONC * 5 )) --max-concurrency $CONC --request-rate inf \
  --save-result --result-dir /tmp --result-filename vllm-c${CONC}.json || true
sudo docker cp vllm-bench:/tmp/vllm-c${CONC}.json /tmp/vllm-c${CONC}.json 2>/dev/null || true
cat /tmp/vllm-c${CONC}.json 2>/dev/null || true
echo VLLM_BENCH_DONE
REMOTE
  scp -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes "Ubuntu@$IP:/tmp/vllm-c${CONC}.json" "$OUT/vllm-c${CONC}.json" 2>/dev/null || true
done
ssh_cmd 'sudo docker rm -f vllm-bench >/dev/null 2>&1 || true'

# SGLang
ssh_cmd bash -s <<REMOTE
set -euo pipefail
set +x
export HUGGING_FACE_HUB_TOKEN='$HF'
set -x
sudo docker rm -f sglang-bench >/dev/null 2>&1 || true
sudo docker run -d --name sglang-bench --gpus all --shm-size 16g --ipc=host \
  -e HUGGING_FACE_HUB_TOKEN=\$HUGGING_FACE_HUB_TOKEN \
  -p 30000:30000 \
  -v "\$HOME/.cache/huggingface:/root/.cache/huggingface" \
  lmsysorg/sglang:latest \
  python3 -m sglang.launch_server --model-path '$MODEL' --tp-size $TP --host 0.0.0.0 --port 30000 \
  --context-length 4096 --trust-remote-code --mem-fraction-static 0.88 --disable-custom-all-reduce
for i in \$(seq 1 240); do
  if curl -sf http://127.0.0.1:30000/health >/dev/null || curl -sf http://127.0.0.1:30000/v1/models >/dev/null; then echo SGLANG_READY; exit 0; fi
  if ! sudo docker ps --format '{{.Names}}' | grep -q '^sglang-bench\$'; then sudo docker logs --tail 100 sglang-bench >&2 || true; exit 1; fi
  sleep 10
done
exit 1
REMOTE

for CONC in 1 8 32; do
  echo "[$(date -u +%H:%M:%S)] sglang c$CONC"
  ssh_cmd bash -s <<REMOTE > "$OUT/sglang-c${CONC}.txt" 2>&1
set -euxo pipefail
sudo docker exec sglang-bench python3 -m sglang.bench_serving \
  --backend sglang --base-url http://127.0.0.1:30000 --model '$MODEL' \
  --dataset-name random --random-input-len 128 --random-output-len 128 \
  --num-prompts \$(( $CONC * 5 )) --max-concurrency $CONC --request-rate inf \
  --output-file /tmp/sglang-c${CONC}.json || true
sudo docker cp sglang-bench:/tmp/sglang-c${CONC}.json /tmp/sglang-c${CONC}.json 2>/dev/null || true
cat /tmp/sglang-c${CONC}.json 2>/dev/null || true
echo SGLANG_BENCH_DONE
REMOTE
  scp -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes "Ubuntu@$IP:/tmp/sglang-c${CONC}.json" "$OUT/sglang-c${CONC}.json" 2>/dev/null || true
done
ssh_cmd 'sudo docker rm -f sglang-bench >/dev/null 2>&1 || true'
echo OUT_DIR=$OUT
echo "DONE $TAG $SKU"
