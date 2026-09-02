#!/usr/bin/env python3
"""Build MAR-74 capture table + peak util from pulled SKU dirs."""
from __future__ import annotations

import csv
import json
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


def main() -> None:
    rows = []
    for sku, usd_hr in LIST.items():
        d = DAY / sku
        warm = json.loads((d / "warm.json").read_text()) if (d / "warm.json").exists() else None
        cold = json.loads((d / "cold.json").read_text()) if (d / "cold.json").exists() else None
        if not warm:
            continue
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
                "peak_gpu_util_pct": peak_util(d / "warm.vram.csv"),
                "usd_per_clip": round(usd_clip, 4),
                "clips_per_hr": round(3600.0 / wall, 2),
                "mp4_bytes": warm.get("mp4_bytes"),
                "status": warm.get("status"),
                "failures": [],
            }
        )
    DAY.mkdir(parents=True, exist_ok=True)
    (DAY / "capture-table.json").write_text(json.dumps({"date": "2026-09-02", "ticket": "MAR-74", "rows": rows}, indent=2) + "\n")
    md = ["# MAR-74 capture table 2026-09-02", "", "| SKU | $/hr list | Warm s | Cold s | VRAM | Peak util | $/clip | Clips/hr | Status |", "|---|---:|---:|---:|---:|---:|---:|---:|---|"]
    for r in rows:
        md.append(
            f"| {r['label']} | {r['usd_hr_list']:.2f} | {r['warm_s']:.3f} | {r['cold_s'] if r['cold_s'] is not None else ''} | {r['peak_vram_gib']} GiB | {r['peak_gpu_util_pct']} | {r['usd_per_clip']:.4f} | {r['clips_per_hr']:.1f} | {r['status']} |"
        )
    (DAY / "capture-table.md").write_text("\n".join(md) + "\n")
    print("wrote", DAY / "capture-table.md")


if __name__ == "__main__":
    main()
