# Qwen-Image-2.1 GPU Benchmark

### Last Edit Date:
MC - 2026.09.21

## Purpose
Live Massed Compute text-to-image benches for [Qwen/Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) (BF16, Qwen Research License).

## Technique
Diffusers `QwenImage21Pipeline` from git `7263f3317f6b392d62f41e9d75ed9d7e21fc5a5c` (`0.41.0.dev0`), transformers `5.17.0`, torch `2.11.0`. Weights stay resident in BF16 on the GPU. Each resolution gets a 2-step warmup, then five timed calls at **40 steps** (the count in the model card). The clock is `torch.cuda.synchronize()` around `pipe()`. CUDA wheel is **cu126** on A6000 and A100, and **cu128** on RTX PRO 6000 Blackwell. Runner: `scripts/qwen-image-2.1/remote_bench.sh`.

## Results

| SKU | $/hr | Res | Gen latency mean (s) | Images/s | Peak VRAM (GB) |
|---|---:|---|---:|---:|---:|
| `gpu_1x_a6000` | 0.57 | 1024×1024 | 29.646 | 0.034 | 39.28 |
| `gpu_1x_a6000` | 0.57 | 2048×2048 | OOM | — | — |
| `gpu_1x_a100` | 1.35 | 1024×1024 | 15.626 | 0.064 | 39.45 |
| `gpu_1x_a100` | 1.35 | 2048×2048 | 83.044 | 0.012 | 64.25 |
| `gpu_1x_pro_6000_blackwell` | 2.19 | 1024×1024 | 9.307 | 0.107 | 39.41 |
| `gpu_1x_pro_6000_blackwell` | 2.19 | 2048×2048 | 51.784 | 0.019 | 64.44 |

Peak VRAM is the max `nvidia-smi` memory.used sample during that resolution’s timed runs, divided by 1024. `$/hr` is the live rate on 2026-09-21.

### Screenshots

1024×1024 still from the first timed run. Prompt: ceramic espresso cup on sunlit oak, shallow depth of field, no text in the image.

**gpu_1x_a6000** — RTX A6000 48GB — $0.57/hr · mean gen **29.646** s · 40 steps · 1024×1024

![1xA6000 t2i](./images/1xA6000-diffusers-showcase.png)

**gpu_1x_a100** — A100 80GB — $1.35/hr · mean gen **15.626** s · 40 steps · 1024×1024

![1xA100 t2i](./images/1xA100-diffusers-showcase.png)

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr · mean gen **9.307** s · 40 steps · 1024×1024

![1xBlackwell t2i](./images/1xBlackwell-diffusers-showcase.png)

## Conclusion

At 1024×1024, Blackwell’s mean is **9.307 s** (**1.6×** the A100, **3.1×** the A6000). Lowest cost per 1024 image is the A6000 at **$0.0047** ($0.57/hr × 29.646 s), versus **$0.0057** on Blackwell and **$0.0059** on the A100.

2048×2048 does not fit on the 48GB A6000 (allocation failed; 1024 already used **39.28 GB**). On the two cards that finished, Blackwell’s mean is **51.784 s** (**1.6×** the A100’s **83.044 s**). Cost per 2048 image is **$0.0311** on the A100 and **$0.0315** on Blackwell.

## Notes
- Visual stack is a 7B DiT plus a Qwen3-VL text encoder. Full BF16 load at 1024 used about **39 GB**, so 32GB and 24GB cards were not launched.
- `gpu_1x_h100` had no capacity on 2026-09-21. A100 is the 80GB row.
- 2048 OOM on A6000 is the failed `pipe()` after the 1024 runs succeeded. No CPU offload.
- `results/raw/qwen-image-2.1/<sku>/nvidia-smi.txt` is a full `nvidia-smi` taken while a 1024 run was on GPU. The table’s 2048 peaks come from the same 2-second query log stored in `bench.json`.
- Numbers from live Massed runs 2026-09-21.

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
