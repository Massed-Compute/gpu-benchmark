#!/usr/bin/env python3
"""Rebuild a generated capture table from pulled SKU dirs.

Writes capture-table.generated.md / .json only. Never overwrites the
hand-written capture-table.md / .json this page cites as provenance.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DAY = ROOT / "results/raw/ltx-2.5/mar-74-2026-09-02"
LIST = {
    "gpu_1x_l40s": 0.88,
    "gpu_1x_DGX_A100": 1.38,
    "gpu_1x_pro_6000_blackwell": 2.19,
}
LABEL = {
    "gpu_1x_l40s": "L40S",
    "gpu_1x_DGX_A100": "DGX A100",
    "gpu_1x_pro_6000_blackwell": "RTX PRO 6000 Blackwell",
}


def peak_util(vram_csv: Path) -> float | None:
    peak = None
    if not vram_csv.exists():
        return None
    for row in csv.reader(vram_csv.read_text().splitlines()):
        if len(row) < 4:
            continue
        try:
            util = float(row[3].strip())
        except ValueError:
            continue
        peak = util if peak is None else max(peak, util)
    return peak


def load_ok(d: Path, name: str) -> dict | None:
    p = d / name
    if not p.exists():
        return None
    try:
        blob = json.loads(p.read_text())
    except json.JSONDecodeError:
        return None
    if blob.get("status") != "ok":
        return None
    return blob


def load_pair(d: Path) -> tuple[dict, dict | None, str] | None:
    warm = load_ok(d, "warm.json")
    cold = load_ok(d, "cold.json")
    kind = "bf16"
    if warm is None:
        warm = load_ok(d, "warm_fp8.json")
        cold = load_ok(d, "cold_fp8.json")
        kind = "fp8"
    if warm is None:
        return None
    return warm, cold, kind


def main() -> None:
    rows = []
    for sku, usd_hr in LIST.items():
        d = DAY / sku
        pair = load_pair(d)
        if not pair:
            continue
        warm, cold, kind = pair
        wall = float(warm["wall_s"])
        usd_clip = wall * usd_hr / 3600.0
        rows.append(
            {
                "sku": sku,
                "label": LABEL[sku],
                "usd_hr_list": usd_hr,
                "warm_s": wall,
                "cold_s": cold["wall_s"] if cold else None,
                "peak_vram_gib": warm.get("peak_vram_gib"),
                "peak_vram_mib": warm.get("peak_vram_mib"),
                "peak_gpu_util_pct": peak_util(d / "warm.vram.csv")
                if kind == "bf16"
                else peak_util(d / "warm_fp8.vram.csv"),
                "usd_per_clip": round(usd_clip, 4),
                "clips_per_hr": round(3600.0 / wall, 2),
                "mp4": f"results/raw/ltx-2.5/mar-74-2026-09-02/{sku}/warm.mp4"
                if kind == "bf16"
                else f"results/raw/ltx-2.5/mar-74-2026-09-02/{sku}/warm_fp8.mp4",
                "mp4_bytes": warm.get("mp4_bytes"),
                "status": warm.get("status"),
                "quant": kind,
            }
        )
    DAY.mkdir(parents=True, exist_ok=True)
    out_json = DAY / "capture-table.generated.json"
    out_md = DAY / "capture-table.generated.md"
    out_json.write_text(json.dumps({"date": "2026-09-02", "rows": rows}, indent=2) + "\n")
    md = [
        "# Generated capture table 2026-09-02",
        "",
        "Machine output. The page cites `capture-table.md`, not this file.",
        "",
        "| SKU | $/hr list | Warm s | Cold s | VRAM | Peak util | $/clip | Clips/hr | Quant | Status |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---|---|",
    ]
    for r in rows:
        md.append(
            f"| {r['label']} | {r['usd_hr_list']:.2f} | {r['warm_s']:.3f} | {r['cold_s'] if r['cold_s'] is not None else ''} | {r['peak_vram_gib']} GiB | {r['peak_gpu_util_pct']} | {r['usd_per_clip']:.4f} | {r['clips_per_hr']:.1f} | {r['quant']} | {r['status']} |"
        )
    out_md.write_text("\n".join(md) + "\n")
    print("wrote", out_md, file=sys.stderr)


if __name__ == "__main__":
    main()
