# Solar Open2 250B-A15B GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute inference benches for **nota-ai/Solar-Open2-250B-Nota-NVFP4** (NVFP4 of upstage/Solar-Open2-250B).

## Technique
Upstage `vllm-solar-open2` Docker (vLLM 0.22.0). Flags: `--tensor-parallel-size 2 --moe-backend cutlass --max-model-len 4096 --enforce-eager --disable-custom-all-reduce`. Concurrent OpenAI chat completions (`max_tokens=128`); headline = aggregate **output tok/s at concurrency 32**.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | Mean e2e latency (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| vllm-upstage | `gpu_2x_pro_6000_blackwell` | 4.38 | 592.5 | 6894.5 | 135.3 |

### Screenshots

Terminal-style serving-bench captures from live Massed runs 2026-07-22 (concurrent chat completions, not T2I).

**gpu_2x_pro_6000_blackwell** — 2× RTX PRO 6000 Blackwell 96GB — $4.38/hr

Upstage vLLM · NVFP4 · TP=2 · c32 **592.5** output tok/s:
![gpu_2x_pro_6000_blackwell vllm](./images/2xBlackwell-vllm-showcase.png)

## Conclusion

Peak c32: **592 tok/s** on `gpu_2x_pro_6000_blackwell` (**135.3 tok/s per $**).

## Notes
- Serving uses Upstage’s Solar Open2 vLLM image (`upstage/vllm-solar-open2`); stock vLLM lacks `SolarOpen2ForCausalLM`.
- NVFP4 MoE needs `--moe-backend cutlass` (not `triton`). TP=2 without expert-parallel.
- Full BF16 weights need roughly 8×80GB; NVFP4 fits 2×96GB.
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

