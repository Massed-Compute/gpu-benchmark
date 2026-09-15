#!/usr/bin/env bash
# Capture runner for DeepSeek-V4.1-Flash TP8 single-stream decode.
# Expects the HF snapshot at /home/Ubuntu/models/DeepSeek-V4.1-Flash and
# scripts/deepseek-v4.1-flash/time_bench.py at /home/Ubuntu/mc-bench/time_bench.py.
set -euxo pipefail
IMG='lmsysorg/sglang@sha256:d6e7288627be8b02be88e4bba38e73f6d50e2826869f753c13a4c4385ab3eda9'
HF=/home/Ubuntu/models/DeepSeek-V4.1-Flash
TP=/home/Ubuntu/models/DeepSeek-V4.1-Flash-TP8
OUT=/home/Ubuntu/mc-bench/out
mkdir -p "$OUT"

test -f "$HF/config.json"
sudo docker image inspect "$IMG" >/dev/null

if ! sudo docker inspect dsv41-infer >/dev/null 2>&1; then
  sudo docker run -d --name dsv41-infer --gpus all --ipc=host --shm-size 32g \
    -v /home/Ubuntu/models:/models \
    -v /home/Ubuntu/mc-bench:/mc-bench \
    -w /models/DeepSeek-V4.1-Flash/inference \
    "$IMG" sleep infinity
fi

sudo docker exec dsv41-infer python3 -c 'import tilelang,sys; print(tilelang.__version__)' || \
  sudo docker exec dsv41-infer pip install -q tilelang==0.1.12 safetensors numpy sympy Pillow tqdm tokenizers transformers

sudo docker exec dsv41-infer python3 model.py | tee "$OUT/model-py.log" | tail -n 5

if [[ ! -f "$TP/model0-mp8.safetensors" ]]; then
  sudo docker exec dsv41-infer python3 convert.py \
    --hf-ckpt-path /models/DeepSeek-V4.1-Flash \
    --save-path /models/DeepSeek-V4.1-Flash-TP8 \
    --model-parallel 8 \
    --expert-dtype fp4 \
    --tokenizer-path /models/DeepSeek-V4.1-Flash | tee "$OUT/convert.log"
fi

install -m 644 /home/Ubuntu/mc-bench/time_bench.py "$HF/inference/time_bench.py"

: > "$OUT/nvidia-smi-live.txt"
( while true; do
    date -u +'%Y-%m-%dT%H:%M:%SZ' >> "$OUT/nvidia-smi-live.txt"
    nvidia-smi >> "$OUT/nvidia-smi-live.txt"
    echo '---' >> "$OUT/nvidia-smi-live.txt"
    sleep 2
  done ) &
SMI_PID=$!
trap 'kill $SMI_PID 2>/dev/null || true' EXIT

sudo docker exec -w /models/DeepSeek-V4.1-Flash/inference dsv41-infer \
  torchrun --nproc-per-node 8 /models/DeepSeek-V4.1-Flash/inference/time_bench.py \
    --ckpt-path /models/DeepSeek-V4.1-Flash-TP8 \
    --config /models/DeepSeek-V4.1-Flash/inference/config.json \
    --max-new-tokens 128 --warmup 1 --repeats 5 \
    --out /mc-bench/out/official-generate-bench.json \
    | tee "$OUT/time-bench.log"

kill "$SMI_PID" 2>/dev/null || true
cp "$OUT/nvidia-smi-live.txt" "$OUT/nvidia-smi.txt"
nvidia-smi -L > "$OUT/gpu-list.txt"
echo OK > "$OUT/DONE"
echo PIPELINE_DONE
