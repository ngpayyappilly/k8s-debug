# k8s-debug

Ubuntu 24.04 image for `kubectl debug` ephemeral containers. Multi-arch (amd64 + arm64).

**Tools:** curl, wget, dig/nslookup/drill, ping, traceroute, mtr, tcpdump, nmap, ncat/nc, socat, ss/ip, iptables/nft, conntrack, ethtool, iperf3, openssl, strace, ltrace, gdb, lsof, htop, sysstat (pidstat/iostat), iotop, bpftrace, jq, yq, kubectl, stern, grpcurl, git, ssh, python3, vi/nano.

## Build and push

```sh
# local test
docker build -t k8s-debug:dev .

# multi-arch push (clusters are usually amd64, your Mac is arm64)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <registry>/k8s-debug:1.0.0 --push .

# optional: include redis/postgres/mysql CLI clients
docker buildx build --build-arg INSTALL_DB_CLIENTS=true ...
```

Bump `KUBECTL_VERSION` etc. via `--build-arg` (keep kubectl within one minor of your cluster).

## Use it

```sh
# Attach to a running pod, sharing the app container's process namespace
kubectl debug -it <pod> -n <ns> --image=<registry>/k8s-debug:1.0.0 \
  --target=<container> --profile=general
```

| Need | Profile | Grants |
|---|---|---|
| `ps`, `/proc/<pid>/root`, `strace` | `general` | `SYS_PTRACE` |
| `tcpdump`, `iptables`, raw sockets | `netadmin` | `NET_ADMIN`, `NET_RAW` |
| everything / node-level | `sysadmin` | privileged |

Some tools need both ptrace and network caps. Profiles can't be combined, so use `netadmin` plus a custom patch, or `sysadmin` for a short session:

```sh
kubectl debug -it <pod> --image=... --target=<container> \
  --custom=caps.json --profile=general
# caps.json: {"securityContext":{"capabilities":{"add":["SYS_PTRACE","NET_ADMIN","NET_RAW"]}}}
```

Other modes:

```sh
# Debug a crashing pod: copy it and swap in the debug image / override command
kubectl debug <pod> -it --copy-to=<pod>-debug --image=<registry>/k8s-debug:1.0.0 --share-processes

# Debug a node (host fs mounted at /host)
kubectl debug node/<node> -it --image=<registry>/k8s-debug:1.0.0 --profile=sysadmin
```

## Gotchas

- **Ephemeral containers can't be removed** from a pod once added; they go away when the pod does. Exit the shell and it stays `Terminated`.
- Without `--target`, you share the network namespace but **not** the process namespace.
- `--target` needs runtime support (containerd and CRI-O are fine).
- With a restrictive Pod Security Admission level (`restricted`), the capability profiles above will be rejected.
- Target's filesystem: `ls /proc/<pid>/root/` (needs ptrace access to that PID).
- The image runs as root. Don't push it to a public registry if you bake in credentials or internal tooling.
- Image is ~740MB; pre-pull it onto nodes or host it in a registry close to the cluster for fast attach.
