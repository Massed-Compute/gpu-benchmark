#!/usr/bin/env python3
"""Generate Wave5 writeups + showcase PNGs from results/raw."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from mc_bench.screenshot import (  # noqa: E402
    build_tgi_style_tables,
    from_vllm_style_runs,
    render_showcase_png,
)

FOOTER = (ROOT / "docs/writeup-footer.md").read_text().split("```markdown")[1].split("```")[0].strip()

SKU_META = {
    "gpu_1x_pro_6000_blackwell": ("1xBlackwell", 2.19, "RTX PRO 6000 Blackwell 96GB"),
    "gpu_1x_h100": ("1xH100", 2.73, "H100 80GB PCIe"),
    "gpu_1x_h200_nvl": ("1xH200", 3.62, "H200 NVL 141GB"),
    "gpu_2x_pro_6000_blackwell": ("2xBlackwell", 4.38, "2x RTX PRO 6000 Blackwell 96GB"),
    "gpu_2x_h200_nvl": ("2xH200", 7.24, "2x H200 NVL 141GB"),
}


def metric(d: dict, *keys, default=0.0):
    for k in keys:
        if k in d and d[k] is not None:
            return float(d[k])
    return float(default)


def write_llm(slug: str, title: str, hf: str, notes: list[str], skus: list[str]):
    raw = ROOT / "results/raw" / slug
    img_dir = ROOT / slug / "images"
    img_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    shot_blocks = []
    for sku in skus:
        label, price, gpu = SKU_META[sku]
        runs = {}
        for c in (1, 8, 32):
            p = raw / sku / f"vllm-c{c}.json"
            if p.exists():
                runs[c] = json.loads(p.read_text())
        if 32 not in runs:
            continue
        by = from_vllm_style_runs(runs)
        table = build_tgi_style_tables(title=f"{hf} | {sku} | vllm", by_batch=by)
        shot = img_dir / f"{label}-vllm-showcase.png"
        render_showcase_png(f"{title} — {label} / vllm", table, shot)
        tok = metric(runs[32], "output_throughput")
        ttft = metric(runs[32], "median_ttft_ms", "mean_ttft_ms")
        eff = tok / price if price else 0
        rows.append((sku, price, tok, ttft, eff, label, gpu))
        shot_blocks.append(
            f"**{sku}** — {gpu} — ${price}/hr\n\n"
            f"vLLM nightly · `{hf}` · c32 **{tok:.1f}** output tok/s · TTFT med **{ttft:.1f}** ms:\n"
            f"![{sku} vllm](./images/{label}-vllm-showcase.png)\n"
        )
    if not rows:
        print("skip empty", slug)
        return
    best = max(rows, key=lambda r: r[2])
    best_eff = max(rows, key=lambda r: r[4])
    table_md = "| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ |\n|---|---|---:|---:|---:|---:|\n"
    for sku, price, tok, ttft, eff, *_ in rows:
        table_md += f"| vllm | `{sku}` | {price} | {tok:.1f} | {ttft:.1f} | {eff:.1f} |\n"
    md = f"""# {title} GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute inference benches for **{hf}**.

## Technique
Pinned profile: random prompts, input=128, output=128, request-rate=inf, concurrency 1 / 8 / 32. Headlines use **c32**.
Engine: **vLLM** (`nightly`) with `--trust-remote-code --max-model-len 4096`.

## Results

{table_md}
### Screenshots

Terminal-style vLLM serving-bench captures (input=128, output=128, concurrency 1/8/32), Massed Compute 2026-07-22.

{chr(10).join(shot_blocks)}
## Conclusion

Peak c32 output throughput: **{best[2]:.0f} tok/s** on `{best[0]}` with **vllm**.
Best $/tok: **{best_eff[4]:.1f} tok/s per $** on `{best_eff[0]}` / **vllm**.

## Notes
{chr(10).join(f'- {n}' for n in notes)}
- Numbers from live Massed runs 2026-07-22; bench VMs terminated after capture.

