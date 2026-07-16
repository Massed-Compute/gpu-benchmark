"""Generate llama-3.1-style model writeups from bench summaries."""
from __future__ import annotations

import json
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def render_writeup(model_slug: str, summaries: list[dict] | None = None) -> Path:
    if summaries is None:
        latest = ROOT / "results" / "raw" / model_slug / "latest.json"
        if not latest.exists():
            # gather all sku latest folders
            summaries = []
            base = ROOT / "results" / "raw" / model_slug
            if base.exists():
                for p in sorted(base.rglob("summary.json")):
                    summaries.append(json.loads(p.read_text()))
        else:
            summaries = [json.loads(latest.read_text())]

    if not summaries:
        raise FileNotFoundError(f"No summaries for {model_slug}")

    model = summaries[0]["model"]["hf_id"]
    title_name = model.split("/")[-1].replace("-", " ")
    out_dir = ROOT / model_slug
    out_dir.mkdir(parents=True, exist_ok=True)
    md_path = out_dir / f"{model_slug}.md"

    # headline rows at conc 32
    rows = []
    for s in summaries:
        hw = s["hardware"]
        for r in s.get("results", []):
            if r.get("max_concurrency") != 32:
                continue
            m = r.get("metrics", {})
            tok = m.get("output_tok_s")
            price = hw.get("price_usd_per_hour") or 0
            eff = (tok / price) if tok and price else None
            rows.append(
                {
                    "engine": r["engine"],
                    "sku": hw["sku"],
                    "price": price,
                    "tok": tok,
                    "ttft": m.get("ttft_ms_p50") or m.get("ttft_ms_mean"),
                    "eff": eff,
                    "shot": r.get("screenshot"),
                }
            )

    lines = [
        f"# {title_name} GPU Benchmark",
        "",
        "### Last Edit Date:",
        f"MC - {date.today().strftime('%Y.%m.%d')}",
        "",
        "## Purpose",
        f"Traffic-facing inference benchmarks for **{model}** on Massed Compute GPUs, "
        "comparing modern serving engines so buyers can pick the right card.",
        "",
        "## Technique",
        "We run the same online serving workload on **[vLLM](https://github.com/vllm-project/vllm)** "
        "and **[SGLang](https://github.com/sgl-project/sglang)**.",
        "",
        "Pinned profile: random prompts, input=128, output=128, request-rate=inf, "
        "max concurrency 1 / 8 / 32. Headline tables use concurrency **32**.",
        "",
        "## Running the test",
        "",
        "```bash",
        "# vLLM",
        "docker run --gpus all --shm-size 16g -p 8000:8000 \\",
        f"  vllm/vllm-openai:v0.8.5 --model {model} --tensor-parallel-size $TP",
        "",
        "vllm bench serve --backend openai --base-url http://127.0.0.1:8000 \\",
        f"  --model {model} --dataset-name random --input-len 128 --output-len 128 \\",
        "  --num-prompts 160 --max-concurrency 32 --request-rate inf",
        "```",
        "",
        "```bash",
        "# SGLang",
        "docker run --gpus all --shm-size 16g -p 30000:30000 lmsysorg/sglang:latest \\",
        f"  python3 -m sglang.launch_server --model-path {model} --tp-size $TP --port 30000",
        "",
        "python3 -m sglang.bench_serving --backend sglang --host 127.0.0.1 --port 30000 \\",
        f"  --model {model} --dataset-name random --random-input-len 128 --random-output-len 128 \\",
        "  --num-prompts 160 --max-concurrency 32 --request-rate inf",
        "```",
        "",
        "## GPU Quantity per Type",
        "Small models use a single GPU. Large (~70B) models use 2–3 instances max "
        "(Blackwell vs H100, optional 4× L40S).",
        "",
        "## Results",
        "",
        "| Engine | SKU | $/hr | Output tok/s (c32) | TTFT p50/mean | tok/s per $ |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for r in rows:
        tok_s = r["tok"] if r["tok"] is not None else "—"
        ttft_s = r["ttft"] if r["ttft"] is not None else "—"
        eff_s = f"{r['eff']:.1f}" if r["eff"] else "—"
        lines.append(
            f"| {r['engine']} | `{r['sku']}` | {r['price']} | {tok_s} | {ttft_s} | {eff_s} |"
        )

    lines += ["", "### Per-SKU screenshots", ""]
    for r in rows:
        if r.get("shot"):
            lines += [
                f"**{r['sku']} / {r['engine']} (conc 32)**",
                f"![{r['sku']} {r['engine']}](../{r['shot']})",
                "",
            ]

    # conclusion draft
    best = None
    for r in rows:
        if r["eff"] is None:
            continue
        if best is None or r["eff"] > best["eff"]:
            best = r
    lines += ["## Conclusion", ""]
    if best:
        lines.append(
            f"On this run, **{best['sku']}** with **{best['engine']}** led cost efficiency "
            f"at ~{best['eff']:.1f} output tok/s per $/hr "
            f"(raw ~{best['tok']} tok/s at ${best['price']}/hr)."
        )
    else:
        lines.append("See results table above; fill promo callouts after reviewing metrics.")
    lines += [
        "",
        "For flagship messaging: emphasize **RTX PRO 6000 Blackwell vs H100** on multi-GPU posts, "
        "and **L40S** on single-GPU posts for value and capacity.",
        "",
        "## Future Additions",
        "More models as they release — `mc-bench run --model <hf_id>` launches, benches, "
        "writes this page, and terminates the VMs.",
        "",
    ]
    md_path.write_text("\n".join(lines))
    return md_path
