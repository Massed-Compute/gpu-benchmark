#!/usr/bin/env bash
# Copy the MiniCPM-V-4.7 runner to a disposable bench VM and start it detached.
# Token file is installed mode 600 before the copy. It is not placed on the ssh command line.
# Usage: deploy.sh <host> <sku>
# nohup keeps the run alive if this SSH session drops.
set -euo pipefail
HOST=${1:?host}
SKU=${2:?sku}
KEY=${MC_BENCH_SSH_KEY:-$HOME/.ssh/songtree_massedcompute}
TOKEN_SRC=${HF_TOKEN_FILE:-$HOME/.cache/huggingface/token}
ROOT=$(cd "$(dirname "$0")" && pwd)
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "Ubuntu@${HOST}")
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=accept-new)

"${SSH[@]}" 'mkdir -p ~/.cache/huggingface ~/mc-bench/bin ~/mc-bench/logs'
if [[ -f "$TOKEN_SRC" ]]; then
  "${SSH[@]}" 'install -m 600 /dev/null ~/.cache/huggingface/token'
  "${SCP[@]}" "$TOKEN_SRC" "Ubuntu@${HOST}:.cache/huggingface/token"
fi
"${SCP[@]}" "$ROOT/remote.sh" "Ubuntu@${HOST}:mc-bench/bin/remote.sh"
SKU_Q=$(printf '%q' "$SKU")
"${SSH[@]}" "chmod 700 ~/mc-bench/bin/remote.sh && nohup env SKU=${SKU_Q} bash ~/mc-bench/bin/remote.sh > ~/mc-bench/logs/minicpm-v-4.7-35b-a3b-${SKU_Q}.log 2>&1 < /dev/null & echo pid \$!"
echo "Remote run is detached under nohup."
echo "Poll log:  ssh -i ${KEY} Ubuntu@${HOST} 'tail -n 30 ~/mc-bench/logs/minicpm-v-4.7-35b-a3b-${SKU}.log'"
echo "Poll done: ssh -i ${KEY} Ubuntu@${HOST} 'test -f ~/mc-bench/out/minicpm-v-4.7-35b-a3b/${SKU}/bf16-vllm/DONE && echo DONE'"
