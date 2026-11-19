#!/usr/bin/env bash
# Smoke-test a built k8s-debug image: every advertised tool must exist and
# the pinned binaries must run. Usage: scripts/smoke-test.sh [image]
set -euo pipefail

IMAGE="${1:-k8s-debug:dev}"

TOOLS=(
  # HTTP and connectivity
  curl wget nc ncat socat openssl iperf3 ping tracepath traceroute mtr nmap
  # DNS
  dig nslookup drill
  # network stack
  ip ss arping ethtool ifconfig netstat brctl
  # packet capture and firewall
  tcpdump iptables nft ipset conntrack
  # processes and system
  ps pgrep top free vmstat htop lsof fuser pstree pidstat iostat mpstat iotop
  strace ltrace gdb bpftrace nsenter lsns findmnt dmesg lsmod lspci
  # kubernetes and data
  kubectl stern grpcurl yq jq
  # shell and files
  bash vi nano less file tree unzip xz git ssh gpg python3
)

fail=0
for t in "${TOOLS[@]}"; do
  if ! docker run --rm --entrypoint bash "$IMAGE" -c "command -v $t" >/dev/null; then
    echo "MISSING: $t"
    fail=1
  fi
done

# Binaries that should actually execute (catches wrong-arch downloads).
run() { docker run --rm --entrypoint bash "$IMAGE" -c "$1" >/dev/null || { echo "FAILED: $1"; fail=1; }; }
run "kubectl version --client"
run "yq --version"
run "stern --version"
run "grpcurl -version"
run "tcpdump --version"
run "jq --version"

# Interactive shell loads our rc file (alias k, banner).
out=$(docker run --rm -i "$IMAGE" -i <<<'type k' 2>&1 || true)
grep -q "k is aliased to" <<<"$out" || { echo "FAILED: bashrc not loaded"; fail=1; }

if [ "$fail" -ne 0 ]; then
  echo "smoke test FAILED for $IMAGE"
  exit 1
fi
echo "smoke test passed for $IMAGE ($(docker run --rm --entrypoint uname "$IMAGE" -m))"
