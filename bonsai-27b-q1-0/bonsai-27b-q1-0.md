# Bonsai 27B Q1_0 GPU Benchmark

### Last Edit Date:
MC - 2026.07.21

## Purpose
Live Massed Compute llama.cpp benches for **prism-ml/Bonsai-27B-gguf** `Bonsai-27B-Q1_0.gguf` (Qwen3.5 27B, ~3.8 GB 1-bit GGUF).

## Technique
`llama-bench` (CUDA docker, `-ngl 99`), profile **pp128 / tg128**, 5 repeats. Headline decode = **tg128**.
Script: `scripts/wave4/remote_bonsai.sh`.

## Results

| Engine | SKU | $/hr | Prefill tok/s (pp128) | Decode tok/s (tg128) | tok/s per $ (decode) |
|---|---|---:|---:|---:|---:|
| llama.cpp | `gpu_1x_pro_6000_blackwell` | 2.19 | 2679.4 | 155.9 | 71.2 |
| llama.cpp | `gpu_1x_h100` | 2.73 | 1808.1 | 99.3 | 36.4 |

### Screenshots

**gpu_1x_pro_6000_blackwell** — $2.19/hr

llama.cpp:
![gpu_1x_pro_6000_blackwell llamacpp](./images/1xBlackwell-llamacpp-showcase.png)

**gpu_1x_h100** — $2.73/hr

llama.cpp:
![gpu_1x_h100 llamacpp](./images/1xH100-llamacpp-showcase.png)

## Conclusion

Peak decode: **155.9 tok/s** on `gpu_1x_pro_6000_blackwell` (~**71.2 tok/s per $**).
Blackwell leads H100 on both prefill (~48% faster) and decode (~57% faster) for this Q1_0 GGUF.

## Notes
- Open HF GGUF from prism-ml; architecture reported as `qwen35 27B Q1_0`.
- Numbers from live Massed runs 2026-07-21; wave4 bench VMs terminated after capture.
