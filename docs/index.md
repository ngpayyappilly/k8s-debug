# k8s-debug

A container image packed with debugging tools, built to be attached to a **running pod** (or node) with
`kubectl debug`, so you can investigate live without rebuilding or restarting anything.

Production images should stay small and locked down: no shell, no `curl`, no `tcpdump`. When something goes
wrong you still need those tools. `kubectl debug` adds a temporary
[ephemeral container](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/) to the pod
that shares its network (and, optionally, its processes), and this image is what you run in it.

## 30-second start

```sh
kubectl debug -it <pod> -n <namespace> \
  --image=ghcr.io/ngpayyappilly/k8s-debug:latest \
  --target=<container>
```

You land in a shell inside the pod's network namespace, with the target container's processes visible:

```text
 k8s-debug ephemeral container
 ------------------------------------------------------------------
  Network   dig nslookup curl nc socat tcpdump nmap mtr traceroute ss ip ...
  Process   ps top htop strace ltrace gdb lsof bpftrace pidstat iostat ...
  K8s       kubectl (k) stern grpcurl yq jq
 ...
[debug] my-pod:~ #
```

!!! tip "Is this your first time?"
    Read [Installation](getting-started/installation.md) for every way to run it (attach to a pod, copy a
    crashing pod, debug a node, run locally with Docker), then
    [Permissions and profiles](getting-started/permissions.md) to understand what the container is allowed to do.

## What is in the box

| Area | Tools | Page |
|---|---|---|
| HTTP and connectivity | `curl` `wget` `nc` `ncat` `socat` `openssl` `iperf3` `ping` `tracepath` `traceroute` `mtr` `nmap` | [Connectivity](tools/connectivity.md) |
| DNS | `dig` `nslookup` `drill` | [DNS](tools/dns.md) |
| Network stack | `ip` `ss` `arping` `ethtool` `ifconfig` `netstat` `brctl` | [Network stack](tools/network-stack.md) |
| Packet capture and firewall | `tcpdump` `iptables` `nft` `ipset` `conntrack` | [Packets and firewall](tools/packets-firewall.md) |
| Processes and system | `ps` `top` `htop` `lsof` `strace` `ltrace` `gdb` `bpftrace` `pidstat` `iostat` `nsenter` ... | [Processes](tools/processes.md) |
| Kubernetes and data | `kubectl` `stern` `grpcurl` `yq` `jq` | [Kubernetes](tools/kubernetes.md) |
| Shell and files | `bash` `vi` `nano` `less` `git` `ssh` `python3` ... | [Shell](tools/shell.md) |

Every tool has its own section with what it is for, copy-pasteable examples for Kubernetes situations, and
the permissions it needs.

## Looking for a task, not a tool?

The [Recipes](recipes.md) page is organised by symptom: *connection refused*, *DNS is slow*, *the pod is
being throttled*, *capture traffic and open it in Wireshark*, *read the app's config from its own filesystem*.

## Image facts

- **Registry:** `ghcr.io/ngpayyappilly/k8s-debug` (public, no login required)
- **Platforms:** `linux/amd64`, `linux/arm64`
- **Base:** Ubuntu 24.04 (glibc, so `gdb`, `strace` and `bpftrace` behave)
- **Size:** about 740 MB. Pre-pull it on nodes if you debug under time pressure.
- **Runs as:** root by default. See [Permissions](getting-started/permissions.md#pods-that-run-as-non-root).
- **Source:** [github.com/ngpayyappilly/k8s-debug](https://github.com/ngpayyappilly/k8s-debug)

!!! warning "Be deliberate with production"
    Ephemeral containers cannot be removed from a pod once added, and an interactive session is recorded in
    the container logs, including anything you type. Treat a debug session like a change to production.
