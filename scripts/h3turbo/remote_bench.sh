#!/usr/bin/env bash
# Timed MiniMax-H3 Turbo T2AV with rewriter + 4-step 768p. Heavy SKUs also run 8-step + SLA.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
SKU="${SKU:?set SKU}"
ADDONS_HEAVY="${ADDONS_HEAVY:-0}"
ROOT="$HOME/mc-bench"
OUT="${OUTDIR:-$ROOT/out/h3turbo}"
MODELS="$ROOT/models"
LX="$ROOT/LightX2V"
PROMPT_SHORT="${PROMPT:-A compact GPU accelerator module on a clean desk in soft daylight, camera slowly pushes in, quiet fan whir and room tone, no text no logos no watermarks.}"
SEED="${SEED:-42}"
LOG="$HOME/h3turbo-bench.log"
exec > >(tee -a "$LOG") 2>&1
log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

mkdir -p "$OUT"
# shellcheck disable=SC1091
source "$ROOT/venv/bin/activate"
export SENSITIVE_LAYER_DTYPE=FP32
export DTYPE=BF16
export PYTHONPATH="$LX${PYTHONPATH:+:$PYTHONPATH}"
export HF_HUB_ENABLE_HF_TRANSFER=1

REWRITE="$OUT/rewritten_prompt.txt"
log "rewrite prompt (8B VL LoRA)"
python3 "$MODELS/rewriter-8b/infer.py" \
  --base-model "$MODELS/Qwen3-VL-8B-Instruct" \
  --adapter-path "$MODELS/rewriter-8b" \
  --prompt "$PROMPT_SHORT" \
  --duration 5 \
  --resolution 16:9 \
  --greedy \
  --output "$REWRITE" \
  || python3 - <<PY
from pathlib import Path
Path("$REWRITE").write_text("""integrated_multimodal_description: [Shot 1] $PROMPT_SHORT
overall_soundscape: Quiet fan whir and room tone.
non_diegetic_music: N/A
""")
print("rewriter failed; using structured fallback")
PY
PROMPT="$(cat "$REWRITE")"
log "prompt ready ($(wc -c < "$REWRITE") bytes)"

run_one() {
  local label=$1 cfg=$2
  local mp4="$OUT/${label}.mp4"
  local logf="$OUT/${label}.log"
  local vramf="$OUT/${label}.vram.csv"
  rm -f "$mp4"
  : > "$vramf"
  local smi_pid=""
  (
    while true; do
      nvidia-smi --query-gpu=timestamp,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits >> "$vramf" || true
      sleep 1
    done
  ) &
  smi_pid=$!
  local t0 t1 rc
  t0=$(date +%s.%N)
  set +e
  python -m lightx2v.infer \
    --model_cls minimax_h3 \
    --task t2av \
    --model_path "$MODELS/MiniMax-H3" \
    --config_json "$cfg" \
    --prompt "$PROMPT" \
    --save_result_path "$mp4" \
    --seed "$SEED" >"$logf" 2>&1
  rc=$?
  set -e
  t1=$(date +%s.%N)
  kill "$smi_pid" 2>/dev/null || true
  wait "$smi_pid" 2>/dev/null || true
  python3 - "$OUT" "$label" "$SKU" "$rc" "$t0" "$t1" "$mp4" <<'PY'
import csv, json, os, subprocess, sys
from pathlib import Path
outdir, label, sku, rc, t0, t1, mp4 = sys.argv[1:8]
rc = int(rc)
wall = float(t1) - float(t0)
peak = 0.0
vramf = Path(outdir) / f"{label}.vram.csv"
if vramf.exists():
    for row in csv.reader(vramf.read_text().splitlines()):
        if not row:
            continue
        try:
            peak = max(peak, float(row[1].strip()))
        except Exception:
            pass
ffprobe = {}
p = Path(mp4)
if p.exists() and p.stat().st_size > 1024:
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(p)],
            text=True,
        )
        ffprobe = json.loads(out)
    except Exception as e:
        ffprobe = {"error": str(e)}
    still = Path(outdir) / f"{label}.png"
    subprocess.call(["ffmpeg", "-y", "-ss", "1.5", "-i", str(p), "-frames:v", "1", str(still)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
blob = {
    "sku": sku,
    "label": label,
    "status": "ok" if rc == 0 and p.exists() and p.stat().st_size > 1024 else "fail",
    "exit_code": rc,
    "wall_s": round(wall, 3),
    "peak_vram_mib": peak,
    "peak_vram_gib": round(peak / 1024.0, 2) if peak else None,
    "mp4": str(p) if p.exists() else None,
    "mp4_bytes": p.stat().st_size if p.exists() else 0,
    "height": 768, "width": 1344, "num_frames": 124,
    "fps": 24, "seed": 42,
    "engine": "lightx2v minimax_h3 t2av",
    "lora": label,
    "ffprobe": ffprobe,
}
Path(outdir, f"{label}.json").write_text(json.dumps(blob, indent=2) + "\n")
print(json.dumps({k: blob[k] for k in ("label", "status", "wall_s", "peak_vram_gib", "mp4_bytes")}, indent=2))
sys.exit(0 if blob["status"] == "ok" else 1)
PY
}

CFG4="$ROOT/configs/t2av_4step_768p_offload.json"
CFG8="$ROOT/configs/t2av_8step_768p_offload.json"
CFGSLA="$ROOT/configs/t2av_4step_768p_sla_offload.json"

log "cold 4-step 768p"
run_one cold_4step "$CFG4" || true
log "warm 4-step 768p"
run_one warm_4step "$CFG4" || true

if [[ "$ADDONS_HEAVY" == "1" ]]; then
  log "warm 8-step 768p (studio)"
  run_one warm_8step "$CFG8" || true
  log "warm 4-step SLA"
  run_one warm_sla "$CFGSLA" || true
fi

python3 - "$OUT" "$SKU" <<'PY'
import json, sys
from pathlib import Path
outdir, sku = Path(sys.argv[1]), sys.argv[2]
rows = []
for p in sorted(outdir.glob("*.json")):
    if p.name in ("summary.json",):
        continue
    try:
        rows.append(json.loads(p.read_text()))
    except Exception:
        pass
summary = {
    "sku": sku,
    "engine": "lightx2v",
    "hf_id": "lightx2v/Minimax-h3-Turbo",
    "checkpoint": "minimax_h3_fl2v_turbo_4step_v1.2_768p_bf16",
    "addons": [
        "FL2VA Turbo 4-step v1.2 768p",
        "FL2VA Turbo 8-step v1.0 768p",
        "Ref2VA Turbo 4-step v0.1",
        "Ref2VA Turbo 8-step v1.0 768p",
        "Turbo SLA 4-step 768p",
        "Prompt Rewriter LoRA-8B + Qwen3-VL-8B",
        "SeedVR2-3B weights",
    ],
    "runs": rows,
}
(outdir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print("wrote", outdir / "summary.json")
PY

log "done"
touch "$OUT/DONE"
