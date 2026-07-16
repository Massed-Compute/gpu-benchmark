"""SKU planning under traffic spend caps."""
from __future__ import annotations


def _guess_params(model: str, params_b: float | None) -> float:
    if params_b is not None:
        return params_b
    m = model.lower()
    for needle, val in [
        ("405b", 405),
        ("236b", 236),
        ("72b", 72),
        ("70b", 70),
        ("32b", 32),
        ("27b", 27),
        ("14b", 14),
        ("8b", 8),
        ("7b", 7),
        ("3b", 3),
        ("1.5b", 1.5),
        ("0.5b", 0.5),
    ]:
        if needle in m:
            return float(val)
    return 8.0


def plan_skus(model: str, params_b: float | None = None, include_l40s: bool = False) -> dict:
    pb = _guess_params(model, params_b)
    if pb <= 32:
        return {
            "model": model,
            "params_b": pb,
            "tier": "small",
            "max_vms": 1,
            "skus": ["gpu_1x_l40s"],
            "notes": "1 VM for small models (L40S default for traffic/value story)",
        }
    skus = ["gpu_2x_pro_6000_blackwell", "gpu_2x_h100"]
    max_vms = 2
    if include_l40s:
        skus.append("gpu_4x_l40s")
        max_vms = 3
    return {
        "model": model,
        "params_b": pb,
        "tier": "big",
        "max_vms": max_vms,
        "skus": skus,
        "notes": "2 VMs default (Blackwell vs H100); +L40S with --include-l40s (max 3)",
    }
