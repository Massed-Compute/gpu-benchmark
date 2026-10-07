#!/usr/bin/env python3
"""Burn JEV-27B-VL System 1 text-decision numbers onto a Laya-style showcase card.

Numbers come from decide-bench.json. Watermark is a separate step.
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
PRICES = {"gpu_1x_a100": "1.35", "gpu_1x_h100": "2.73", "gpu_1x_pro_6000_blackwell": "2.19"}


def load_font(size: int):
    for path in (
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def vllm_version(raw_json: Path) -> str:
    versions = raw_json.parent / "versions.txt"
    if not versions.is_file():
        raise SystemExit(f"missing {versions}; refusing to hardcode a vLLM version")
    for line in versions.read_text().splitlines():
        parts = line.split()
        if parts and parts[0] == "vllm" and len(parts) >= 2:
            return parts[1]
    raise SystemExit(f"no vllm version in {versions}")


def render(raw_json: Path, dest: Path) -> None:
    data = json.loads(raw_json.read_text())
    sku = data["sku"]
    if sku not in PRICES:
        raise SystemExit(f"no list price for {sku}")
    version = vllm_version(raw_json)
    single = data["text"]["single"]
    c8 = data["text"]["c8"]
    img = Image.new("RGB", (900, 228), BG)
    draw = ImageDraw.Draw(img)
    title = load_font(18)
    body = load_font(16)
    draw.text((25, 22), f"vLLM {version}  |  {sku}", font=title, fill=ACCENT)
    draw.text((25, 50), "autotrust/JEV-27B-VL  |  System 1 text decision", font=body, fill=FG)
    draw.text((25, 72), f"$ {PRICES[sku]}/hr   BF16", font=body, fill=MUTED)
    rows = (
        f"p50 latency       {single['p50_ms']:.3f} ms",
        f"p95 latency       {single['p95_ms']:.3f} ms",
        f"decisions/s  c1   {single['decisions_per_s']:.3f}",
        f"decisions/s  c8   {c8['decisions_per_s']:.3f}",
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
