# MAR-74 footage — 2026-09-02

Same locked 5.04 s Distilled clip on L40S, A100, Blackwell. Overlay wall time and $/clip in MAR-85 post; do not bake a logo into the generate.

| File | What |
|---|---|
| `L40S-clip.mp4` | Warm mux (timed run) |
| `A100-clip.mp4` | Warm mux (timed run) |
| `Blackwell-clip.mp4` | Warm mux (timed run) |
| `L40S-clip-timer.mp4` | Same + SKU / wall / $/clip burned in |
| `A100-clip-timer.mp4` | Same |
| `Blackwell-clip-timer.mp4` | Same |
| `../gpu_1x_l40s/launch-nvidia-smi.txt` | Launch GPU identity |
| `../gpu_1x_l40s/gen-nvidia-smi.txt` | Mid-generate util (100%, 343 W, 42.97 GiB). A100 has this file too; Blackwell does not. |
| `../gpu_1x_l40s/warm.vram.csv` | 1 Hz VRAM + util during warm |
| `../gpu_1x_DGX_A100/` | Same launch-nvidia-smi + gen-nvidia-smi + warm.vram.csv |
| `../gpu_1x_pro_6000_blackwell/` | launch-nvidia-smi + warm.vram.csv only (no gen-nvidia-smi.txt) |
