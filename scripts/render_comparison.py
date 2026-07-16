#!/usr/bin/env python3
"""Render a markdown comparison table from result JSON files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_results(paths: list[Path]) -> list[dict]:
    out = []
    for p in paths:
        if p.is_dir():
            out.extend(load_results(sorted(p.rglob("*.json"))))
        else:
            out.append(json.loads(p.read_text()))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("-o", "--output", type=Path)
    args = ap.parse_args()

    rows = load_results(args.paths)
    lines = [
        "| Model | GPU | Count | SKU | $/hr | Decode tok/s (b1) | Decode tok/s (b32) | Cost efficiency (b32 tok/s per $) | Source |",
        "|---|---|---:|---|---:|---:|---:|---:|---|",
    ]
    for r in sorted(rows, key=lambda x: (x.get("model", {}).get("hf_id", ""), x.get("hardware", {}).get("gpu", ""))):
        h = r.get("hardware", {})
        m = r.get("metrics", {})
        price = h.get("price_usd_per_hour")
        d32 = m.get("decode_tok_s_b32")
        eff = f"{d32 / price:.1f}" if price and d32 else "—"
        lines.append(
            "| {model} | {gpu} | {count} | `{sku}` | {price} | {b1} | {b32} | {eff} | {src} |".format(
                model=r.get("model", {}).get("hf_id", "—"),
                gpu=h.get("gpu", "—"),
                count=h.get("count", "—"),
                sku=h.get("sku", "—"),
                price=price if price is not None else "—",
                b1=m.get("decode_tok_s_b1", "—"),
                b32=d32 if d32 is not None else "—",
                eff=eff,
                src=r.get("provenance", {}).get("source", "—"),
            )
        )

    md = "\n".join(lines) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(md)
        print(f"Wrote {args.output}")
    else:
        print(md, end="")


if __name__ == "__main__":
    main()
