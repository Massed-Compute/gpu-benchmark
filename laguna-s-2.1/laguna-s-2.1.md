# Laguna S 2.1 NVFP4 GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute inference benches for **poolside/Laguna-S-2.1-NVFP4**.

## Technique
Pinned profile where supported: random prompts, input=128, output=128, concurrency 1/8/32 (headline c32). Alternate engines noted in Results.

## Results

| Engine | SKU | $/hr | Output tok/s | TTFT med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm | `gpu_2x_pro_6000_blackwell` | 4.38 | 1202.1 | 161.6 | 274.4 |

### Screenshots

Terminal-style captures from live Massed runs 2026-07-22.

**gpu_2x_pro_6000_blackwell** — 2x RTX PRO 6000 Blackwell 96GB — $4.38/hr

vLLM · `poolside/Laguna-S-2.1-NVFP4` · c32 **1202.1** tok/s · TTFT med **161.6** ms:
![gpu_2x_pro_6000_blackwell vllm](./images/2xBlackwell-vllm-showcase.png)

## Conclusion

Peak throughput: **1202 tok/s** on `gpu_2x_pro_6000_blackwell`.
Best $/tok: **274.4 tok/s per $** on `gpu_2x_pro_6000_blackwell`.

## Notes
- 118B-A8B MoE; BF16 OOM on 2×96GB — shipped **NVFP4** quant.
- `gpu_2x_h200_nvl` launch failed (capacity/billing); single SKU this wave.
- Numbers from live Massed runs 2026-07-22; disposable bench VMs terminated after capture.

---

[![Massed Compute](../shared-images/logo-horizontal-on-light.png)](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)

**[LAUNCH GPU OR CPU INSTANCE](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)**

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.
