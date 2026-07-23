# Laguna XS.2 GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute inference benches for **poolside/Laguna-XS.2** (33B-A3B MoE).

## Technique
vLLM serving bench: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headline = **c32 output tok/s**.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm | `gpu_1x_pro_6000_blackwell` | 2.19 | 1102.8 | 153.4 | 503.6 |
| vllm | `gpu_1x_h200_nvl` | 3.62 | 2405.8 | 93.7 | 664.6 |

### Screenshots

Terminal-style vLLM serving-bench captures (input=128, output=128, concurrency 1/8/32), Massed Compute 2026-07-22.

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr

vLLM · `poolside/Laguna-XS.2` · c32 **1102.8** output tok/s · TTFT med **153.4** ms:
![gpu_1x_pro_6000_blackwell vllm](./images/1xBlackwell-vllm-showcase.png)

**gpu_1x_h200_nvl** — H200 NVL 141GB — $3.62/hr

vLLM · same checkpoint · c32 **2405.8** output tok/s · TTFT med **93.7** ms:
![gpu_1x_h200_nvl vllm](./images/1xH200-vllm-showcase.png)

## Conclusion

Peak c32: **2406 tok/s** on `gpu_1x_h200_nvl`.
Best $/tok: **664.6 tok/s per $** on `gpu_1x_h200_nvl` (~2.2× Blackwell throughput for ~1.7× $/hr).

## Notes
- 33B-A3B MoE (Apache-2.0) for local/agentic coding.
- Pair: mid-tier Blackwell + H200 NVL to show scale-up.
- Numbers from live Massed runs 2026-07-22; disposable bench VMs terminated after capture.


---

<p align="center">
  <a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">
    <img src="../shared-images/logo-horizontal-on-light.png" alt="Massed Compute" height="56"/>
  </a>
</p>

<p align="center">
  <strong><a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">LAUNCH GPU OR CPU INSTANCE</a></strong>
</p>

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.

