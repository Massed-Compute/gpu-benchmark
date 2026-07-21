# Qwen3 30B-A3B (MoE) GPU Benchmark

### Last Edit Date:
MC - 2026.07.16

## Purpose
Live Massed Compute inference benches for **Qwen/Qwen3-30B-A3B**, comparing **vLLM** vs **SGLang**.

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headlines use **c32**.
Engines: vLLM (`cu129-nightly`) + SGLang `lmsysorg/sglang:latest`.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm | `gpu_1x_pro_6000_blackwell` | 2.19 | 1099.4 | 137.2 | 502.0 |
| sglang | `gpu_1x_pro_6000_blackwell` | 2.19 | 711.6 | 88.2 | 324.9 |
| vllm | `gpu_1x_h100` | 2.73 | 1227.3 | 135.3 | 449.5 |
| sglang | `gpu_1x_h100` | 2.73 | 859.0 | 73.3 | 314.6 |

### Screenshots

**gpu_1x_pro_6000_blackwell** — $2.19/hr

vllm:
![gpu_1x_pro_6000_blackwell vllm](./images/1xBlackwell-vllm-showcase.png)

sglang:
![gpu_1x_pro_6000_blackwell sglang](./images/1xBlackwell-sglang-showcase.png)

**gpu_1x_h100** — $2.73/hr

vllm:
![gpu_1x_h100 vllm](./images/1xH100-vllm-showcase.png)

sglang:
![gpu_1x_h100 sglang](./images/1xH100-sglang-showcase.png)

## Conclusion

Peak c32 output throughput: **1227 tok/s** on `gpu_1x_h100` with **vllm**.
Best $/tok: **502.0 tok/s per $** on `gpu_1x_pro_6000_blackwell` / **vllm**.

## Notes

- MoE with ~3B active params — very high throughput per card.
- Numbers from live Massed runs 2026-07-16; bench VMs terminated after capture.


---

<p align="center">
  <a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">
    <img src="../shared-images/logo-horizontal-on-light.png" alt="Massed Compute" height="56"/>
  </a>
</p>

<p align="center">
  <strong><a href="https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark">LAUNCH GPU OR CPU INSTANCE</a></strong>
</p>

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use; no long-term contracts.
