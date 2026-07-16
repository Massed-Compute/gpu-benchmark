"""Orchestrate launch → setup → bench → stats → terminate.

Launch/terminate go through Massed MCP externally when API creds
are unavailable; this module focuses on SSH remote execution + local artifacts.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from datetime import date, datetime, timezone
from pathlib import Path

from mc_bench import plan as plan_mod
from mc_bench import remote
from mc_bench import report as report_mod
from mc_bench import screenshot as shot_mod

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KEY = os.path.expanduser("~/.ssh/songtree_massedcompute")
SSH_USER = "Ubuntu"


def _ssh(ip: str, cmd: str, key: str = DEFAULT_KEY, timeout: int = 600) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            "ssh",
            "-i",
            key,
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=accept-new",
            "-o",
            "ConnectTimeout=15",
            f"{SSH_USER}@{ip}",
            "bash",
            "-lc",
            cmd,
        ],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _wait_ssh(ip: str, key: str = DEFAULT_KEY, tries: int = 60) -> None:
    for i in range(tries):
        r = _ssh(ip, "echo SSH_OK", key=key, timeout=30)
        if r.returncode == 0 and "SSH_OK" in r.stdout:
            return
        time.sleep(10)
    raise RuntimeError(f"SSH not ready on {ip}: {r.stderr}")


def _slug(model: str) -> str:
    return model.split("/")[-1].lower().replace(".", "-").replace("_", "-")


def run_on_host(
    *,
    ip: str,
    model: str,
    sku: str,
    gpu_count: int,
    price_hr: float,
    engines: list[str],
    hf_token: str = "",
    key: str = DEFAULT_KEY,
) -> dict:
    slug = _slug(model)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = ROOT / "results" / "raw" / slug / sku / run_id
    out_dir.mkdir(parents=True, exist_ok=True)
    img_dir = ROOT / slug / "images"
    img_dir.mkdir(parents=True, exist_ok=True)

    _wait_ssh(ip, key=key)
    boot = _ssh(ip, remote.BOOTSTRAP, key=key, timeout=900)
    (out_dir / "bootstrap.log").write_text(boot.stdout + "\n" + boot.stderr)
    if boot.returncode != 0:
        raise RuntimeError(f"bootstrap failed: {boot.stderr[-2000:]}")

    results = []
    for engine in engines:
        # stop previous
        _ssh(ip, remote.STOP_ENGINES, key=key, timeout=120)
        port = 8000 if engine == "vllm" else 30000
        if engine == "vllm":
            serve = remote.VLLM_SERVE.format(
                model=model, tp=gpu_count, port=port, hf_token=hf_token or ""
            )
        else:
            serve = remote.SGLANG_SERVE.format(
                model=model, tp=gpu_count, port=port, hf_token=hf_token or ""
            )
        srv = _ssh(ip, serve, key=key, timeout=3600)
        (out_dir / f"{engine}-serve.log").write_text(srv.stdout + "\n" + srv.stderr)
        if srv.returncode != 0:
            raise RuntimeError(f"{engine} serve failed: {srv.stderr[-2000:]}")

        for conc in (1, 8, 32):
            remote_out = f"$HOME/mc-bench/{engine}-c{conc}.json"
            if engine == "vllm":
                bench = remote.VLLM_BENCH.format(
                    model=model, port=port, out=remote_out, conc=conc
                )
            else:
                bench = remote.SGLANG_BENCH.format(
                    model=model, port=port, out=remote_out, conc=conc
                )
            br = _ssh(ip, bench, key=key, timeout=3600)
            local = out_dir / f"{engine}-c{conc}.txt"
            local.write_text(br.stdout + "\n" + br.stderr)
            # pull json if any
            pull = _ssh(ip, f"cat {remote_out} 2>/dev/null || true", key=key, timeout=60)
            metrics = _parse_bench_text(br.stdout + "\n" + br.stderr + "\n" + pull.stdout)
            entry = {
                "engine": engine,
                "sku": sku,
                "gpu_count": gpu_count,
                "price_usd_per_hour": price_hr,
                "max_concurrency": conc,
                "metrics": metrics,
                "raw_stdout_path": str(local.relative_to(ROOT)),
            }
            results.append(entry)
            # screenshot of summary text
            png = img_dir / f"{sku}-{engine}-c{conc}.png"
            shot_mod.render_terminal_png(
                title=f"{engine} | {sku} | conc={conc} | {model}",
                body=local.read_text()[-4000:],
                path=png,
            )
            entry["screenshot"] = str(png.relative_to(ROOT))

        _ssh(ip, remote.STOP_ENGINES, key=key, timeout=120)

    summary = {
        "id": f"{run_id}-{sku}",
        "date": date.today().isoformat(),
        "model": {"hf_id": model},
        "hardware": {"sku": sku, "count": gpu_count, "price_usd_per_hour": price_hr, "ip": ip},
        "results": results,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    # also copy latest pointer
    latest = ROOT / "results" / "raw" / slug / "latest.json"
    latest.write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def _parse_bench_text(text: str) -> dict:
    """Best-effort extract of common serving-bench lines."""
    metrics: dict = {}
    for line in text.splitlines():
        low = line.lower()
        if "output token" in low and "throughput" in low:
            metrics["output_tok_s"] = _last_float(line)
        elif "request throughput" in low:
            metrics["request_s"] = _last_float(line)
        elif "mean ttft" in low or "ttft" in low and "mean" in low:
            metrics.setdefault("ttft_ms_mean", _last_float(line))
        elif "median ttft" in low:
            metrics["ttft_ms_p50"] = _last_float(line)
        elif "mean tpot" in low:
            metrics["tpot_ms_mean"] = _last_float(line)
        elif "median tpot" in low:
            metrics["tpot_ms_p50"] = _last_float(line)
    return metrics


def _last_float(line: str) -> float | None:
    import re

    nums = re.findall(r"[-+]?\d*\.\d+|\d+", line.replace(",", ""))
    if not nums:
        return None
    return float(nums[-1])


def run_benchmark(args: argparse.Namespace) -> int:
    planned = plan_mod.plan_skus(args.model, args.params_b, args.include_l40s)
    skus = args.skus.split(",") if args.skus else planned["skus"]
    engines = [e.strip() for e in args.engines.split(",") if e.strip()]
    state = {
        "model": args.model,
        "skus": skus,
        "engines": engines,
        "instances": [],
        "created": datetime.now(timezone.utc).isoformat(),
    }
    state_path = ROOT / "results" / "raw" / f"state-{_slug(args.model)}.json"
    if args.dry_run:
        print(json.dumps({"plan": planned, "skus": skus, "note": "dry-run"}, indent=2))
        return 0

    # Expect operator/MCP to have launched VMs; IPs via env MC_BENCH_IPS=sku:ip,...
    # or a state file with instances.
    ips_env = os.environ.get("MC_BENCH_IPS", "")
    if not ips_env:
        print(
            "Set MC_BENCH_IPS=sku:ip[,sku:ip] after launching via Massed MCP, then re-run.\n"
            f"Plan: {json.dumps(planned, indent=2)}",
            file=__import__("sys").stderr,
        )
        state_path.write_text(json.dumps(state, indent=2) + "\n")
        return 2

    sku_prices = {
        "gpu_1x_l40s": (1, 0.88),
        "gpu_1x_h100": (1, 2.73),
        "gpu_1x_pro_6000_blackwell": (1, 2.19),
        "gpu_2x_h100": (2, 5.46),
        "gpu_2x_pro_6000_blackwell": (2, 4.38),
        "gpu_4x_l40s": (4, 3.52),
    }
    hf_token = os.environ.get("HF_TOKEN", "")
    summaries = []
    for pair in ips_env.split(","):
        sku, ip = pair.split(":", 1)
        count, price = sku_prices.get(sku, (1, 0.0))
        summaries.append(
            run_on_host(
                ip=ip.strip(),
                model=args.model,
                sku=sku.strip(),
                gpu_count=count,
                price_hr=price,
                engines=engines,
                hf_token=hf_token,
            )
        )
        state["instances"].append({"sku": sku, "ip": ip})

    state_path.write_text(json.dumps(state, indent=2) + "\n")
    report_mod.render_writeup(_slug(args.model), summaries)
    if not args.keep:
        print("CLOSE_AFTER: terminate Massed UUIDs for this run via MCP instances_terminate")
        print(json.dumps(state, indent=2))
    return 0


def terminate_from_state(path: Path) -> int:
    print(f"State at {path}; terminate UUIDs via Massed MCP (not embedded here).")
    print(path.read_text())
    return 0
