# Mage-Flow GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute text-to-image benches for **microsoft/Mage-Flow**.

## Technique
Official `mage_flow.MageFlowPipeline` from [microsoft/Mage](https://github.com/microsoft/Mage). SDPA attention backend. Timed **1024×1024** gens at **20 steps** (5 repeats after a 4-step warmup).

## Results

| SKU | $/hr | Res | Gen latency mean (s) | Images/s | Peak VRAM (GB) |
|---|---:|---|---:|---:|---:|
| `gpu_1x_l40s` | 0.88 | 1024×1024 | 5.733 | 0.174 | 18.7 |
| `gpu_1x_pro_6000_blackwell` | 2.19 | 1024×1024 | 3.277 | 0.305 | 18.9 |

### Screenshots

Word-free T2I showcase stills from the timed runs: ceramic espresso cup on sunlit oak, shallow depth of field, no text / logo / watermark.

**gpu_1x_l40s** — L40S 48GB — $0.88/hr · mean gen **5.733** s · 20 steps · 1024×1024

![1xL40S t2i](./images/1xL40S-t2i-showcase.png)

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr · mean gen **3.277** s · 20 steps · 1024×1024

![1xBlackwell t2i](./images/1xBlackwell-t2i-showcase.png)

## Conclusion

Fastest mean: **3.277 s** on `gpu_1x_pro_6000_blackwell` (~1.75× L40S).
Best latency per dollar: **L40S** at $0.88/hr.

## Notes
- Requires the Microsoft Mage package (not stock Diffusers `DiffusionPipeline`).
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

