# Qwen3.8 27B OBLITERATED GPU Benchmark

### Last Edit Date:
MC - 2026.08.31

## Purpose
Live Massed Compute inference benches for **OBLITERATUS/Qwen3.8-27B-OBLITERATED** (exact BF16, ~27B, native VL). Official weights, text-decode throughput profile (MM image limit 0).

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 16 / 32 / 64. Headlines use **c32**.

Engine: **vLLM** `vllm/vllm-openai:v0.27.1`, `--max-model-len 8192 --kv-cache-dtype fp8 --reasoning-parser qwen3 --limit-mm-per-prompt '{"image":0}'`.

- **1× DGX A100** (`gpu_1x_DGX_A100`, $1.38/hr): default `--max-num-seqs`.
- **1× RTX PRO 6000 Blackwell** (`gpu_1x_pro_6000_blackwell`, $2.19/hr): `--max-num-seqs 256 --gpu-memory-utilization 0.95` (Mamba cache block cap).
- **1× H100** (`gpu_1x_h100`, $2.73/hr): same `--max-num-seqs 256` cap.

Exact BF16 does not fit 48 GB. No official FP8 checkpoint, so L40S was not a same-weights row. SGLang not captured this wave.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ | $/1M out tokens |
|---|---|---:|---:|---:|---:|---:|
| vllm | `gpu_1x_DGX_A100` | 1.38 | 616.2 | 954.9 | 446.5 | 0.622 |
| vllm | `gpu_1x_pro_6000_blackwell` | 2.19 | 623.5 | 639.2 | 284.7 | 0.976 |
| vllm | `gpu_1x_h100` | 2.73 | 745.0 | 569.2 | 272.9 | 1.018 |

### Screenshots

**gpu_1x_DGX_A100** — $1.38/hr

vllm — 616.2 output tok/s @ c32:
![gpu_1x_DGX_A100 vllm](./images/1xA100-vllm-showcase.png)

**gpu_1x_pro_6000_blackwell** — $2.19/hr

vllm — 623.5 output tok/s @ c32:
![gpu_1x_pro_6000_blackwell vllm](./images/1xBlackwell-vllm-showcase.png)

**gpu_1x_h100** — $2.73/hr

vllm — 745.0 output tok/s @ c32:
![gpu_1x_h100 vllm](./images/1xH100-vllm-showcase.png)

## Conclusion

Peak c32 output throughput: **745 tok/s** on `gpu_1x_h100` with **vllm**.
Best tok/s per $: **446.5** on `gpu_1x_DGX_A100` / **vllm**.

A100 and Blackwell are within **1.2%** on c32 throughput (616.2 vs 623.5). Blackwell costs more per hour; H100 buys **+21%** tok/s vs A100 and the lowest TTFT (569 ms).

## Notes
- Exact published BF16 (~54 GB). 1× L40S skipped — not a same-checkpoint row.
- Hopper/Blackwell default `max_num_seqs=1024` died on Mamba cache (H100 333 blocks, Blackwell 594). Cap 256.
- A100 c32 (616.2) sits 0.38% from stock Qwen3.8-27B BF16 on the same SKU (613.8). That stock page documents `--max-model-len 8192 --reasoning-parser qwen3 --limit-mm-per-prompt` with no `--kv-cache-dtype`; this page sets **fp8 KV** on every row. The comparison is indicative, not a controlled A/B.
- Numbers from live Massed runs 2026-08-31; bench VMs terminated after capture.
- Raw: `results/raw/qwen3.8-27b-obliterated/`.

> [!WARNING]
> **Disclaimer.** This page is a Massed Compute speed-and-cost bench for `OBLITERATUS/Qwen3.8-27B-OBLITERATED`. We did not train these weights. The checkpoint is an uncensored derivative of Qwen3.8-27B — stock refusal filters have been removed. Publishing tok/s here is not an endorsement of unrestricted use. If you launch it, you are responsible for prompts, outputs, and downstream use. Author terms: [Hugging Face model card](https://huggingface.co/OBLITERATUS/Qwen3.8-27B-OBLITERATED).

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
