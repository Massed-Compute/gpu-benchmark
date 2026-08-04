"""Orchestrate setup → bench → stats (launch/terminate via Massed MCP)."""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import time
from datetime import date, datetime, timezone
from pathlib import Path

from mc_bench import plan as plan_mod
from mc_bench import remote
from mc_bench import report as report_mod
from mc_bench import screenshot as shot_mod
from mc_bench.names import SKU_PRICES, showcase_name, slugify

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KEY = os.path.expanduser(
    os.environ.get("MC_BENCH_SSH_KEY", "~/.ssh/songtree_massedcompute")
)
SSH_USER = "Ubuntu"


def _ssh(ip: str, cmd: str, key: str = DEFAULT_KEY, timeout: int = 600) -> subprocess.CompletedProcess:
    # OpenSSH joins remote argv with spaces, so pass one string:
    # `bash -lc <quoted-cmd>` — not separate `bash`, `-lc`, `cmd` args.
    remote_cmd = f"bash -lc {shlex.quote(cmd)}"
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
            remote_cmd,
        ],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _wait_ssh(ip: str, key: str = DEFAULT_KEY, tries: int = 60) -> None:
    r = None
    for _ in range(tries):
        r = _ssh(ip, "echo SSH_OK", key=key, timeout=30)
        if r.returncode == 0 and "SSH_OK" in r.stdout:
            return
        time.sleep(10)
    raise RuntimeError(f"SSH not ready on {ip}: {getattr(r, 'stderr', '')}")


def _hf_token() -> str:
    tok = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN") or ""
    if tok:
        return tok.strip()
    for p in (
        Path.home() / ".cache" / "huggingface" / "token",
        Path.home() / ".huggingface" / "token",
    ):
        if p.exists():
            return p.read_text().strip()
    return ""


def _parse_bench_text(text: str) -> dict:
    metrics: dict = {}
    for line in text.splitlines():
        low = line.lower()
        if "output token" in low and "throughput" in low:
            metrics["output_tok_s"] = _last_float(line)
        elif "output_throughput" in low or '"output_throughput"' in low:
            pass
        elif "request throughput" in low:
            metrics["request_s"] = _last_float(line)
        elif "median ttft" in low:
            metrics["ttft_ms_p50"] = _last_float(line)
        elif ("mean ttft" in low) or ("ttft" in low and "mean" in low):
            metrics.setdefault("ttft_ms_mean", _last_float(line))
        elif "mean tpot" in low:
            metrics["tpot_ms_mean"] = _last_float(line)
        elif "median tpot" in low:
            metrics["tpot_ms_p50"] = _last_float(line)
    # JSON blob fallback
    try:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            blob = json.loads(text[start : end + 1])
            if isinstance(blob, dict):
                if "output_throughput" in blob:
                    metrics.setdefault("output_tok_s", float(blob["output_throughput"]))
                if "median_ttft_ms" in blob:
                    metrics.setdefault("ttft_ms_p50", float(blob["median_ttft_ms"]))
                if "mean_ttft_ms" in blob:
                    metrics.setdefault("ttft_ms_mean", float(blob["mean_ttft_ms"]))
                if "median_tpot_ms" in blob:
                    metrics.setdefault("tpot_ms_p50", float(blob["median_tpot_ms"]))
                if "mean_tpot_ms" in blob:
                    metrics.setdefault("tpot_ms_mean", float(blob["mean_tpot_ms"]))
    except Exception:
        pass
    return metrics


def _last_float(line: str) -> float | None:
    import re

    nums = re.findall(r"[-+]?\d*\.\d+|\d+", line.replace(",", ""))
    if not nums:
        return None
    return float(nums[-1])


