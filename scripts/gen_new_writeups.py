#!/usr/bin/env python3
"""Generate llama-3.1-style writeups + TGI showcase PNGs for the new
DeepSeek + newest-local model benches, matching the shipped format."""
from __future__ import annotations

import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mc_bench.screenshot import (  # noqa: E402
    build_tgi_style_tables,
    from_vllm_style_runs,
    render_showcase_png,
)

RAW = ROOT / "results" / "raw"

SKU_LABEL = {
    "gpu_1x_pro_6000_blackwell": "1xBlackwell",
    "gpu_1x_h100": "1xH100",
    "gpu_2x_pro_6000_blackwell": "2xBlackwellPRO6000",
    "gpu_2x_h200_nvl": "2xH200",
}
PRICES = {
    "gpu_1x_pro_6000_blackwell": 2.19,
    "gpu_1x_h100": 2.73,
    "gpu_2x_pro_6000_blackwell": 4.38,
    "gpu_2x_h200_nvl": 7.24,
}

MODELS = [
    {
        "slug": "deepseek-r1-distill-llama-8b",
        "hf": "deepseek-ai/DeepSeek-R1-Distill-Llama-8B",
        "title": "DeepSeek R1 Distill Llama 8B",
        "skus": ["gpu_1x_pro_6000_blackwell", "gpu_1x_h100"],
        "notes": [
            "Reasoning distill of Llama 3.1 8B; single-GPU class.",
            "Blackwell + H100 both ran vLLM `cu129-nightly`.",
        ],
    },
    {
        "slug": "deepseek-r1-distill-qwen-32b",
        "hf": "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
        "title": "DeepSeek R1 Distill Qwen 32B",
        "skus": ["gpu_1x_pro_6000_blackwell", "gpu_1x_h100"],
        "notes": [
            "Reasoning distill on Qwen2.5 32B; fits one 80–96GB card at bf16.",
        ],
    },
    {
        "slug": "qwen3-32b",
        "hf": "Qwen/Qwen3-32B",
        "title": "Qwen3 32B",
        "skus": ["gpu_1x_pro_6000_blackwell", "gpu_1x_h100"],
        "notes": [
            "Dense Qwen3 32B; newest Qwen generation.",
        ],
    },
    {
        "slug": "qwen3-30b-a3b",
        "hf": "Qwen/Qwen3-30B-A3B",
        "title": "Qwen3 30B-A3B (MoE)",
        "skus": ["gpu_1x_pro_6000_blackwell", "gpu_1x_h100"],
        "notes": [
            "MoE with ~3B active params — very high throughput per card.",
        ],
    },
    {
        "slug": "deepseek-r1-distill-llama-70b",
        "hf": "deepseek-ai/DeepSeek-R1-Distill-Llama-70B",
        "title": "DeepSeek R1 Distill Llama 70B",
        "skus": ["gpu_2x_pro_6000_blackwell", "gpu_2x_h200_nvl"],
        "notes": [
            "Reasoning distill of Llama 3.3 70B; needs 2 GPUs (TP=2).",
            "2x Blackwell vs 2x H200 NVL comparison.",
        ],
    },
]


def latest_dir(slug: str, sku: str) -> Path | None:
    base = RAW / slug / sku
    if not base.exists():
        return None
    subs = sorted([p for p in base.iterdir() if p.is_dir()])
    return subs[-1] if subs else None


def load_runs(slug: str, sku: str, engine: str) -> dict[int, dict]:
    d = latest_dir(slug, sku)
    runs: dict[int, dict] = {}
    if not d:
        return runs
    for c in (1, 8, 32):
        f = d / f"{engine}-c{c}.json"
        if f.exists():
            try:
                data = json.loads(f.read_text())
            except Exception:
                continue
            if "output_throughput" not in data and "output_token_throughput" in data:
                data["output_throughput"] = data["output_token_throughput"]
            runs[c] = data
    return runs


def metric(d: dict, *keys):
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return 0


