#!/usr/bin/env bash
# Atlas-Coder-2: merge PEFT adapter onto Qwen2.5-Coder-0.5B then vLLM local path.
# Env: HF_TOKEN OUTDIR
set -euo pipefail
HF_TOKEN=${HF_TOKEN:-}
OUTDIR=${OUTDIR:-$HOME/mc-bench/out/atlas-coder-2-0.5b}
ADAPTER=${ADAPTER:-Siddh07ETH/Atlas-Coder-2-0.5B}
BASE=${BASE:-Qwen/Qwen2.5-Coder-0.5B-Instruct}
MERGED=$HOME/mc-bench/models/atlas-coder-2-0.5b-merged
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUTDIR" "$HOME/mc-bench/models"
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN" HF_TOKEN="$HF_TOKEN"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip || true
python3 -m venv "$HOME/mc-bench/venv"
# shellcheck disable=SC1091
. "$HOME/mc-bench/venv/bin/activate"
pip install -q -U pip wheel torch --index-url https://download.pytorch.org/whl/cu128 || pip install -q -U torch
pip install -q -U transformers peft accelerate huggingface_hub safetensors

if [[ ! -f "$MERGED/config.json" ]]; then
  log "merge $ADAPTER onto $BASE"
  python3 - <<PY
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
import torch, os
base=os.environ.get("BASE","Qwen/Qwen2.5-Coder-0.5B-Instruct")
adapter=os.environ.get("ADAPTER","Siddh07ETH/Atlas-Coder-2-0.5B")
out=os.path.expanduser("~/mc-bench/models/atlas-coder-2-0.5b-merged")
tok=AutoTokenizer.from_pretrained(base, trust_remote_code=True)
m=AutoModelForCausalLM.from_pretrained(base, torch_dtype=torch.bfloat16, trust_remote_code=True)
m=PeftModel.from_pretrained(m, adapter)
m=m.merge_and_unload()
m.save_pretrained(out)
tok.save_pretrained(out)
print("merged", out)
PY
fi

MODEL="$MERGED" OUTDIR="$OUTDIR" bash "$SCRIPT_DIR/remote_vllm_llm.sh"
echo "adapter=$ADAPTER base=$BASE" >"$OUTDIR/merge-note.txt"
