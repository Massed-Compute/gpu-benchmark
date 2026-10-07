#!/usr/bin/env python3
"""Burn c1/c8/c32 output throughput from vllm bench JSON onto a showcase PNG."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from watermark_showcase import watermark

BG = (42, 10, 28)
FG = (235, 230, 232)
ACCENT = (120, 210, 170)
MUTED = (190, 160, 175)


def load_font(size: int):
    for path in (
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def row(path: Path, conc: int) -> dict:
    data = json.loads((path / f"vllm-c{conc}.json").read_text())
    return {
        "conc": conc,
        "out": data["output_throughput"],
        "ttft": data["median_ttft_ms"],
        "tpot": data["median_tpot_ms"],
    }


def max_model_len(raw_dir: Path) -> str:
    versions = raw_dir / "versions.txt"
    if versions.is_file():
        for line in versions.read_text().splitlines():
            key, _, value = line.partition(" ")
            if key == "max_model_len" and value.strip():
                return value.strip()
    return "8192"


def render(raw_dir: Path, sku: str, subtitle: str, dest: Path) -> None:
    rows = [row(raw_dir, c) for c in (1, 8, 32)]
    img = Image.new("RGB", (1400, 720), BG)
    draw = ImageDraw.Draw(img)
    title = load_font(36)
    body = load_font(28)
    small = load_font(22)
    draw.text((48, 36), f"vllm  |  {sku}", font=title, fill=ACCENT)
    draw.text((48, 88), subtitle, font=small, fill=MUTED)
    draw.text((48, 150), "Output token throughput", font=title, fill=FG)
    headers = ("c", "output tok/s", "median TTFT ms", "median TPOT ms")
    xs = (48, 220, 560, 980)
    y = 230
    for x, h in zip(xs, headers):
        draw.text((x, y), h, font=body, fill=ACCENT)
    y = 290
    for r in rows:
        vals = (
            str(r["conc"]),
            f"{r['out']:.1f}",
            f"{r['ttft']:.1f}",
            f"{r['tpot']:.1f}",
        )
        for x, val in zip(xs, vals):
            draw.text((x, y), val, font=body, fill=FG)
        y += 64
    draw.text(
        (48, 560),
        f"c32 is the headline. Prefix cache off. max-model-len {max_model_len(raw_dir)}.",
        font=small,
        fill=MUTED,
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, "PNG")
    watermark(dest, REPO_ROOT / "shared-images" / "mark-watermark-white.png")
    print(dest)


def main() -> None:
    raw, sku, subtitle, dest = sys.argv[1:]
    render(Path(raw), sku, subtitle, Path(dest))


if __name__ == "__main__":
    main()
