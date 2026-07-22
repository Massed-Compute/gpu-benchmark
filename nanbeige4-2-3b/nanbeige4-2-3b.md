# Nanbeige4.2 3B GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Attempted live Massed Compute benches for **Nanbeige/Nanbeige4.2-3B**.

## Technique
Wave 5 scripts under `scripts/wave5/` (vLLM / Diffusers / transformers fallbacks).

## Results

| Status | Note |
|---|---|
| **Blocked** | Not in vLLM (`NanbeigeForCausalLM`). Transformers load fails on `rope_scaling` keys (`type`/`factor`) in published config. |

### Screenshots

No showcase — bench did not complete.

## Conclusion

Could not publish latency/tok/s numbers this wave. Revisit when engine support lands.

## Notes
- Attempted 2026-07-22 on disposable `mc-bench-w5*` VMs (image 184).
- Related SKU notes: `gpu_1x_h100` / `gpu_2x_h200_nvl` often unavailable; used Blackwell / H200 NVL substitutes where possible.

---

[![Massed Compute](../shared-images/logo-horizontal-on-light.png)](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)

**[LAUNCH GPU OR CPU INSTANCE](https://massedcompute.com/?utm_source=github.com&utm_campaign=gpu-benchmark)**

> **Pricing note:** Listed `$/hr` rates are point-in-time from the capture date. Confirm live pricing in the marketplace before you launch — rates can change. Pay only for the hours you use.
