#!/usr/bin/env bash
# Smoke-test a built k8s-debug image.
#
#   scripts/smoke-test.sh [image] [--db-clients]
#
# Checks (all inside ONE container, so it costs a single container start):
#   1. every advertised tool exists on PATH
#   2. tools that matter during an incident actually execute (catches
#      wrong-arch downloads and missing shared libraries, which `command -v`
#      cannot)
#   3. pinned tool versions match the ARGs in the Dockerfile
#   4. the interactive shell config loads (alias, completion, banner)
# --db-clients additionally requires redis-cli, psql and mysql (image built
# with INSTALL_DB_CLIENTS=true).
set -euo pipefail

IMAGE="k8s-debug:dev"
DB_CLIENTS=false
for a in "$@"; do
  case "$a" in
    --db-clients) DB_CLIENTS=true ;;
    *) IMAGE="$a" ;;
  esac
done

DOCKERFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Dockerfile"
arg() { sed -n "s/^ARG $1=//p" "$DOCKERFILE" | head -n1; }

# --- Test body: runs inside the container. Prints FAIL lines, exits non-zero.
read -r -d '' BODY <<'INNER' || true
fail=0
bad() { echo "FAIL: $*"; fail=1; }

tools="curl wget dig nslookup drill ping traceroute mtr tcpdump nmap ncat nc socat
  ss ip iptables nft conntrack ethtool iperf3 openssl
  strace ltrace gdb lsof htop pidstat iostat iotop bpftrace ps
  jq yq kubectl stern grpcurl git ssh python3 vi nano"
[ "$DB_CLIENTS" = true ] && tools="$tools redis-cli psql mysql"
for t in $tools; do command -v "$t" >/dev/null || bad "missing tool: $t"; done

# Must execute, not just exist.
run() { "$@" >/dev/null 2>&1 || bad "does not run: $*"; }
run kubectl version --client
run yq --version
run stern --version
run grpcurl -version
run jq --version
run tcpdump --version
run strace -V
run gdb --version
run bpftrace --version
run nmap --version
run dig -v
run openssl version
run iperf3 --version
run python3 --version

# Pinned versions must match the Dockerfile ARGs.
ver() { # <label> <expected> <command...>
  local label=$1 want=${2#v}; shift 2
  "$@" 2>&1 | grep -qF "$want" || bad "$label version is not $want"
}
ver kubectl "$KUBECTL_VERSION" kubectl version --client
ver yq      "$YQ_VERSION"      yq --version
ver stern   "$STERN_VERSION"   stern --version
ver grpcurl "$GRPCURL_VERSION" grpcurl -version

# Interactive shell config: alias, completion, banner.
out=$(bash -i <<<'type k; complete -p k' 2>&1 || true)
grep -q "k is aliased to" <<<"$out" || bad "bashrc not loaded (alias k)"
grep -q "__start_kubectl" <<<"$out" || bad "kubectl completion not registered for k"
grep -q "k8s-debug ephemeral container" <<<"$out" || bad "motd banner not shown"

# Non-interactive shells must stay quiet (scripts / kubectl exec -- bash -c).
[ -z "$(bash -c 'true' 2>&1)" ] || bad "non-interactive shell printed output"

exit $fail
INNER

if docker run --rm -i --entrypoint bash \
    -e DB_CLIENTS="$DB_CLIENTS" \
    -e KUBECTL_VERSION="$(arg KUBECTL_VERSION)" \
    -e YQ_VERSION="$(arg YQ_VERSION)" \
    -e STERN_VERSION="$(arg STERN_VERSION)" \
    -e GRPCURL_VERSION="$(arg GRPCURL_VERSION)" \
    "$IMAGE" -c "$BODY"; then
  echo "smoke test passed for $IMAGE ($(docker run --rm --entrypoint uname "$IMAGE" -m))"
else
  echo "smoke test FAILED for $IMAGE"
  exit 1
fi
