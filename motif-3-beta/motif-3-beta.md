# Motif-3-Beta GPU Benchmark (partial)

### Last Edit Date:
MC - 2026.07.21

## Purpose
Attempted live Massed Compute load of **Motif-Technologies/Motif-3-Beta** (~314B MoE / ~13B active, BF16, beta preview).

## Technique
`transformers` + `trust_remote_code` + `device_map="auto"` on **4× RTX PRO 6000 Blackwell**. Official card notes a dedicated **vLLM guide is coming soon**.

## Results

| Engine | SKU | $/hr | Load wall (cold) | VRAM reserved (sum) | Generate |
|---|---|---:|---:|---:|---|
| transformers | `gpu_4x_pro_6000_blackwell` | 8.76 | 921 s | ~382 GB | **failed** (rotary / GDLA dim mismatch) |

Load footprint (per GPU, reserved):

| GPU | reserved GB |
|---:|---:|
| 0 | 88.4 |
| 1 | 98.0 |
| 2 | 98.0 |
| 3 | 98.0 |

## Conclusion

Motif-3-Beta **fits 4× Blackwell BF16 for load**, but **inference is blocked** on this beta checkpoint with current Transformers (`apply_rotary_pos_emb_single` 64 vs 192). Revisit when Motif ships the vLLM serving guide or a fixed modeling patch.

## Notes
- Preview / beta weights — not final release.
- Numbers from live Massed attempt 2026-07-21; VM terminated after capture.


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
