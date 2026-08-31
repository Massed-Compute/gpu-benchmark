# LTX 2.5 GPU Benchmark

### Last Edit Date:
MC - 2026.08.31

## Purpose
Live Massed Compute benches for **Lightricks/LTX-2.5** distilled two-stage text-to-video (audio+video). Official `ltx-pipelines.distilled` path, exact BF16 split pack. Disposable `mc-bench-ltx25-*` VMs only.

## Technique
Engine: `uv sync --extra natten` from [Lightricks/LTX-2](https://github.com/Lightricks/LTX-2), `python -m ltx_pipelines.distilled`. Checkpoint: `ltx-2.5-22b-distilled-transformer-bf16` + Gemma 4 12B TE + DiffVAE + audio VAE + spatial x2 upscaler (~66 GiB on disk). Native BF16, no `fp8-cast`, no CPU offload flag.

Locked clip (same on every SKU): **1536×1024**, **121 frames**, **24 fps** (5.041667 s), seed **42**. Stage 1 is 8 steps at 768×512; stage 2 is 3 steps at 1536×1024. Image 184, driver **580.126.16**.

Headline metric: **warm end-to-end wall** (second clip on a loaded process). Peak VRAM is `nvidia-smi memory.used` sampled at 1 Hz, not the Python allocator.

Locked prompt:
> A compact GPU accelerator module on a clean desk in soft daylight, camera slowly pushes in, quiet fan whir and room tone, no text no logos no watermarks.

## Results

Catalog `$/hr` from live inventory 2026-08-31. `$/clip` = warm wall × `$/hr` ÷ 3600.

| SKU | $/hr | Warm e2e (s) | Cold (s) | Peak VRAM | $/clip | Clips/hr | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| `gpu_1x_l40s` | 0.88 | **106.698** | 108.169 | 43.83 GiB | **0.026** | 33.7 | OK |
| `gpu_1x_DGX_A100` | 1.38 | 90.296 | 95.302 | 47.05 GiB | 0.035 | 39.9 | OK |
| `gpu_1x_pro_6000_blackwell` | 2.19 | **54.688** | 59.160 | 47.27 GiB | 0.033 | **65.8** | OK |

Smallest Massed fit that returned a valid 121-frame mux: **1× L40S (48 GB)** at **$0.88/hr**. Peak sat at **97%** of the card (44877 / 46068 MiB). Blackwell is **1.95×** faster than L40S on the warm clip; A100 sits in between. Best catalog `$/clip` is L40S. Fastest wall is Blackwell.

All three muxes: H.264 1536×1024, 121 frames, 24 fps, AAC stereo ~5.01 s.

### Smoke clips

These **are** the timed warm runs (H.264 + AAC, 1536×1024, 121 frames, 24 fps, seed 42). Same prompt on every SKU. Preview still is a frame from that clip; the link under it is the full smoke MP4.

**1× L40S** — $0.88/hr — DistilledPipeline — warm **106.7 s** / **$0.026** per clip.

[![1× L40S smoke preview](./images/1xL40S-distilled-showcase.png)](./images/1xL40S-distilled-smoke.mp4)

[1× L40S smoke clip (mp4)](./images/1xL40S-distilled-smoke.mp4)

**1× DGX A100** — $1.38/hr — DistilledPipeline — warm **90.3 s** / **$0.035** per clip.

[![1× A100 smoke preview](./images/1xA100-distilled-showcase.png)](./images/1xA100-distilled-smoke.mp4)

[1× A100 smoke clip (mp4)](./images/1xA100-distilled-smoke.mp4)

**1× RTX PRO 6000 Blackwell** — $2.19/hr — DistilledPipeline — warm **54.7 s** / **$0.033** per clip.

[![1× Blackwell smoke preview](./images/1xBlackwell-distilled-showcase.png)](./images/1xBlackwell-distilled-smoke.mp4)

[1× Blackwell smoke clip (mp4)](./images/1xBlackwell-distilled-smoke.mp4)

## Conclusion
Start on **1× L40S** if you want the least expensive Massed SKU that actually runs this distilled BF16 pack. Pay **1× RTX PRO 6000 Blackwell** when wall-clock matters: about **66 clips/hr** vs **34** on L40S, at nearly the same `$/clip` as A100. A 80 GB A100 is not the floor and is not the speed winner.

## Notes
- This is **DistilledPipeline**, not DFR (detailing IC-LoRA) and not the full 22B dev transformer. DFR is slower and hungrier; do not divide these walls into a DFR quote.
- Disk weights are ~66 GiB (DiT 39.1 + Gemma 24.5 + VAEs/upscaler). Peak GPU is ~44–47 GiB because the official pipeline trims the text encoder after encode. That is not FP8/INT8.
- L40S did **not** need `--quantization fp8-cast --offload cpu` for this locked 5 s clip.
- Torch from `uv sync --extra natten`: **2.13.0+cu132**. Same image-184 driver on all three SKUs.
- Raw: `results/raw/ltx-2.5/`.

---

[![Massed Compute](../shared-images/logo-horizontal-on-light.png)](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)

**[LAUNCH GPU OR CPU INSTANCE](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)**

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.
