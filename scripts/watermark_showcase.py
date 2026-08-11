#!/usr/bin/env python3
"""Ghost-watermark showcase PNGs (Massed Compute gpu-benchmark recipe).

Prep mark: crop bbox → flat white on alpha.
Composite: bottom-right, height=46% of base, opacity=5%, margin=2% of base width.

Usage:
  python3 scripts/watermark_showcase.py path/to/showcase.png [...]
  python3 scripts/watermark_showcase.py --mark shared-images/mark-watermark-white.png slug/images/*.png
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def to_flat_white_mark(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    _r, _g, _b, a = im.split()
    white = Image.new("L", im.size, 255)
    return Image.merge("RGBA", (white, white, white, a))


def watermark(base_path: Path, mark_path: Path, out_path: Path | None = None) -> Path:
    base = Image.open(base_path).convert("RGBA")
    mark = to_flat_white_mark(Image.open(mark_path))
    bw, bh = base.size
    target_h = max(1, int(round(bh * 0.46)))
    aspect = mark.width / max(mark.height, 1)
    target_w = max(1, int(round(target_h * aspect)))
    mark = mark.resize((target_w, target_h), Image.Resampling.LANCZOS)
    r, g, b, a = mark.split()
    a = a.point(lambda p: int(p * 0.05))
    mark = Image.merge("RGBA", (r, g, b, a))
    margin = int(round(bw * 0.02))
    x = bw - target_w - margin
    y = bh - target_h - margin
    # Paste without mask: RGBA→RGBA paste(..., mask) collapses low alpha (~5%) to ~1
    # and the ghost mark disappears after RGB convert.
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(mark, (x, y))
    out = Image.alpha_composite(base, layer).convert("RGB")
    dest = out_path or base_path
    out.save(dest, "PNG")
    return dest


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+", type=Path)
    ap.add_argument(
        "--mark",
        type=Path,
        default=Path("shared-images/mark-watermark-white.png"),
        help="Flat white mark (or color logo to flatten)",
    )
    args = ap.parse_args()
    if not args.mark.exists():
        alt = Path("shared-images/mark.png")
        if alt.exists():
            args.mark = alt
        else:
            raise SystemExit(f"missing mark: {args.mark}")
    for img in args.images:
        dest = watermark(img, args.mark)
        print("watermarked", dest)


if __name__ == "__main__":
    main()
