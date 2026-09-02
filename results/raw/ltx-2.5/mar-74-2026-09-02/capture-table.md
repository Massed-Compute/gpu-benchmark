# MAR-74 capture — 2026-09-02

Locked clip on every SKU: **LTX-2.5 Distilled**, 1536×1024, 121 frames, 24 fps (**5.041667 s**), seed **42**.

Prompt: A compact GPU accelerator module on a clean desk in soft daylight, camera slowly pushes in, quiet fan whir and room tone, no text no logos no watermarks.

List rates from `gpu_inventory_list` 2026-09-02 (not coupon, not remembered). Image 184, driver 580.126.16.

| SKU | $/hr list | Warm s | Cold s | VRAM | Peak util | $/clip | Clips/hr | Launch → first clip | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| L40S (`gpu_1x_l40s`) | 0.88 | **93.599** | 111.289 | 43.83 / 45.00 GiB | 100% | **0.0229** | 38.5 | 9.55 min | ok |
| DGX A100 (`gpu_1x_DGX_A100`) | 1.38 | 91.664 | 103.777 | 47.05 / 80.00 GiB | 100% | 0.0351 | 39.3 | 9.27 min | ok |
| RTX PRO 6000 Blackwell (`gpu_1x_pro_6000_blackwell`) | 2.19 | **52.925** | 61.026 | 47.27 / 95.59 GiB | 100% | 0.0322 | **68.0** | 7.90 min | ok |

`$ /clip` = warm wall × list $/hr ÷ 3600. Warm is a second process launch of the same clip (weights reload).

## Renter angle (not the speed table)

Hourly sticker is the wrong unit. The job peaks at 44–47 GiB on every card.

- **A100 is the trap.** 2% faster than L40S on warm (91.7 s vs 93.6 s), 53% more $/clip, 33 GB of empty VRAM.
- **First clip costs 6–9× a later clip** because of the ~66 GiB pull (L40S $0.14 / 9.6 min, A100 $0.21 / 9.3 min, Blackwell $0.29 / 7.9 min).
- **If a person is waiting, rent Blackwell.** Ten clips: 15.8 min / $0.58 vs L40S 23.6 min / $0.35. Extra $0.23 buys 8 minutes. Break-even human wage: **$1.80/hr**.
- **If it is an unattended batch, rent L40S.** Same mux, least dollars. A100 loses both tests.
- Wait per 1 s of output: L40S 18.6× realtime, A100 18.2×, Blackwell 10.5×.

| Clips in one sitting | L40S $ | A100 $ | Blackwell $ |
|---:|---:|---:|---:|
| 1 | 0.14 | 0.21 | 0.29 |
| 10 | 0.35 | 0.53 | 0.58 |
| 20 | 0.57 | 0.88 | 0.90 |
| 50 | 1.26 | 1.94 | 1.87 |

## Failures / changes

- uv installer returned non-zero on L40S and A100 (`~/.config/fish` mkdir permission). Binary was already installed. Restarted the script. No OOM, no `fp8-cast`, no clip change.
- Protected studio `ltx-25` left running. Disposable boxes: `mc-bench-ltx-l40s`, `mc-bench-ltx-a100`, `mc-bench-ltx-bwk`.

## Footage (for MAR-85)

See `footage/README.md`. Same 5.04 s mux on all three cards. Do not re-generate.

## Handoff

MAR-84 paste this table. MAR-85 edit from `footage/`. MAR-86 waits on the 45–90 s cut.
