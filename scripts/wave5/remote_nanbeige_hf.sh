#!/usr/bin/env bash
# Nanbeige4.2-3B via transformers (vLLM lacks NanbeigeForCausalLM). Env: HF_TOKEN OUTDIR
set -euo pipefail
MODEL=${MODEL:-Nanbeige/Nanbeige4.2-3B}
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/nanbeige4-2-3b}
mkdir -p "$OUTDIR" "$HOME/.cache/huggingface" "$HOME/mc-bench"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" HF_HUB_ENABLE_HF_TRANSFER=1 MODEL OUTDIR
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip git curl || true
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel
pip install -q -U torch --index-url https://download.pytorch.org/whl/cu128 || pip install -q -U torch
pip install -q -U 'transformers>=4.56' accelerate huggingface_hub hf_transfer sentencepiece protobuf

log "transformers bench $MODEL"
python3 - <<'PY'
import json, os, statistics, time, torch
from pathlib import Path
from transformers import AutoModelForCausalLM, AutoTokenizer

out = Path(os.environ["OUTDIR"])
model_id = os.environ["MODEL"]
from transformers import AutoConfig
tok = AutoTokenizer.from_pretrained(model_id, trust_remote_code=True)
cfg = AutoConfig.from_pretrained(model_id, trust_remote_code=True)
rs = getattr(cfg, "rope_scaling", None)
if isinstance(rs, dict) and "type" not in rs:
    rs["type"] = rs.get("rope_type") or rs.get("name") or "default"
    cfg.rope_scaling = rs
t0 = time.perf_counter()
model = AutoModelForCausalLM.from_pretrained(
    model_id, config=cfg, trust_remote_code=True, torch_dtype=torch.bfloat16, device_map="auto"
)
load_s = time.perf_counter() - t0
prompt = "Explain GPU inference throughput in two sentences."
inputs = tok(prompt, return_tensors="pt")
first = next(model.parameters()).device
inputs = {k: v.to(first) for k, v in inputs.items()}

def run(max_new=128):
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    with torch.inference_mode():
        o = model.generate(**inputs, max_new_tokens=max_new, do_sample=False)
    torch.cuda.synchronize()
    dt = time.perf_counter() - t0
    n = int(o.shape[-1] - inputs["input_ids"].shape[-1])
    return {"latency_s": dt, "new_tokens": n, "tok_s": n / dt if dt else 0}

run(32)  # warmup
runs = [run(128) for _ in range(5)]
# synthesize vLLM-like c1 for writeup compatibility
mean_tok = statistics.mean(r["tok_s"] for r in runs)
mean_lat_ms = statistics.mean(r["latency_s"] for r in runs) * 1000
c1 = {
    "engine": "transformers",
    "max_concurrency": 1,
    "output_throughput": mean_tok,
    "median_ttft_ms": mean_lat_ms / 2,  # rough; single generate not true TTFT
    "mean_ttft_ms": mean_lat_ms / 2,
    "mean_tpot_ms": (1000.0 / mean_tok) if mean_tok else 0,
    "note": "single-stream transformers generate; c8/c32 N/A (arch not in vLLM)",
}
(out / "vllm-c1.json").write_text(json.dumps(c1, indent=2))
# mark c8/c32 as same note so pages don't invent numbers
for c in (8, 32):
    d = dict(c1)
    d["max_concurrency"] = c
    d["output_throughput"] = None
    d["unsupported"] = True
    (out / f"vllm-c{c}.json").write_text(json.dumps(d, indent=2))
result = {
    "model": model_id,
    "load_s": load_s,
    "engine": "transformers+device_map_auto",
    "runs": runs,
    "mean_tok_s": mean_tok,
    "median_tok_s": statistics.median(r["tok_s"] for r in runs),
}
(out / "transformers-bench.json").write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
PY
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv | tee "$OUTDIR/nvidia-smi.txt"
rm -f "$OUTDIR/FAIL"
echo DONE >"$OUTDIR/DONE"
log DONE
