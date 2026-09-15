#!/usr/bin/env bash
# Push the ComfyUI 4-step runner (the credited path) to a booted mc-bench-h3turbo-* VM.
set -euo pipefail
KEY="${MC_BENCH_SSH_KEY:-$HOME/.ssh/songtree_massedcompute}"
HF_TOKEN="${HF_TOKEN:-}"
if [[ -z "$HF_TOKEN" ]]; then
  tok=$(tr -d '[:space:]' < "$HOME/.cache/huggingface/token")
  HF_TOKEN=$tok
fi
IP="${1:?ip}"
SKU="${2:?sku}"
HEAVY="${3:-0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10)
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)

echo "wait SSH $IP"
for i in $(seq 1 90); do
  if "${SSH[@]}" "Ubuntu@$IP" "echo SSH_OK" >/dev/null 2>&1; then
    echo "SSH_OK try=$i"
    break
  fi
  sleep 10
  [[ "$i" -eq 90 ]] && { echo "no ssh"; exit 1; }
done

"${SSH[@]}" "Ubuntu@$IP" "mkdir -p ~/h3turbo-configs ~/mc-bench/scripts ~/.cache/huggingface"
"${SCP[@]}" "$HERE"/configs/*.json "Ubuntu@$IP:~/h3turbo-configs/"
"${SCP[@]}" "$HERE/bootstrap.sh" "$HERE/remote_bench.sh" "$HERE/remote_comfy_4step.sh" "Ubuntu@$IP:~/mc-bench/scripts/"
"${SSH[@]}" "Ubuntu@$IP" "chmod +x ~/mc-bench/scripts/*.sh && install -m 600 /dev/null ~/.cache/huggingface/token"
printf '%s' "$HF_TOKEN" | "${SSH[@]}" "Ubuntu@$IP" "cat > ~/.cache/huggingface/token"
"${SSH[@]}" "Ubuntu@$IP" "nohup env SKU=$SKU ADDONS_HEAVY=$HEAVY bash ~/mc-bench/scripts/remote_comfy_4step.sh >~/h3turbo-bench.log 2>&1 & echo BENCH_PID=\$!"
echo "started comfy 4-step $SKU $IP heavy=$HEAVY"
