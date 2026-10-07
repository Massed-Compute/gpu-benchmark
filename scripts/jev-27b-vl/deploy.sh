#!/usr/bin/env bash
# Copy the JEV runner to a disposable bench VM and start it detached.
# Token file is installed mode 600. It is not placed on the ssh command line.
# Usage: deploy.sh <host> <sku>
# nohup keeps the run alive if this SSH session drops.
# Poll the log:  ssh -i "$KEY" "Ubuntu@<host>" 'tail -n 30 ~/mc-bench/logs/jev-<sku>.log'
# Poll completion: ssh -i "$KEY" "Ubuntu@<host>" 'test -f ~/mc-bench/out/jev-27b-vl/<sku>/bf16-vllm/DONE && echo DONE'
set -euo pipefail
HOST=${1:?host}
SKU=${2:?sku}
KEY=${MC_BENCH_SSH_KEY:-$HOME/.ssh/songtree_massedcompute}
TOKEN_SRC=${HF_TOKEN_FILE:-$HOME/.cache/huggingface/token}
ROOT=$(cd "$(dirname "$0")" && pwd)
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "Ubuntu@${HOST}")
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=accept-new)

"${SSH[@]}" 'mkdir -p ~/.cache/huggingface ~/mc-bench/bin'
if [[ -f "$TOKEN_SRC" ]]; then
  "${SSH[@]}" 'install -m 600 /dev/null ~/.cache/huggingface/token'
  "${SCP[@]}" "$TOKEN_SRC" "Ubuntu@${HOST}:.cache/huggingface/token"
fi
"${SCP[@]}" "$ROOT/remote.sh" "Ubuntu@${HOST}:mc-bench/bin/remote.sh"
SKU_Q=$(printf '%q' "$SKU")
"${SSH[@]}" "chmod 700 ~/mc-bench/bin/remote.sh && mkdir -p ~/mc-bench/logs && nohup env SKU=${SKU_Q} bash ~/mc-bench/bin/remote.sh > ~/mc-bench/logs/jev-${SKU_Q}.log 2>&1 < /dev/null & echo pid \$!"
echo "Remote run is detached under nohup. A dropped SSH session does not stop it."
echo "Poll log:  ssh -i ${KEY} Ubuntu@${HOST} 'tail -n 30 ~/mc-bench/logs/jev-${SKU}.log'"
echo "Poll done: ssh -i ${KEY} Ubuntu@${HOST} 'test -f ~/mc-bench/out/jev-27b-vl/${SKU}/bf16-vllm/DONE && echo DONE'"
