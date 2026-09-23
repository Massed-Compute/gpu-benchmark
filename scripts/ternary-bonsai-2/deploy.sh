#!/usr/bin/env bash
# Deploy Ternary Bonsai 2 GGUF llama-bench remote to one mc-bench VM.
set -euo pipefail
KEY="${MC_BENCH_SSH_KEY:-$HOME/.ssh/songtree_massedcompute}"
IP="${1:?ip}"
SKU="${2:?sku}"
CUDA_ARCHS="${3:?cuda arch e.g. 86 or 89 or 120}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o BatchMode=yes -o ConnectTimeout=15)
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts" -o BatchMode=yes)

echo "wait SSH $IP $SKU"
for i in $(seq 1 90); do
  if "${SSH[@]}" "Ubuntu@$IP" "echo SSH_OK" >/dev/null 2>&1; then
    echo "SSH_OK try=$i"
    break
  fi
  sleep 10
  [[ "$i" -eq 90 ]] && { echo "no ssh"; exit 1; }
done

"${SSH[@]}" "Ubuntu@$IP" "mkdir -p ~/mc-bench/scripts ~/.cache/huggingface"
"${SCP[@]}" "$HERE/remote.sh" "Ubuntu@$IP:~/mc-bench/scripts/remote_ternary_bonsai2.sh"
"${SSH[@]}" "Ubuntu@$IP" "chmod +x ~/mc-bench/scripts/*.sh && install -m 600 /dev/null ~/.cache/huggingface/token"

if [[ -z "${HUGGING_FACE_HUB_TOKEN:-}" && -f "$HOME/.cache/huggingface/token" ]]; then
  tok=$(tr -d '[:space:]' < "$HOME/.cache/huggingface/token")
  export HUGGING_FACE_HUB_TOKEN="$tok"
fi
if [[ -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
  printf '%s' "$HUGGING_FACE_HUB_TOKEN" | "${SSH[@]}" "Ubuntu@$IP" "cat > ~/.cache/huggingface/token"
fi

"${SSH[@]}" "Ubuntu@$IP" "nohup env SKU=$SKU CUDA_ARCHS=$CUDA_ARCHS bash ~/mc-bench/scripts/remote_ternary_bonsai2.sh >~/mc-bench/bench.log 2>&1 & echo BENCH_PID=\$!"
echo "started $SKU $IP arch=$CUDA_ARCHS"
