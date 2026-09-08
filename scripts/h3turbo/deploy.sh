#!/usr/bin/env bash
# Push bootstrap + configs to a booted mc-bench-h3turbo-* VM and start downloads.
set -euo pipefail
KEY="${MC_BENCH_SSH_KEY:-$HOME/.ssh/songtree_massedcompute}"
HF_TOKEN="${HF_TOKEN:-$(cat "$HOME/.cache/huggingface/token")}"
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

"${SSH[@]}" "Ubuntu@$IP" "mkdir -p ~/h3turbo-configs ~/mc-bench/scripts"
"${SCP[@]}" "$HERE"/configs/*.json "Ubuntu@$IP:~/h3turbo-configs/"
"${SCP[@]}" "$HERE/bootstrap.sh" "$HERE/remote_bench.sh" "Ubuntu@$IP:~/mc-bench/scripts/"
"${SSH[@]}" "Ubuntu@$IP" "chmod +x ~/mc-bench/scripts/*.sh && mkdir -p ~/.cache/huggingface"
printf '%s' "$HF_TOKEN" | "${SSH[@]}" "Ubuntu@$IP" "cat > ~/.cache/huggingface/token && chmod 600 ~/.cache/huggingface/token"
"${SSH[@]}" "Ubuntu@$IP" "nohup env SKU=$SKU ADDONS_HEAVY=$HEAVY HF_TOKEN=\$(cat ~/.cache/huggingface/token) bash ~/mc-bench/scripts/bootstrap.sh >~/h3turbo-bootstrap.log 2>&1 & echo BOOTSTRAP_PID=\$!"
echo "started bootstrap $SKU $IP heavy=$HEAVY"
