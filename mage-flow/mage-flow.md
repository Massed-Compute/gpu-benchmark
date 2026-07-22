# Mage-Flow GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute text-to-image benches for **microsoft/Mage-Flow**.

## Technique
Official `mage_flow.MageFlowPipeline` from [microsoft/Mage](https://github.com/microsoft/Mage) (`mage_flow/` package). Attention backend forced to **SDPA** (FlashAttention build unavailable on these images). Timed 1024×1024 gens at **20 steps** (5 repeats after warmup).

## Results

| SKU | $/hr | Res | Gen latency mean (s) | Images/s | Peak VRAM (GB) |
|---|---:|---|---:|---:|---:|
| `gpu_1x_pro_6000_blackwell` | 2.19 | 1024x1024 | 3.277 | 0.305 | 18.9 |
| `gpu_1x_l40s` | 0.88 | 1024x1024 | 5.733 | 0.174 | 18.7 |

### Screenshots

Word-free T2I showcase stills (product photo of a ceramic cup). Prompt locked to no text/letters/watermark. Latency numbers above are from timed multi-seed bench runs.

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr · mean gen **3.277** s

![1xBlackwell t2i](./images/1xBlackwell-t2i-showcase.png)

**gpu_1x_l40s** — L40S 48GB — $0.88/hr · mean gen **5.733** s

![1xL40S t2i](./images/1xL40S-t2i-showcase.png)

## Conclusion

Fastest mean latency: **3.277 s** on `gpu_1x_pro_6000_blackwell`.

## Notes
- Not loadable via stock Diffusers `DiffusionPipeline`; requires Microsoft Mage package.
- Torch **cu129** required for Blackwell; L40S used cu126.
- Numbers from live Massed runs 2026-07-22; disposable bench VMs terminated after capture.

---

[![Massed Compute](../shared-images/logo-horizontal-on-light.png)](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)

**[LAUNCH GPU OR CPU INSTANCE](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)**

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.
