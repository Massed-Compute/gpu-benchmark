# Llama 3.1 Nemotron Nano 8B GPU Benchmark

### Last Edit Date:
MC - 2026.07.16

## Purpose
Live Massed Compute inference benches for **nvidia/Llama-3.1-Nemotron-Nano-8B-v1**, comparing **vLLM** vs **SGLang**.

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headlines use **c32**.
Engines: vLLM (`v0.8.5` and/or `cu129-nightly`) + SGLang `lmsysorg/sglang:latest`.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT mean/med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm | `gpu_1x_pro_6000_blackwell` | 2.19 | 2166.1 | 142.5 | 989.1 |
| sglang | `gpu_1x_pro_6000_blackwell` | 2.19 | 1606.4 | 37.6 | 733.5 |
| vllm | `gpu_1x_h100` | 2.73 | 2387.8 | 107.2 | 874.6 |
| sglang | `gpu_1x_h100` | 2.73 | 1939.4 | 28.6 | 710.4 |

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

Peak c32 output throughput: **2388 tok/s** on `gpu_1x_h100` with **vllm**.
Best $/tok: **989.1 tok/s per $** on `gpu_1x_pro_6000_blackwell` / **vllm**.

## Notes

- Blackwell used vLLM `cu129-nightly` (sm_120); H100 used `v0.8.5`.
- H100 wins raw tok/s; Blackwell wins tok/s per dollar.
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
