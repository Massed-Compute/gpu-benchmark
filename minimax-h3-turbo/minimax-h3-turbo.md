# MiniMax-H3 Turbo GPU Benchmark

### Last Edit Date:
MC - 2026.09.04

## Purpose
Live Massed Compute benches for **[lightx2v/Minimax-h3-Turbo](https://huggingface.co/lightx2v/Minimax-h3-Turbo)** on **MiniMaxAI/MiniMax-H3** FL2VA via LightX2V (`minimax_h3` T2AV). Headline path: **4-step v1.2 768p** LoRA (1344×768, 124 frames, 24 fps, ~5 s clip with stereo audio). Studio path: **8-step v1.0 768p**.

This is a distilled LoRA on the native H3 checkpoint, not the earlier vLLM-Omni / ComfyUI H3 series.

## Technique
- Engine: LightX2V `python -m lightx2v.infer --model_cls minimax_h3 --task t2av`
- Checkpoint: official repo-root `transformer/` + `text_encoder/` + `vae/` (not nested `FL2VA/` Diffusers keys)
- LoRA: `minimax_h3_fl2v_turbo_4step_v1.2_768p_bf16` (alpha 128); studio row uses `…_8step_v1.0_768p`
- Offload: block CPU offload, TE block offload, VAE offload, `lazy_load=false`, `attn_type=torch_sdpa`
- Prompt: rewriter 8B (Qwen3-VL) then locked smoke (GPU module on a desk, seed **42**)
- `video_flow_shift=6`, `audio_flow_shift=3`

Addons on disk (keep box): Turbo 4/8-step + Ref2VA 4/8, Turbo-SLA, rewriter 8B + 27B, SeedVR2-3B.

## Results

**Speed winner:** `gpu_1x_pro_6000_blackwell` — 208 s warm 4-step, **1.55×** A100.

**Value winner:** `gpu_1x_DGX_A100` — **$0.12**/clip vs Blackwell **$0.13**.

**Unexpected:** Peak VRAM is only ~17 GiB. The floor is **host RAM** (~125 GiB for native transformer + Qwen3-VL TE). Ticket cheapest-fit `gpu_1x_a6000` is 48 GiB RAM; mid `gpu_1x_l40s` is 72 GiB. Neither can load this engine. Cheapest card that actually ran is A100 (120 GiB RAM).

Warm 4-step 768p T2AV (live list $/hr 2026-09-04):

| SKU | $/hr | Warm e2e (s) | Peak VRAM | VRAM total | $/clip | Status |
|---|---:|---:|---:|---:|---:|---|
| `gpu_1x_a6000` | 0.57 | — | — | 48 GiB | — | Not launched — 48 GiB host RAM is below the L40S fail |
| `gpu_1x_l40s` | 0.97 | — | — | 48 GiB | — | Fail — 72 GiB host RAM; SSH wedged while pinning weights |
| `gpu_1x_DGX_A100` | 1.38 | **322.0** | 17.0 GiB | 80 GiB | **0.12** | OK |
| `gpu_1x_pro_6000_blackwell` | 2.19 | **208.0** | 17.2 GiB | 96 GiB | **0.13** | OK |

Same clip, 8-step studio LoRA:

| SKU | Warm e2e (s) | Peak VRAM | $/clip |
|---|---:|---:|---:|
| `gpu_1x_DGX_A100` | 375.3 | 17.0 GiB | 0.14 |
| `gpu_1x_pro_6000_blackwell` | 236.3 | 17.2 GiB | 0.14 |

Blackwell is **1.55×** faster than A100 on 4-step. Peak VRAM with block offload is ~17 GiB of 96 GiB — that leftover is the plugin headroom (extra LoRAs, 27B rewriter, SeedVR2 4K). A100 is the least expensive row that actually ran. Turbo-SLA was **not** timed: Sol-Attn is not in this image (sdpa dense fallback still raises).

### Screenshots

**gpu_1x_DGX_A100** — $1.38/hr — 4-step Turbo 768p

LightX2V — 322.0 s warm e2e, 17.0 GiB peak:
![gpu_1x_DGX_A100 lightx2v](./images/1xA100-lightx2v-showcase.png)

**gpu_1x_pro_6000_blackwell** — $2.19/hr — 4-step Turbo 768p

LightX2V — 208.0 s warm e2e, 17.2 GiB peak:
![gpu_1x_pro_6000_blackwell lightx2v](./images/1xBlackwell-lightx2v-showcase.png)

## Notes
- Native LightX2V weights live at repo root (`diffusion_pytorch_model-*-of-00014.safetensors`). Nested `FL2VA/` Diffusers keys (`proj_in.weight` missing) will not load. Ticket named the ComfyUI 4-step file; this capture is LightX2V + `minimax_h3_fl2v_turbo_4step_v1.2_768p_bf16` so every SKU uses the same engine.
- `gpu_1x_a6000` (48 GiB RAM, live $0.57/hr, cap 73) was not launched: 1× L40S already failed the same workload with **more** host RAM.
- Setup: fresh image 184 + coupon, ~12 min to `DONE_WEIGHTS` on a second Blackwell, ~20 min launch-to-first-OK 4-step clip. First ladder hung SSH (pinned TE+transformer) and was replaced.
- Attention on this Massed image is `torch_sdpa` (no flash_attn3 / sageattention / Sol-Attn). SLA LoRA failed import.
- Cold 4-step: A100 326.6 s, Blackwell 190.9 s.
- Footage: output clips + watermarked stills (no separate screen-record of launch). Blackwell `results/raw/minimax-h3-turbo/gpu_1x_pro_6000_blackwell/warm_4step.mp4`. A100 still: `minimax-h3-turbo/images/1xA100-lightx2v-showcase.png`.
- Capture 2026-09-04. Disposable L40S/A100 VMs terminated. **1× RTX PRO 6000 Blackwell kept** (`mc-bench-h3turbo-bw2`) for the addon stack — user override vs ticket “terminate all `mc-bench-*`”.

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
