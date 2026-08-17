# DeepSeek V4 Flash 0731 GPU Benchmark

### Last Edit Date:
MC - 2026.08.04

## Purpose
Live Massed Compute inference benches for **deepseek-ai/DeepSeek-V4-Flash-0731** (official Flash release; ~304B MoE, FP8+packed experts). Speculative decoding (DSpark) was **not** live on the timed run — CUDA-graph capture OOMed with the draft attached.

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headlines use **c32** sustained **Output token throughput** (not Peak).
Engine: **SGLang** (`lmsysorg/sglang:latest`) `--tp 4 --moe-runner-backend flashinfer_mxfp4 --context-length 2048 --mem-fraction-static 0.80 --cuda-graph-backend-decode disabled --disable-custom-all-reduce`.
vLLM nightly blocked on SM120 (see Notes).

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ |
|---|---|---:|---:|---:|---:|
| sglang | `gpu_4x_pro_6000_blackwell` | 8.76 | 238.7 | 233.3 | 27.2 |

### Screenshots

**gpu_4x_pro_6000_blackwell** — $8.76/hr

sglang — 238.7 output tok/s @ c32 (sustained):
![gpu_4x_pro_6000_blackwell sglang](./images/4xBlackwell-sglang-showcase.png)

## Conclusion

On this run, **gpu_4x_pro_6000_blackwell** with **sglang** delivered **~238.7** output tok/s at **$8.76/hr** (~**27.2** tok/s per $/hr).

## Notes
- Official **DeepSeek-V4-Flash-0731** (MIT; supersedes preview). ~304B MoE / FP8+packed experts (~167GB download). DSpark draft was attempted but **not enabled** on the timed run (`no DSPARK (OOM on graph)` in `summary.json`).
- Engine: **SGLang** (`lmsysorg/sglang:latest`) with `--moe-runner-backend flashinfer_mxfp4`, `--tp 4`, `--context-length 2048`, `--cuda-graph-backend-decode disabled`, `--disable-custom-all-reduce`.
- **vLLM nightly** could not load on RTX PRO 6000 Blackwell (**SM120**): DeepGEMM hits `Unknown SF transformation` / `Unsupported architecture`; official MegaMoE path requires **SM100** (B200/GB300). No B200 capacity at capture time.
- Ladder attempts: `1x H200` OOM (~138 GiB weights); `2x Blackwell` SGLang OOM after load; `4x Blackwell` succeeded.
- vs preview page `../deepseek-v4-flash/deepseek-v4-flash.md`: preview vLLM on 2×Blackwell was **514.4** tok/s c32 at **$4.38/hr** (**117.4** tok/s per $). This official release is **238.7** at **$8.76/hr** (**27.2** per $) — roughly 2× the cost for under half the throughput (~4× worse $/tok efficiency). Different model + engine, SM120 forcing SGLang with decode CUDA graphs disabled and no DSpark; publish that plainly rather than comparing peak-SGLang to sustained-vLLM.
- Live Massed runs 2026-08-04; bench VMs terminated after capture.

## Raw
- `results/raw/deepseek-v4-flash-0731/gpu_4x_pro_6000_blackwell/20260804T162952Z/`
- Failure logs: `gpu_1x_h200_nvl/`, `gpu_2x_pro_6000_blackwell/`, earlier `gpu_4x_*` attempts

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
