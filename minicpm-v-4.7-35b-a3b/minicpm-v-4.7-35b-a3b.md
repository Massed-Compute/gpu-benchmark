# MiniCPM-V-4.7-35B-A3B GPU Benchmark

### Last Edit Date:
MC - 2026.10.19

## Purpose
Live Massed Compute vLLM benches for [openbmb/MiniCPM-V-4.7-35B-A3B](https://huggingface.co/openbmb/MiniCPM-V-4.7-35B-A3B) revision `896c2d454672476a7b45dcc5e3f0c700a0218577`. Architecture `MiniCPMV4_7ForConditionalGeneration` (`minicpmv4_7`). The repo ships no modeling Python, and vLLM 0.32.0 registers that class, so the server does not pass `--trust-remote-code`. Weights are BF16. Measured safetensors are **70,425,903,448** bytes (**65.59 GiB**). The timed requests are text completions. The server is started with `--limit-mm-per-prompt '{"image": 1}'` so the multimodal loader stays on the path this page credits.

## Technique
Pinned profile: `vllm bench serve`, backend openai, `/v1/completions`, random prompts, input=128, output=128, `ignore-eos`, request-rate=inf, concurrency 1 / 8 / 32. Prompts per row are concurrency times 5. Headlines use **c32** **Output token throughput**. The clock is client wall time against one long-lived server, including HTTP.

Engine is vLLM **0.32.0** (torch 2.13.0+cu130, CUDA 13.0). Prefix cache off. `--max-model-len 8192 --gpu-memory-utilization 0.92 --max-num-batched-tokens 16384`. Tensor parallel is 1. Runner: `scripts/minicpm-v-4.7-35b-a3b/remote.sh`.

Only one SKU completed this profile. Blackwell is forced to `--attention-backend TRITON_ATTN` with fp8 KV. Blackwell has no FlashAttention candidate, and the FlashInfer XQA kernel is missing. A100 was forced to Triton with bfloat16 KV, because SM80 cannot store fp8 KV on Triton or FlashAttention and FlashInfer’s JIT needs nvcc. H100 was forced to `FLASH_ATTN` with fp8 KV so the server would use FA3 instead of the FlashInfer JIT.

## Results

| Engine | SKU | Quant/KV | Attention | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ | $/1M out tokens |
|---|---|---|---|---:|---:|---:|---:|---:|
| vllm 0.32.0 | `gpu_1x_pro_6000_blackwell` | bf16 / fp8 | Triton (forced) | 2.19 | 1018.8 | 183.7 | 465.2 | 0.597 |

`$/hr` is the live list rate on 2026-10-19. tok/s per $ is c32 output tok/s divided by `$/hr`. `$/1M` is `$/hr × 1,000,000 / (output tok/s × 3600)`. Derived columns use the c32 rate rounded to one decimal, the same figure in the table.

### Screenshots

Serving-bench card from the raw JSON (input=128, output=128, concurrency 1/8/32).

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr

vLLM · Triton (forced) · BF16 · fp8 KV · c32 **1018.8** output tok/s · TTFT med **183.7** ms:
![gpu_1x_pro_6000_blackwell vllm](./images/1xBlackwell-vllm-showcase.png)

## Conclusion

The smallest card at 80GB or above that held this model at the published 8192 profile is **`gpu_1x_pro_6000_blackwell`** (96GB) at **$2.19/hr**. Its c32 output throughput is **1018.8** tok/s, **465.2** tok/s per $, **$0.597** per 1M output tokens.

Both 80GB cards that were launched failed before the bench. `gpu_1x_A100_SXM4` at **$1.38/hr** OOMed during engine init (bf16 KV). `gpu_1x_h100` at **$2.73/hr** loaded the weights (**65.65 GiB**) with FlashAttention and fp8 KV, then reported no memory left for KV cache blocks. There is no completed 80GB row to set beside Blackwell. Blackwell is the only finished capture, so it is also the throughput and value figure for this page.

Concurrency 1 output tok/s on Blackwell: **148.0**. The c32 row completed 160 prompts and failed 0.

## Notes
- `nvidia-smi` memory.used on Blackwell while the server was up, divided by 1024: **82.78 GiB** of **95.59 GiB**.
- `gpu_1x_A100_SXM4` did not write `DONE`. CUDA OOM during init. The caching allocator’s device total was **85,093,777,408** bytes. Failure log: `results/raw/minicpm-v-4.7-35b-a3b/gpu_1x_A100_SXM4/bf16-vllm-oom/serve-attempt1.log`.
- `gpu_1x_h100` did not write `DONE`. After load, vLLM raised `ValueError: No available memory for the cache blocks`, with a CUDA OOM while allocating KV. The allocator device total was **85,017,493,504** bytes. Failure log: `results/raw/minicpm-v-4.7-35b-a3b/gpu_1x_h100/bf16-vllm-oom/serve-attempt1.log`. No shorter `--max-model-len` retry was run. The published profile stays 8192.
- 48GB cards were not launched. `gpu_1x_h100_nvl` at **$3.11/hr** was in stock and was not launched. `gpu_1x_h200_nvl` had no capacity.
- Numbers from live Massed runs 2026-10-19; bench VMs terminated after capture.

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
