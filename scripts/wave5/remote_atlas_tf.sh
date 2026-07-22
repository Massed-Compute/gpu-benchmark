#!/usr/bin/env bash
set -euo pipefail
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/atlas-coder-2-0.5b}
MERGED=${MERGED:-$HOME/mc-bench/models/atlas-coder-2-0.5b-merged}
mkdir -p "$OUTDIR"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pkill -f "vllm serve" >/dev/null 2>&1 || true
python3 - <<'PY'
import json, statistics, time, torch
from pathlib import Path
from transformers import AutoModelForCausalLM, AutoTokenizer
out = Path.home() / "mc-bench/out/atlas-coder-2-0.5b"
merged = Path.home() / "mc-bench/models/atlas-coder-2-0.5b-merged"
tok = AutoTokenizer.from_pretrained(merged)
m = AutoModelForCausalLM.from_pretrained(merged, torch_dtype=torch.bfloat16, device_map="auto")
prompt = "Write a Python function that returns fibonacci(n)."
inputs = {k: v.to(next(m.parameters()).device) for k, v in tok(prompt, return_tensors="pt").items()}

def run(n=128):
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    with torch.inference_mode():
        o = m.generate(**inputs, max_new_tokens=n, do_sample=False)
    torch.cuda.synchronize()
    dt = time.perf_counter() - t0
    nt = int(o.shape[-1] - inputs["input_ids"].shape[-1])
    return {"latency_s": dt, "new_tokens": nt, "tok_s": nt / dt if dt else 0}

run(32)
runs = [run(128) for _ in range(5)]
mean = statistics.mean(r["tok_s"] for r in runs)
c1 = {
    "engine": "transformers-merged-peft",
    "max_concurrency": 1,
    "output_throughput": mean,
    "ttft_measured": False,
    "note": "PEFT adapter merged onto Qwen2.5-Coder-0.5B-Instruct; single-stream generate; TTFT not measured",
}
(out / "transformers-c1.json").write_text(json.dumps(c1, indent=2) + "\n")
for c in (8, 32):
    d = dict(c1)
    d["max_concurrency"] = c
    d["output_throughput"] = None
    d["unsupported"] = True
    (out / f"transformers-c{c}.json").write_text(json.dumps(d, indent=2) + "\n")
(out / "transformers-bench.json").write_text(json.dumps({"mean_tok_s": mean, "runs": runs}, indent=2) + "\n")
(out / "DONE").write_text("DONE\n")
print("atlas mean", mean)
PY
rm -f "$OUTDIR/FAIL"
