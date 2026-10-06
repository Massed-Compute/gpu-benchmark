#!/usr/bin/env bash
# Copy the JEV runner to a disposable bench VM and run it.
# Token file is installed mode 600. It is not placed on the ssh command line.
# Usage: deploy.sh <host> <sku>
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
"${SSH[@]}" "chmod 700 ~/mc-bench/bin/remote.sh && SKU=$(printf '%q' "$SKU") bash ~/mc-bench/bin/remote.sh"
