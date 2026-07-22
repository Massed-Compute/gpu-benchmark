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

### Screenshots

Word-free T2I showcase still from the timed run: compact accelerator product photo, no text / logo / watermark. Packing bench — not a new base model.

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr · mean gen **4.110** s · 20 steps · 1024×1024

![1xBlackwell t2i](./images/1xBlackwell-t2i-showcase.png)

## Conclusion

Mean gen latency: **4.110 s** on `gpu_1x_pro_6000_blackwell` (~**0.243** images/s).

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

