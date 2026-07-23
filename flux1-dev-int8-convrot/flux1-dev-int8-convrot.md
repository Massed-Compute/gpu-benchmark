# FLUX.1-dev INT8 ConvRot GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute text-to-image benches for **SearchingMan/FLUX.1-dev-ConvRot** (INT8 ConvRot packing of FLUX.1-dev).

## Technique
ComfyUI timed gens: **20 steps**, **1024×1024**, euler. Headline = mean latency over timed seeds (warmup excluded).

## Results

| SKU | $/hr | Res | Gen latency mean (s) | Images/s | Peak VRAM (GB) |
|---|---:|---|---:|---:|---:|
| `gpu_1x_pro_6000_blackwell` | 2.19 | 1024×1024 | 4.110 | 0.243 | 20.6 |
| `gpu_1x_h200_nvl` | 3.62 | 1024×1024 | 4.008 | 0.250 | 20.7 |

### Screenshots

Word-free T2I showcase stills from the timed runs: compact accelerator product photo, no text / logo / watermark. Packing bench — not a new base model.

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr · mean gen **4.110** s · 20 steps · 1024×1024

![1xBlackwell t2i](./images/1xBlackwell-t2i-showcase.png)

**gpu_1x_h200_nvl** — H200 NVL 141GB — $3.62/hr · mean gen **4.008** s · 20 steps · 1024×1024

![1xH200 t2i](./images/1xH200-t2i-showcase.png)

## Conclusion

Fastest mean: **4.008 s** on `gpu_1x_h200_nvl` (~**0.250** images/s). Blackwell is nearly as fast at lower $/hr (**4.110 s**, **0.243** images/s).

## Notes
- Native ComfyUI INT8 ConvRot packing of FLUX.1-dev.
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