def gen_model(m: dict):
    out_dir = ROOT / m["slug"]
    img_dir = out_dir / "images"
    img_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    for sku in m["skus"]:
        label = SKU_LABEL[sku]
        price = PRICES[sku]
        for eng in ("vllm", "sglang"):
            runs = load_runs(m["slug"], sku, eng)
            if not runs:
                print(f"  WARN no {eng} runs for {m['slug']} {sku}")
                continue
            by = from_vllm_style_runs(runs)
            table = build_tgi_style_tables(title=f"{m['hf']} | {sku} | {eng}", by_batch=by)
            shot = img_dir / f"{label}-{eng}-showcase.png"
            render_showcase_png(f"{m['title']} — {label} / {eng}", table, shot)
            c32 = runs.get(32, {})
            tok = float(metric(c32, "output_throughput", "output_token_throughput"))
            ttft = float(metric(c32, "median_ttft_ms", "mean_ttft_ms"))
            eff = tok / price if price else 0
            rows.append((eng, sku, label, price, tok, ttft, eff))

    if not rows:
        print(f"SKIP {m['slug']} (no data)")
        return False

    best = max(rows, key=lambda r: r[4])
    best_eff = max(rows, key=lambda r: r[6])

    lines = [
        f"# {m['title']} GPU Benchmark",
        "",
        "### Last Edit Date:",
        f"MC - {date.today().strftime('%Y.%m.%d')}",
        "",
        "## Purpose",
        f"Live Massed Compute inference benches for **{m['hf']}**, comparing **vLLM** vs **SGLang**.",
        "",
        "## Technique",
        "Pinned profile: random prompts, input=128, output=128, request-rate=inf, "
        "concurrency 1 / 8 / 32. Headlines use **c32**.",
        "Engines: vLLM (`cu129-nightly`) + SGLang `lmsysorg/sglang:latest`.",
        "",
        "## Results",
        "",
        "| Engine | SKU | $/hr | Output tok/s (c32) | TTFT med (ms) | tok/s per $ |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for eng, sku, label, price, tok, ttft, eff in rows:
        lines.append(f"| {eng} | `{sku}` | {price} | {tok:.1f} | {ttft:.1f} | {eff:.1f} |")

    lines += ["", "### Screenshots", ""]
    for sku in m["skus"]:
        label = SKU_LABEL[sku]
        lines.append(f"**{sku}** — ${PRICES[sku]}/hr")
        lines.append("")
        for eng in ("vllm", "sglang"):
            shot = out_dir / "images" / f"{label}-{eng}-showcase.png"
            if shot.exists():
                lines.append(f"{eng}:")
                lines.append(f"![{sku} {eng}](./images/{label}-{eng}-showcase.png)")
                lines.append("")

    lines += [
        "## Conclusion",
        "",
        f"Peak c32 output throughput: **{best[4]:.0f} tok/s** on `{best[1]}` with **{best[0]}**.",
        f"Best $/tok: **{best_eff[6]:.1f} tok/s per $** on `{best_eff[1]}` / **{best_eff[0]}**.",
        "",
        "## Notes",
        "",
    ]
    for n in m["notes"]:
        lines.append(f"- {n}")
    lines.append("- Numbers from live Massed runs 2026-07-16; bench VMs terminated after capture.")
    lines.append("")

    (out_dir / f"{m['slug']}.md").write_text("\n".join(lines))
    print(f"wrote {m['slug']}.md ({len(rows)} engine-sku rows)")
    return True


def update_readme(done_slugs):
    readme = ROOT / "README.md"
    text = readme.read_text()
    entries = {
        "deepseek-r1-distill-llama-8b": "[DeepSeek R1 Distill Llama 8B (Blackwell vs H100)](./deepseek-r1-distill-llama-8b/deepseek-r1-distill-llama-8b.md)",
        "deepseek-r1-distill-qwen-32b": "[DeepSeek R1 Distill Qwen 32B (Blackwell vs H100)](./deepseek-r1-distill-qwen-32b/deepseek-r1-distill-qwen-32b.md)",
        "qwen3-32b": "[Qwen3 32B (Blackwell vs H100)](./qwen3-32b/qwen3-32b.md)",
        "qwen3-30b-a3b": "[Qwen3 30B-A3B MoE (Blackwell vs H100)](./qwen3-30b-a3b/qwen3-30b-a3b.md)",
        "deepseek-r1-distill-llama-70b": "[DeepSeek R1 Distill Llama 70B (2x Blackwell vs 2x H200)](./deepseek-r1-distill-llama-70b/deepseek-r1-distill-llama-70b.md)",
    }
    new_lines = [f"- {entries[s]}" for s in done_slugs if s in entries]
    block = "## DeepSeek + Newest Local (2026) — vLLM + SGLang\n\n" + "\n".join(new_lines) + "\n\n"
    if "## DeepSeek + Newest Local" in text:
        text = re.sub(r"## DeepSeek \+ Newest Local.*?(?=\n## )", block, text, flags=re.S)
    else:
        # insert after the New (2026) block, before "## How we run" if present
        anchor = "## How we run"
        if anchor in text:
            text = text.replace(anchor, block + anchor)
        else:
            text = text.rstrip() + "\n\n" + block
    readme.write_text(text)
    print("README updated")


def update_catalog(done_slugs):
    p = ROOT / "catalog" / "models.json"
    cat = json.loads(p.read_text())
    for model in cat["models"]:
        if model["id"] in done_slugs:
            model["status"] = "complete"
    cat["updated"] = "2026-07-16"
    p.write_text(json.dumps(cat, indent=2) + "\n")
    print("catalog updated")


if __name__ == "__main__":
    done = []
    for m in MODELS:
        if gen_model(m):
            done.append(m["slug"])
    if done:
        update_readme(done)
        update_catalog(done)
    print("done:", done)
