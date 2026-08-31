# GLM 5.3 Flash GPU Benchmark

### Last Edit Date:
MC - 2026.08.31

## Purpose
Live Massed Compute inference benches for **zai-org/GLM-5.3-Flash** (321B MoE / 18B active, native FP8, multimodal). Official weights, text-decode throughput profile (MM image limit 0).

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 16 / 32 / 64. Headlines use **c32**.

- **4× RTX PRO 6000 Blackwell** (`gpu_4x_pro_6000_blackwell`, $8.76/hr): patched SM120 NoPE image `cstechdev/vllm:glm53-flash-nope-sm120-cu130-20260826-r1`, `--tensor-parallel-size 4 --kv-cache-dtype fp8 --max-num-seqs 64 --max-model-len 8192 --gpu-memory-utilization 0.95`.
- **8× H100 SXM5** (`gpu_8x_H100_SXM5`, $25.12/hr): official `vllm/vllm-openai:glm53-flash`, `--tensor-parallel-size 8 --kv-cache-dtype bfloat16 --max-num-seqs 256 --max-model-len 8192`.

Stock `glm53-flash` cannot serve this checkpoint on SM120 (NoPE MLA, `qk_rope_head_dim=0` vs `fp8_ds_mla` pe_dim=64). Hopper 8× H100 is the official-image path. SGLang not captured this wave.

## Results

| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ | $/1M out tokens |
|---|---|---:|---:|---:|---:|---:|
| vllm | `gpu_4x_pro_6000_blackwell` | 8.76 | 546.8 | 531.1 | 62.4 | 4.450 |
| vllm | `gpu_8x_H100_SXM5` | 25.12 | 698.0 | 321.2 | 27.8 | 9.997 |

### Screenshots

**gpu_4x_pro_6000_blackwell** — $8.76/hr

vllm — 546.8 output tok/s @ c32:
![gpu_4x_pro_6000_blackwell vllm](./images/4xBlackwell-vllm-showcase.png)

**gpu_8x_H100_SXM5** — $25.12/hr

vllm — 698.0 output tok/s @ c32:
![gpu_8x_H100_SXM5 vllm](./images/8xH100-vllm-showcase.png)

## Conclusion

Peak c32 output throughput: **698 tok/s** on `gpu_8x_H100_SXM5` with **vllm**.
Best tok/s per $: **62.4** on `gpu_4x_pro_6000_blackwell` / **vllm**.

8× H100 also hit **1824 tok/s** at c64 (not the headline). 4× Blackwell is the least expensive live fit; 8× H100 buys lower TTFT (321 vs 531 ms at c32) and more headroom.

## Notes
- Official FP8 checkpoint (~306 GiB). 8× Blackwell / 8× H200 had no capacity at capture (large tier skipped).
- Stock `vllm/vllm-openai:glm53-flash` loads on 4× Blackwell then dies (`pe_dim must be 64 for fp8_ds_mla`). 4× numbers use the SM120 NoPE overlay image above.
- Hopper KV is **bfloat16** (this model has no FP8 KV on Hopper). Blackwell overlay uses **fp8**.
- Numbers from live Massed runs 2026-08-31; bench VMs terminated after capture.

---

[![Massed Compute](../shared-images/logo-horizontal-on-light.png)](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)

**[LAUNCH GPU OR CPU INSTANCE](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)**

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.
