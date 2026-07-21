# Nemotron 3 Nano 30B-A3B GPU Benchmark

### Last Edit Date:
MC - 2026.07.16

## Purpose
Live Massed Compute inference benches for **nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-BF16**, comparing **vLLM** vs **SGLang**.

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headlines use **c32**.
Engines: vLLM (`v0.8.5` and/or `cu129-nightly`) + SGLang `lmsysorg/sglang:latest`.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT mean/med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm | `gpu_1x_pro_6000_blackwell` | 2.19 | 1058.6 | 163.7 | 483.4 |
| sglang | `gpu_1x_pro_6000_blackwell` | 2.19 | 620.7 | 122.5 | 283.4 |
| vllm | `gpu_1x_h100` | 2.73 | 1279.1 | 180.3 | 468.5 |
| sglang | `gpu_1x_h100` | 2.73 | 436.4 | 2181.2 | 159.9 |

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

Peak c32 output throughput: **1279 tok/s** on `gpu_1x_h100` with **vllm**.
Best $/tok: **483.4 tok/s per $** on `gpu_1x_pro_6000_blackwell` / **vllm**.

## Notes

- Hybrid Mamba/Transformer; H100 needed `--max-num-seqs 256` (default 1024 OOMs Mamba cache on 80GB).
- Blackwell 96GB ran defaults fine. SGLang on H100 underperformed vs vLLM at c32.
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

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use
