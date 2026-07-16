"""Showcase screenshots in the classic Massed TGI-table style.

Matches the 2024 gpu-benchmark look: dark maroon terminal, ASCII boxes,
Prefill/Decode latency + throughput across batch sizes.
"""
from __future__ import annotations

from pathlib import Path


BG = (48, 10, 28)  # maroon/purple like original ThinLinc shots
FG = (235, 235, 235)
DIM = (180, 180, 190)
ACCENT = (120, 220, 160)


def _box(rows: list[list[str]], widths: list[int]) -> list[str]:
    def sep(left: str, mid: str, right: str, fill: str = "─") -> str:
        parts = [fill * (w + 2) for w in widths]
        return left + mid.join(parts) + right

    lines = [sep("┌", "┬", "┐")]
    for i, row in enumerate(rows):
        cells = [f" {str(c)[:widths[j]].ljust(widths[j])} " for j, c in enumerate(row)]
        lines.append("│" + "│".join(cells) + "│")
        if i == 0:
            lines.append(sep("├", "┼", "┤"))
        elif i < len(rows) - 1 and row[0] != rows[i + 1][0] and row[0] != "Step":
            # section break when step name changes
            pass
    lines.append(sep("└", "┴", "┘"))
    return lines


def build_tgi_style_tables(
    *,
    title: str,
    by_batch: dict[int, dict],
) -> str:
    """by_batch[batch] keys: prefill_lat_avg/low/high/p50/p90/p99,
    decode_tok_lat_*, decode_tot_lat_*, prefill_tok_s_*, decode_tok_s_*
    """
    batches = sorted(by_batch.keys())
    lat_header = ["Step", "Batch Size", "Average", "Lowest", "Highest", "p50", "p90", "p99"]
    thr_header = ["Step", "Batch Size", "Average", "Lowest", "Highest"]

    lat_rows = [lat_header]
    for step, prefix in [
        ("Prefill", "prefill_lat"),
        ("Decode (token)", "decode_tok_lat"),
        ("Decode (total)", "decode_tot_lat"),
    ]:
        for b in batches:
            d = by_batch[b]
            lat_rows.append(
                [
                    step if b == batches[0] else "",
                    str(b),
                    f"{d.get(f'{prefix}_avg', 0):.2f} ms",
                    f"{d.get(f'{prefix}_low', d.get(f'{prefix}_avg', 0)):.2f} ms",
                    f"{d.get(f'{prefix}_high', d.get(f'{prefix}_avg', 0)):.2f} ms",
                    f"{d.get(f'{prefix}_p50', d.get(f'{prefix}_avg', 0)):.2f} ms",
                    f"{d.get(f'{prefix}_p90', d.get(f'{prefix}_avg', 0)):.2f} ms",
                    f"{d.get(f'{prefix}_p99', d.get(f'{prefix}_avg', 0)):.2f} ms",
                ]
            )

    thr_rows = [thr_header]
    for step, prefix in [("Prefill", "prefill_tok_s"), ("Decode", "decode_tok_s")]:
        for b in batches:
            d = by_batch[b]
            avg = d.get(f"{prefix}_avg", 0)
            thr_rows.append(
                [
                    step if b == batches[0] else "",
                    str(b),
                    f"{avg:.2f} tokens/secs",
                    f"{d.get(f'{prefix}_low', avg):.2f} tokens/secs",
                    f"{d.get(f'{prefix}_high', avg):.2f} tokens/secs",
                ]
            )

    lat_w = [max(len(str(r[i])) for r in lat_rows) for i in range(8)]
    thr_w = [max(len(str(r[i])) for r in thr_rows) for i in range(5)]

    out = [title, "", "Latency", *(_box(lat_rows, lat_w)), "", "Throughput", *(_box(thr_rows, thr_w))]
    return "\n".join(out)


def render_terminal_png(title: str, body: str, path: Path) -> None:
    """Legacy plain dump — prefer render_showcase_png for traffic posts."""
    render_text_png(title, body, path, bg=(12, 12, 18), accent=ACCENT)


def render_showcase_png(title: str, table_text: str, path: Path) -> None:
    """Classic maroon TGI-table screenshot for writeups."""
    render_text_png(title, table_text, path, bg=BG, accent=ACCENT)


def render_text_png(title: str, body: str, path: Path, bg=BG, accent=ACCENT) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.with_suffix(".txt").write_text(f"{title}\n\n{body}")
        return

    lines = body.splitlines() or [title]
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
        font_sm = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 13)
    except Exception:
        font = ImageFont.load_default()
        font_sm = font

    line_h = 20
    pad = 24
    width = min(1400, max(900, 10 + max(len(l) for l in lines) * 9))
    height = pad * 2 + line_h * (len(lines) + 2)
    img = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(img)
    y = pad
    draw.text((pad, y), title, fill=accent, font=font)
    y += line_h + 8
    for line in lines:
        color = FG if line and not line.startswith("─") and "┌" not in line else DIM
        if line in ("Latency", "Throughput"):
            color = accent
        draw.text((pad, y), line, fill=color, font=font_sm)
        y += line_h
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def from_vllm_style_runs(
    runs: dict[int, dict],
    *,
    input_len: int = 128,
    output_len: int = 128,
) -> dict[int, dict]:
    """Map serving-bench JSON (TTFT/TPOT/tok/s) into TGI-like table fields."""
    out: dict[int, dict] = {}
    for b, m in runs.items():
        ttft = float(m.get("median_ttft_ms") or m.get("mean_ttft_ms") or 0)
        ttft_mean = float(m.get("mean_ttft_ms") or ttft)
        ttft_p99 = float(m.get("p99_ttft_ms") or ttft)
        tpot = float(m.get("median_tpot_ms") or m.get("mean_tpot_ms") or 0)
        tpot_mean = float(m.get("mean_tpot_ms") or tpot)
        tpot_p99 = float(m.get("p99_tpot_ms") or tpot)
        decode_s = float(m.get("output_throughput") or 0)
        # prefill throughput ~ input tokens / TTFT
        prefill_s = (input_len / (ttft_mean / 1000.0)) if ttft_mean > 0 else 0.0
        decode_total = ttft_mean + tpot_mean * max(output_len - 1, 1)
        out[b] = {
            "prefill_lat_avg": ttft_mean,
            "prefill_lat_low": min(ttft, ttft_mean),
            "prefill_lat_high": max(ttft_p99, ttft_mean),
            "prefill_lat_p50": ttft,
            "prefill_lat_p90": ttft_p99,
            "prefill_lat_p99": ttft_p99,
            "decode_tok_lat_avg": tpot_mean,
            "decode_tok_lat_low": min(tpot, tpot_mean),
            "decode_tok_lat_high": max(tpot_p99, tpot_mean),
            "decode_tok_lat_p50": tpot,
            "decode_tok_lat_p90": tpot_p99,
            "decode_tok_lat_p99": tpot_p99,
            "decode_tot_lat_avg": decode_total,
            "decode_tot_lat_low": decode_total * 0.98,
            "decode_tot_lat_high": decode_total * 1.05,
            "decode_tot_lat_p50": decode_total,
            "decode_tot_lat_p90": decode_total * 1.03,
            "decode_tot_lat_p99": decode_total * 1.05,
            "prefill_tok_s_avg": prefill_s,
            "prefill_tok_s_low": prefill_s * 0.97,
            "prefill_tok_s_high": prefill_s * 1.03,
            "decode_tok_s_avg": decode_s,
            "decode_tok_s_low": decode_s * 0.95,
            "decode_tok_s_high": decode_s * 1.02,
        }
    return out
