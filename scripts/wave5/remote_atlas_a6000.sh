#!/usr/bin/env bash
# Atlas-Coder-2: merge PEFT then transformers single-stream bench.
# Env: HF_TOKEN OUTDIR
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-$(cat "$HOME/.cache/huggingface/token" 2>/dev/null || true)}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/atlas-coder-2-0.5b}
ADAPTER=${ADAPTER:-Siddh07ETH/Atlas-Coder-2-0.5B}
BASE=${BASE:-Qwen/Qwen2.5-Coder-0.5B-Instruct}
MERGED=$HOME/mc-bench/models/atlas-coder-2-0.5b-merged
mkdir -p "$OUTDIR" "$HOME/mc-bench/models" "$HOME/.cache/huggingface"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN" ADAPTER BASE MERGED OUTDIR

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# ensurepip needs distro venv package (image often lacks it until apt install).
need_venv_pkg=1
if python3 -c 'import ensurepip' 2>/dev/null; then
  need_venv_pkg=0
fi
if [[ "$need_venv_pkg" -eq 1 ]]; then
  log "installing python3-venv (waiting for apt locks)"
  for _ in $(seq 1 120); do
    if ! pgrep -x apt >/dev/null && ! pgrep -x apt-get >/dev/null && ! pgrep -x dpkg >/dev/null \
      && ! sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  sudo apt-get update -qq || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3.12-venv python3-pip || \
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip
fi
rm -rf "$HOME/mc-bench/venv"
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel
pip install -q -U torch --index-url https://download.pytorch.org/whl/cu128 || pip install -q -U torch
pip install -q -U transformers peft accelerate huggingface_hub safetensors

if [[ ! -f "$MERGED/config.json" ]]; then
  log "merge $ADAPTER onto $BASE"
  python3 - <<'PY'
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
import torch, os
base=os.environ["BASE"]; adapter=os.environ["ADAPTER"]; out=os.environ["MERGED"]
tok=AutoTokenizer.from_pretrained(base, trust_remote_code=True)
m=AutoModelForCausalLM.from_pretrained(base, torch_dtype=torch.bfloat16, trust_remote_code=True)
m=PeftModel.from_pretrained(m, adapter).merge_and_unload()
m.save_pretrained(out); tok.save_pretrained(out)
print("merged", out)
PY
fi

log "transformers bench"
python3 - <<'PY'
import json, statistics, time, torch, os
from pathlib import Path
from transformers import AutoModelForCausalLM, AutoTokenizer
out = Path(os.environ["OUTDIR"]); merged = Path(os.environ["MERGED"])
tok = AutoTokenizer.from_pretrained(merged)
m = AutoModelForCausalLM.from_pretrained(
    merged,
    torch_dtype=torch.bfloat16,
    device_map="auto",
    attn_implementation="sdpa",
)
prompt = "Write a Python function that returns fibonacci(n)."
inputs = {k: v.to(next(m.parameters()).device) for k, v in tok(prompt, return_tensors="pt").items()}

def run(n=128):
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    with torch.inference_mode():
        o = m.generate(**inputs, max_new_tokens=n, do_sample=False, use_cache=True)
    torch.cuda.synchronize()
    dt = time.perf_counter() - t0
    nt = int(o.shape[-1] - inputs["input_ids"].shape[-1])
    return {"latency_s": dt, "new_tokens": nt, "tok_s": nt / dt if dt else 0}

run(32)
runs = [run(128) for _ in range(5)]
mean = statistics.mean(r["tok_s"] for r in runs)
med = statistics.median(r["tok_s"] for r in runs)
result = {"model": "Siddh07ETH/Atlas-Coder-2-0.5B", "base": os.environ["BASE"], "engine": "transformers-merged-peft-sdpa",
          "attn": "sdpa", "runs": runs, "mean_tok_s": mean, "median_tok_s": med}
(out / "transformers-bench.json").write_text(json.dumps(result, indent=2))
c1 = {"engine": "transformers-merged-peft-sdpa", "max_concurrency": 1, "output_throughput": mean,
      "ttft_measured": False,
      "note": "PEFT merged onto Qwen2.5-Coder-0.5B-Instruct; single-stream generate; TTFT not measured"}
(out / "transformers-c1.json").write_text(json.dumps(c1, indent=2) + "\n")
for c in (8, 32):
    d = dict(c1); d["max_concurrency"] = c; d["output_throughput"] = None; d["unsupported"] = True
    (out / f"transformers-c{c}.json").write_text(json.dumps(d, indent=2) + "\n")
print(json.dumps(result, indent=2))
# Capture VRAM while model still resident
import subprocess
(out / "nvidia-smi.txt").write_text(
    subprocess.check_output(
        ["nvidia-smi", "--query-gpu=name,memory.used,memory.total", "--format=csv"],
        text=True,
    )
)
PY
echo "adapter=$ADAPTER base=$BASE" >"$OUTDIR/merge-note.txt"
echo "$ADAPTER" >"$OUTDIR/model.txt"
rm -f "$OUTDIR/FAIL"
echo DONE >"$OUTDIR/DONE"
log DONE
