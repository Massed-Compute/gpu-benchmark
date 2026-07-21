# Qwen3-VL-4B Heretic GPU Benchmark

### Last Edit Date:
MC - 2026.07.21

## Purpose
Live Massed Compute vLLM benches for **DreamFast/Qwen3-VL-4b-Heretic** (Qwen3-VL 4B vision-language, transformers weights — not ComfyUI-only).

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headlines use **c32**.
Engine: **vLLM** (`nightly`) with `--trust-remote-code --max-model-len 4096`. Text-decode throughput bench (MM image limit 0).
Script: `scripts/wave4/remote_heretic.sh`.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm | `gpu_1x_pro_6000_blackwell` | 2.19 | 3481.8 | 72.5 | 1589.9 |
| vllm | `gpu_1x_h100` | 2.73 | 3942.1 | 78.5 | 1444.0 |

### Screenshots

**gpu_1x_pro_6000_blackwell** — $2.19/hr

vllm:
![gpu_1x_pro_6000_blackwell vllm](./images/1xBlackwell-vllm-showcase.png)

**gpu_1x_h100** — $2.73/hr

vllm:
![gpu_1x_h100 vllm](./images/1xH100-vllm-showcase.png)

## Conclusion

Peak c32 output throughput: **3942 tok/s** on `gpu_1x_h100` with **vllm**.
Best $/tok: **1589.9 tok/s per $** on `gpu_1x_pro_6000_blackwell` / **vllm**.

## Notes
- VL weights served via vLLM; bench is text-only random prompts for comparable decode throughput.
- Numbers from live Massed runs 2026-07-21; wave4 bench VMs terminated after capture.
