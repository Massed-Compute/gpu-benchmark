#!/usr/bin/env python3
"""Burn Clef systemone text-workload numbers onto a Laya-style showcase card.

Numbers come from clef-bench.json. Watermark is a separate step.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BG = (48, 10, 28)
FG = (235, 235, 235)
ACCENT = (120, 210, 160)
MUTED = (198, 190, 194)


def load_font(size: int):
    for path in (
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def render(raw_json: Path, dest: Path) -> None:
    data = json.loads(raw_json.read_text())
    text = data["text"]
    sku = data["sku"]
    prices = {"gpu_1x_A100_SXM4": "1.38", "gpu_1x_pro_6000_blackwell": "2.19"}
    if sku not in prices:
        raise SystemExit(f"no list price for {sku}")
    price = prices[sku]
    gib = text["peak_allocated_mib"] / 1024.0
    img = Image.new("RGB", (900, 228), BG)
    draw = ImageDraw.Draw(img)
    title = load_font(18)
    body = load_font(16)
    draw.text((25, 22), f"transformers  |  {sku}", font=title, fill=ACCENT)
    draw.text((25, 50), "Cloudflare/clef  |  text state", font=body, fill=FG)
    draw.text((25, 72), f"$ {price}/hr   allocated {gib:.2f} GiB", font=body, fill=MUTED)
    rows = (
        f"p50 latency   {text['latency_ms_p50']:.3f} ms",
        f"p95 latency   {text['latency_ms_p95']:.3f} ms",
        f"decisions/s   {text['decisions_per_s']:.3f}",
        "20 warmup + 200 timed  CUDA sync",
    )
    y = 112
    for line in rows:
        draw.text((25, y), line, font=body, fill=FG)
        y += 20
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, "PNG")
    print(dest)


def main() -> None:
    raw, dest = sys.argv[1:]
    render(Path(raw), Path(dest))


if __name__ == "__main__":
    main()
