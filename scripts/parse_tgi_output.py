#!/usr/bin/env python3
"""Parse TGI text-generation-benchmark text dumps into result JSON.

Accepts either a plain table dump (preferred) or mixed TUI capture.
Fills headline metrics + by_batch when rows are found.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROW_RE = re.compile(
    r"^\s*(Prefill|Decode(?:\s*\((?:token|total)\))?)\s+"
    r"(\d+)\s+"
    r"([\d.]+)\s+([\d.]+)\s+([\d.]+)"
    r"(?:\s+([\d.]+)\s+([\d.]+)\s+([\d.]+))?",
    re.IGNORECASE,
)


def parse_rows(text: str) -> list[dict]:
    rows: list[dict] = []
    for line in text.splitlines():
        m = ROW_RE.match(line)
        if not m:
            continue
        step = re.sub(r"\s+", " ", m.group(1)).strip().lower()
        batch = int(m.group(2))
        avg, low, high = float(m.group(3)), float(m.group(4)), float(m.group(5))
        row = {
            "step": step,
            "batch_size": batch,
            "avg": avg,
            "lowest": low,
            "highest": high,
        }
        if m.group(6):
            row["p50"] = float(m.group(6))
            row["p90"] = float(m.group(7))
            row["p99"] = float(m.group(8))
        rows.append(row)
    return rows


def build_result(rows: list[dict], meta: dict) -> dict:
    # Prefer throughput rows (tokens/secs). Latency rows share similar labels;
    # caller should pass only one section, or we detect by magnitude heuristics.
    by_batch: dict[int, dict] = {}
    for r in rows:
        b = r["batch_size"]
        by_batch.setdefault(b, {"batch_size": b})
        step = r["step"]
        if "prefill" in step and "p50" not in r:
            by_batch[b]["prefill_tok_s_avg"] = r["avg"]
        elif step.startswith("decode") and "token" not in step and "total" not in step and "p50" not in r:
            by_batch[b]["decode_tok_s_avg"] = r["avg"]
        elif "prefill" in step and "p50" in r:
            by_batch[b]["prefill_latency_ms_avg"] = r["avg"]
        elif "decode (token)" in step:
            by_batch[b]["decode_token_latency_ms_avg"] = r["avg"]
        elif "decode (total)" in step:
            by_batch[b]["decode_total_latency_ms_avg"] = r["avg"]

    batches = sorted(by_batch.values(), key=lambda x: x["batch_size"])
    metrics = {}
    b1 = by_batch.get(1, {})
    b32 = by_batch.get(32, {})
    for key, src in [
        ("decode_tok_s_b1", b1.get("decode_tok_s_avg")),
        ("decode_tok_s_b32", b32.get("decode_tok_s_avg")),
        ("decode_token_latency_ms_b1", b1.get("decode_token_latency_ms_avg")),
        ("prefill_tok_s_b1", b1.get("prefill_tok_s_avg")),
        ("prefill_tok_s_b32", b32.get("prefill_tok_s_avg")),
    ]:
        if src is not None:
            metrics[key] = src

    return {
        **meta,
        "status": "complete" if metrics else "partial",
        "metrics": metrics,
        "by_batch": batches,
        "provenance": {
            "source": "tgi_text_generation_benchmark",
            "confidence": "high" if metrics else "low",
            "notes": "Parsed by scripts/parse_tgi_output.py",
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path)
    ap.add_argument("-o", "--output", type=Path, required=True)
    ap.add_argument("--meta", type=Path, help="JSON file with id/date/engine/model/hardware/config")
    args = ap.parse_args()

    meta = {}
    if args.meta:
        meta = json.loads(args.meta.read_text())

    rows = parse_rows(args.input.read_text(errors="replace"))
    if not rows:
        print("No benchmark rows parsed; check input format.", file=sys.stderr)
        return 1

    result = build_result(rows, meta)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote {args.output} ({len(result.get('by_batch', []))} batch rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
