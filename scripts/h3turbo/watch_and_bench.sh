#!/usr/bin/env bash
# After DONE_WEIGHTS, start remote_bench on each host once.
# MC_BENCH_HOSTS='ip:sku:heavy ip:sku:heavy'  heavy is 0 or 1
set -euo pipefail
KEY="${MC_BENCH_SSH_KEY:-$HOME/.ssh/songtree_massedcompute}"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10)
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
: "${MC_BENCH_HOSTS:?set MC_BENCH_HOSTS='ip:sku:heavy ...'}"
read -r -a hosts <<<"$MC_BENCH_HOSTS"
HERE="$(cd "$(dirname "$0")" && pwd)"

while true; do
  all_done=1
  for row in "${hosts[@]}"; do
    ip=${row%%:*}
    rest=${row#*:}
    sku=${rest%%:*}
    heavy=${rest#*:}
    marker=$("${SSH[@]}" "Ubuntu@$ip" 'if [[ -f ~/mc-bench/out/h3turbo/DONE ]]; then echo BENCH_DONE; elif [[ -f ~/mc-bench/out/h3turbo/DONE_WEIGHTS ]]; then echo WEIGHTS_DONE; elif pgrep -f "[r]emote_bench.sh" >/dev/null; then echo BENCH_RUN; else echo WAIT; fi' || echo DOWN)
    echo "$(date -u +%H:%M:%S) $sku $ip $marker"
    if [[ "$marker" == "WEIGHTS_DONE" ]]; then
      "${SCP[@]}" "$HERE/remote_bench.sh" "Ubuntu@$ip:~/mc-bench/scripts/remote_bench.sh"
      "${SSH[@]}" "Ubuntu@$ip" "chmod +x ~/mc-bench/scripts/remote_bench.sh; nohup env SKU=$sku ADDONS_HEAVY=$heavy bash ~/mc-bench/scripts/remote_bench.sh >~/h3turbo-bench.log 2>&1 & echo BENCH_PID=\$!"
    fi
    [[ "$marker" == "BENCH_DONE" ]] || all_done=0
  done
  [[ "$all_done" == "1" ]] && break
  sleep 90
done
echo ALL_BENCH_DONE
