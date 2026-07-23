# Atlas-Coder-2 0.5B GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute benches for **Siddh07ETH/Atlas-Coder-2-0.5B** (PEFT adapter merged onto Qwen2.5-Coder-0.5B-Instruct).

## Technique
Merge LoRA (`remote_atlas_merge.sh`) → transformers `generate` single-stream (128 new tokens, 5 repeats after warmup). vLLM rejected adapter-only weights.

| Published SKU | Script | Attention |
|---|---|---|
| `gpu_1x_a6000` | `scripts/wave5/remote_atlas_a6000.sh` | **SDPA** (`attn_implementation="sdpa"`) |
| `gpu_1x_pro_6000_blackwell` | `scripts/wave5/remote_atlas_tf.sh` | **default** (no `attn_implementation`) |

These two rows are **not the same attention config** — do not treat tok/s as an apples-to-apples GPU-only comparison.

## Results

| Engine | SKU | $/hr | Decode tok/s | tok/s per $ |
|---|---|---:|---:|---:|
| transformers+SDPA | `gpu_1x_a6000` | 0.57 | 27.1 | 47.5 |
| transformers (default attn) | `gpu_1x_pro_6000_blackwell` | 2.19 | 149.0 | 68.0 |

### Screenshots

Terminal-style captures from live Massed runs 2026-07-22 (transformers single-stream, not T2I).

**gpu_1x_a6000** — RTX A6000 48GB — $0.57/hr

transformers + SDPA (PEFT merged) · single-stream **27.1** tok/s:
![gpu_1x_a6000](./images/1xA6000-transformers-showcase.png)

**gpu_1x_pro_6000_blackwell** — RTX PRO 6000 Blackwell 96GB — $2.19/hr

transformers default attn (PEFT merged) · single-stream **149.0** tok/s:
![gpu_1x_pro_6000_blackwell](./images/1xBlackwell-transformers-showcase.png)

## Conclusion

Peak decode among published rows: **149 tok/s** on `gpu_1x_pro_6000_blackwell` (default attn).
Entry SKU: **27.1 tok/s** on `gpu_1x_a6000` with SDPA (**47.5 tok/s per $**).

## Notes
- HF repo is PEFT adapter; merged onto `Qwen/Qwen2.5-Coder-0.5B-Instruct` before bench.
- Transformers path only (c8/c32 N/A without a serving engine that loads the merged weights).
- Fabricated H200 duplicate-run raw was removed; not published.
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