def _emit_showcase(
    *,
    img_dir: Path,
    sku: str,
    engine: str,
    model: str,
    by_conc: dict[int, dict],
) -> Path:
    """Write canonical images/<stem>-<engine>-showcase.png from c1/8/32 metrics."""
    mapped = {}
    for conc, m in by_conc.items():
        mapped[conc] = {
            "median_ttft_ms": m.get("ttft_ms_p50") or m.get("ttft_ms_mean"),
            "mean_ttft_ms": m.get("ttft_ms_mean") or m.get("ttft_ms_p50"),
            "median_tpot_ms": m.get("tpot_ms_p50") or m.get("tpot_ms_mean"),
            "mean_tpot_ms": m.get("tpot_ms_mean") or m.get("tpot_ms_p50"),
            "output_throughput": m.get("output_tok_s") or 0,
        }
    tables = shot_mod.from_vllm_style_runs(mapped)
    body = shot_mod.build_tgi_style_tables(
        title=f"{engine} | {sku} | {model}",
        by_batch=tables,
    )
    png = img_dir / showcase_name(sku, engine)
    shot_mod.render_showcase_png(f"{engine} | {sku}", body, png)
    return png


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
    slug = slugify(model)
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
        _ssh(ip, remote.STOP_ENGINES, key=key, timeout=120)
        port = 8000 if engine == "vllm" else 30000
        if engine == "vllm":
            serve = remote.VLLM_SERVE.format(
                model=model, tp=gpu_count, port=port, hf_token=hf_token or ""
            )
            # Forward optional vLLM knobs into the remote shell
            exports = []
            for var in ("VLLM_IMAGE", "VLLM_TEXT_ONLY_MM", "VLLM_MAX_MODEL_LEN", "VLLM_EXTRA_ARGS"):
                val = os.environ.get(var)
                if val:
                    exports.append(f'export {var}={json.dumps(val)}')
            if exports:
                serve = "\n".join(exports) + "\n" + serve
        else:
            serve = remote.SGLANG_SERVE.format(
                model=model, tp=gpu_count, port=port, hf_token=hf_token or ""
            )
        srv = _ssh(ip, serve, key=key, timeout=3600)
        (out_dir / f"{engine}-serve.log").write_text(srv.stdout + "\n" + srv.stderr)
        if srv.returncode != 0:
            raise RuntimeError(f"{engine} serve failed: {srv.stderr[-2000:]}")

        by_conc: dict[int, dict] = {}
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
            pull = _ssh(ip, f"cat {remote_out} 2>/dev/null || true", key=key, timeout=60)
            metrics = _parse_bench_text(br.stdout + "\n" + br.stderr + "\n" + pull.stdout)
            by_conc[conc] = metrics
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

        png = _emit_showcase(
            img_dir=img_dir, sku=sku, engine=engine, model=model, by_conc=by_conc
        )
        # attach showcase path to c32 row
        for entry in results:
            if entry["engine"] == engine and entry["max_concurrency"] == 32:
                entry["screenshot"] = str(png.relative_to(ROOT))

        _ssh(ip, remote.STOP_ENGINES, key=key, timeout=120)

    summary = {
        "id": f"{run_id}-{sku}",
        "date": date.today().isoformat(),
        "model": {"hf_id": model},
        "hardware": {
            "sku": sku,
            "count": gpu_count,
            "price_usd_per_hour": price_hr,
            "ip": ip,
        },
        "results": results,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    latest = ROOT / "results" / "raw" / slug / "latest.json"
    latest.write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def run_benchmark(args: argparse.Namespace) -> int:
    compare = getattr(args, "compare", False)
    planned = plan_mod.plan_skus(args.model, args.params_b, args.include_l40s, compare=compare)
    skus = args.skus.split(",") if args.skus else planned["skus"]
    engines = [e.strip() for e in args.engines.split(",") if e.strip()]
    slug = slugify(args.model)
    state = {
        "model": args.model,
        "slug": slug,
        "skus": skus,
        "engines": engines,
        "instances": [],
        "created": datetime.now(timezone.utc).isoformat(),
    }
    state_path = ROOT / "results" / "raw" / f"state-{slug}.json"
    if args.dry_run:
        print(json.dumps({"plan": planned, "skus": skus, "slug": slug, "note": "dry-run"}, indent=2))
        return 0

    ips_env = os.environ.get("MC_BENCH_IPS", "")
    if not ips_env:
        print(
            "Set MC_BENCH_IPS=sku:ip[,sku:ip] after launching via Massed MCP, then re-run.\n"
            f"Plan: {json.dumps(planned, indent=2)}",
            file=__import__("sys").stderr,
        )
        state_path.write_text(json.dumps(state, indent=2) + "\n")
        return 2

    hf_token = _hf_token()
    key = os.path.expanduser(os.environ.get("MC_BENCH_SSH_KEY", DEFAULT_KEY))
    summaries = []
    for pair in ips_env.split(","):
        sku, ip = pair.split(":", 1)
        sku, ip = sku.strip(), ip.strip()
        count, price = SKU_PRICES.get(sku, (1, 0.0))
        summaries.append(
            run_on_host(
                ip=ip,
                model=args.model,
                sku=sku,
                gpu_count=count,
                price_hr=price,
                engines=engines,
                hf_token=hf_token,
                key=key,
            )
        )
        state["instances"].append({"sku": sku, "ip": ip})

    state_path.write_text(json.dumps(state, indent=2) + "\n")
    md = report_mod.render_writeup(slug, summaries)
    report_mod.link_readme(slug, title=args.model.split("/")[-1].replace("-", " "))
    _mark_catalog_complete(slug)

    print(f"Wrote {md}")
    if not args.keep:
        print("CLOSE_AFTER: terminate Massed UUIDs for this run via MCP instances_terminate")
        print(json.dumps(state, indent=2))
    return 0


def _mark_catalog_complete(slug: str) -> None:
    cat = ROOT / "catalog" / "models.json"
    if not cat.exists():
        return
    data = json.loads(cat.read_text())
    for m in data.get("models", []):
        if m.get("id") == slug:
            m["status"] = "complete"
            m.pop("notes", None)
            data["updated"] = date.today().isoformat()
            cat.write_text(json.dumps(data, indent=2) + "\n")
            return


def terminate_from_state(path: Path) -> int:
    print(f"State at {path}; terminate UUIDs via Massed MCP (not embedded here).")
    print(path.read_text())
    return 0