{FOOTER}
"""
    out = ROOT / slug / f"{slug}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(md)
    print("wrote", out)


def write_t2i(slug: str, title: str, hf: str, notes: list[str], skus: list[str], packing_note: str = ""):
    raw = ROOT / "results/raw" / slug
    img_dir = ROOT / slug / "images"
    img_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    shot_blocks = []
    for sku in skus:
        label, price, gpu = SKU_META[sku]
        meta_p = raw / sku / "t2i-bench.json"
        if not meta_p.exists():
            continue
        meta = json.loads(meta_p.read_text())
        mean = float(meta.get("mean_latency_s") or 0)
        ips = float(meta.get("images_per_s") or (1 / mean if mean else 0))
        vram = float(meta.get("peak_vram_gb") or 0)
        res = f"{meta.get('width', '?')}x{meta.get('height', '?')}"
        src = raw / sku / "showcase.png"
        dest = img_dir / f"{label}-t2i-showcase.png"
        if src.exists():
            dest.write_bytes(src.read_bytes())
        rows.append((sku, price, res, mean, ips, vram, label, gpu, meta.get("steps")))
        shot_blocks.append(
            f"**{sku}** — {gpu} — ${price}/hr · mean gen **{mean:.3f}** s\n\n"
            f"![{label} t2i](./images/{label}-t2i-showcase.png)\n"
        )
    if not rows:
        print("skip empty", slug)
        return
    table_md = "| SKU | $/hr | Res | Gen latency mean (s) | Images/s | Peak VRAM (GB) |\n|---|---:|---|---:|---:|---:|\n"
    for sku, price, res, mean, ips, vram, *_ in rows:
        table_md += f"| `{sku}` | {price} | {res} | {mean:.3f} | {ips:.3f} | {vram:.1f} |\n"
    lead = packing_note or "Word-free T2I showcase stills (product photo). Prompt locked to no text/letters/watermark."
    md = f"""# {title} GPU Benchmark

### Last Edit Date:
MC - 2026.07.22

## Purpose
Live Massed Compute text-to-image benches for **{hf}**.

## Technique
Diffusers / ComfyUI timed multi-seed gens; headline = mean latency (warm excluded where applicable).

## Results

{table_md}
### Screenshots

{lead} Latency numbers above are from timed multi-seed bench runs.

{chr(10).join(shot_blocks)}
## Conclusion

Fastest mean latency: **{min(rows, key=lambda r: r[3])[3]:.3f} s** on `{min(rows, key=lambda r: r[3])[0]}`.

## Notes
{chr(10).join(f'- {n}' for n in notes)}
- Numbers from live Massed runs 2026-07-22; bench VMs terminated after capture.

{FOOTER}
"""
    out = ROOT / slug / f"{slug}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(md)
    print("wrote", out)


if __name__ == "__main__":
    write_llm(
        "nanbeige4-2-3b",
        "Nanbeige4.2 3B",
        "Nanbeige/Nanbeige4.2-3B",
        ["Small agentic claim model; Apache-2.0."],
        ["gpu_1x_pro_6000_blackwell", "gpu_1x_h200_nvl"],
    )
    write_llm(
        "atlas-coder-2-0.5b",
        "Atlas-Coder-2 0.5B",
        "Siddh07ETH/Atlas-Coder-2-0.5B",
        ["Sub-1B coding model from Qwen2.5-Coder-0.5B-Instruct."],
        ["gpu_1x_pro_6000_blackwell", "gpu_1x_h200_nvl"],
    )
    write_llm(
        "laguna-xs-2",
        "Laguna XS.2",
        "poolside/Laguna-XS.2",
        ["33B-A3B MoE; local/agentic coding contender."],
        ["gpu_1x_pro_6000_blackwell", "gpu_1x_h200_nvl"],
    )
    write_llm(
        "solar-open2-250b-a15b",
        "Solar Open2 250B-A15B",
        "upstage/Solar-Open2-250B",
        ["250B-A15B Hybrid-Attention MoE; agentic; claimed near DeepSeek V4 Flash.",
         "Engine: Upstage vLLM fork + NVFP4 on 2× Blackwell."],
        ["gpu_2x_pro_6000_blackwell", "gpu_2x_h200_nvl"],
    )
    write_llm(
        "laguna-s-2.1",
        "Laguna S 2.1",
        "poolside/Laguna-S-2.1",
        ["118B-A8B MoE agentic coding contender."],
        ["gpu_2x_pro_6000_blackwell", "gpu_2x_h200_nvl"],
    )
    write_t2i(
        "mage-flow",
        "Mage-Flow",
        "microsoft/Mage-Flow",
        ["4B MIT T2I foundation (image gen/edit)."],
        ["gpu_1x_pro_6000_blackwell", "gpu_1x_h200_nvl"],
        packing_note="Word-free T2I showcase stills (product photo of a compact accelerator). Prompt locked to no text/letters/watermark.",
    )
    write_t2i(
        "flux1-dev-int8-convrot",
        "FLUX.1-dev INT8 ConvRot",
        "SearchingMan/FLUX.1-dev-ConvRot",
        ["Native ComfyUI INT8 ConvRot packing of FLUX.1-dev — not a new base model."],
        ["gpu_1x_pro_6000_blackwell", "gpu_1x_h200_nvl"],
        packing_note="Word-free T2I showcase stills. Packing bench (INT8 ConvRot), not a new architecture.",
    )
