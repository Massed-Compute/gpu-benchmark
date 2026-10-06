#!/usr/bin/env python3
"""Burn Qwen-Image-2.1 Q8 1024 numbers onto a showcase card.

Numbers come from bench.json. Watermark is a separate step.
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
# L40S list rate rose from $0.88 to $0.97 on 2026-09-08.
PRICE = {
    "gpu_1x_a6000": "0.57",
    "gpu_1x_l40s": "0.97",
    "gpu_1x_pro_6000_blackwell": "2.19",
}


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
    row = next(r for r in data["results"] if r["width"] == 1024 and r.get("mean_s"))
    sku = data["sku"]
    gib = data["peak_vram_mib"] / 1024.0
    img = Image.new("RGB", (900, 228), BG)
    draw = ImageDraw.Draw(img)
    title = load_font(18)
    body = load_font(16)
    draw.text((25, 22), f"ComfyUI GGUF  |  {sku}", font=title, fill=ACCENT)
    draw.text((25, 50), "Q8_0  |  qwen-image-2.1-UC-Q8_0.gguf", font=body, fill=FG)
    draw.text((25, 72), f"$ {PRICE[sku]}/hr   peak {gib:.2f} GiB", font=body, fill=MUTED)
    rows = (
        f"1024 mean     {row['mean_s']:.3f} s",
        f"images/s      {row['images_per_s']:.6f}",
        "40 steps  euler  cfg 1",
        "2 warmup + 5 timed",
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
