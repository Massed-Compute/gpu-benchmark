# Qwen-Image-2.1 GPU Benchmark

### Last Edit Date:
MC - 2026.09.29

## Purpose
Live Massed Compute text-to-image benches for [Qwen/Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) (BF16, Qwen Research License). Official diffusers weights, not a GGUF fork.

## Technique
Diffusers `QwenImage21Pipeline` from git `4ac08e940880fa906c36b944a42f420db4e24b26` (`0.41.0.dev0`), transformers `5.17.0`, torch `2.11.0`. Weights stay resident in BF16 on the GPU. Each resolution gets a 2-step warmup, then five timed calls at **40 steps** (the count in the model card). The clock is `torch.cuda.synchronize()` around `pipe()`. CUDA wheel is **cu126** on A6000 and L40S, and **cu128** on RTX PRO 6000 Blackwell. Runner: `scripts/qwen-image-2.1/remote_bench.sh`.

## Results

| SKU | $/hr | Res | Gen latency mean (s) | Images/s | Peak VRAM (GiB) |
|---|---:|---|---:|---:|---:|
| `gpu_1x_a6000` | 0.57 | 1024×1024 | 29.480 | 0.034 | 39.28 |
| `gpu_1x_a6000` | 0.57 | 2048×2048 | OOM | — | — |
| `gpu_1x_l40s` | 0.97 | 1024×1024 | 16.517 | 0.061 | 39.14 |
| `gpu_1x_l40s` | 0.97 | 2048×2048 | OOM | — | — |
| `gpu_1x_pro_6000_blackwell` | 2.19 | 1024×1024 | 9.278 | 0.108 | 39.41 |
| `gpu_1x_pro_6000_blackwell` | 2.19 | 2048×2048 | 51.053 | 0.020 | 64.44 |

Peak VRAM is the max `nvidia-smi` memory.used sample during that resolution’s timed runs, divided by 1024. `$/hr` is the live list rate on 2026-09-29. L40S list rate on capture date **$0.97/hr** (rate rose from $0.88 on 2026-09-08).

### Screenshots

1024×1024 still from the first timed run. Prompt: ceramic espresso cup on sunlit oak, shallow depth of field, no text in the image.

**gpu_1x_a6000** — RTX A6000 48GB — $0.57/hr · mean gen **29.480** s · 40 steps · 1024×1024

![1xA6000 t2i](./images/1xA6000-diffusers-showcase.png)

**gpu_1x_l40s** — L40S 48GB — $0.97/hr · mean gen **16.517** s · 40 steps · 1024×1024

![1xL40S t2i](./images/1xL40S-diffusers-showcase.png)

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr · mean gen **9.278** s · 40 steps · 1024×1024

![1xBlackwell t2i](./images/1xBlackwell-diffusers-showcase.png)

## Conclusion

At 1024×1024, lowest cost per still is the L40S at **$0.00445** ($0.97/hr × 16.517 s), versus **$0.00467** on the A6000 and **$0.00564** on Blackwell. L40S is **1.78×** the A6000. Blackwell’s mean is **9.278 s** (**3.18×** the A6000, **1.78×** the L40S) and is the speed card, not the value card.

2048×2048 does not fit on the 48GB A6000 or L40S (allocation failed; 1024 already used about **39 GiB**). Blackwell’s 2048 mean is **51.053 s**, **$0.0311** per still. A same-day `gpu_1x_DGX_A100` run also finished 2048 (see below). That card is not in the table.

## Notes
- Visual stack is a 7B DiT plus a Qwen3-VL text encoder. Full BF16 load at 1024 used about **39 GiB**, so 32GB cards were not launched.
- `gpu_1x_a6000_spot` ($0.50/hr) and `gpu_1x_a6000_low_ram` ($0.55/hr) were not launched. Among the three cards in the table, L40S is the lowest cost per 1024 still.
- 2048 OOM on A6000 and L40S is the failed `pipe()` after the 1024 runs succeeded. No CPU offload.

### Same-day checks

Same runner, same prompt, same 40 steps. Not mixed into the table.

`gpu_1x_l40` at **$0.86/hr**, cu126. 1024 mean **27.647** s, **0.036** img/s, peak VRAM **39.14 GiB**, **$0.00660** per still. 2048 OOM. More per still than the A6000 and the L40S.

1536×1536: A6000 and L40S OOM. Blackwell mean **25.650** s, peak VRAM **49.21 GiB** (`nvidia-smi` max 50393 MiB / 1024), **$0.0156** per still.

`gpu_1x_DGX_A100` at **$1.38/hr**, cu126. 1024 mean **14.783** s, peak VRAM **39.45 GiB**, **$0.00567** per still. 2048 mean **77.988** s, peak VRAM **64.25 GiB**, **$0.0299** per still. The 1024 still costs more than the L40S row. The 2048 still costs less than the Blackwell 2048 row and takes longer.
- `results/raw/qwen-image-2.1/<sku>/nvidia-smi.txt` is a full `nvidia-smi` taken while a 1024 run was on GPU. The table’s 2048 peak comes from the same 2-second query log stored in `bench.json`.
- Numbers from live Massed runs 2026-09-29.

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
