# Tools

Every utility in the image, grouped by what you are trying to find out. Each section lists the Ubuntu
package it comes from, the permissions it needs (see [Permissions](../getting-started/permissions.md)), and
examples written for Kubernetes situations.

| Page | Tools |
|---|---|
| [HTTP and connectivity](connectivity.md) | [`curl`](connectivity.md#curl) [`wget`](connectivity.md#wget) [`nc`](connectivity.md#nc) [`ncat`](connectivity.md#ncat) [`socat`](connectivity.md#socat) [`openssl`](connectivity.md#openssl) [`iperf3`](connectivity.md#iperf3) [`ping`](connectivity.md#ping) [`tracepath`](connectivity.md#tracepath) [`traceroute`](connectivity.md#traceroute) [`mtr`](connectivity.md#mtr) [`nmap`](connectivity.md#nmap) |
| [DNS](dns.md) | [`dig`](dns.md#dig) [`nslookup`](dns.md#nslookup) [`drill`](dns.md#drill) |
| [Network stack](network-stack.md) | [`ip`](network-stack.md#ip) [`ss`](network-stack.md#ss) [`arping`](network-stack.md#arping) [`ethtool`](network-stack.md#ethtool) [`ifconfig`](network-stack.md#ifconfig) [`netstat`](network-stack.md#netstat) [`brctl`](network-stack.md#brctl) |
| [Packet capture and firewall](packets-firewall.md) | [`tcpdump`](packets-firewall.md#tcpdump) [`iptables`](packets-firewall.md#iptables) [`nft`](packets-firewall.md#nft) [`ipset`](packets-firewall.md#ipset) [`conntrack`](packets-firewall.md#conntrack) |
| [Processes and system](processes.md) | [`ps`](processes.md#ps) [`pgrep`](processes.md#pgrep) [`top`](processes.md#top) [`free`](processes.md#free) [`vmstat`](processes.md#vmstat) [`htop`](processes.md#htop) [`lsof`](processes.md#lsof) [`fuser`](processes.md#fuser) [`pstree`](processes.md#pstree) [`pidstat`](processes.md#pidstat) [`iostat`](processes.md#iostat) [`mpstat`](processes.md#mpstat) [`iotop`](processes.md#iotop) [`strace`](processes.md#strace) [`ltrace`](processes.md#ltrace) [`gdb`](processes.md#gdb) [`bpftrace`](processes.md#bpftrace) [`nsenter`](processes.md#nsenter) [`lsns`](processes.md#lsns) [`findmnt`](processes.md#findmnt) [`dmesg`](processes.md#dmesg) [`lsmod`](processes.md#lsmod) [`lspci`](processes.md#lspci) |
| [Kubernetes and data](kubernetes.md) | [`kubectl`](kubernetes.md#kubectl) [`stern`](kubernetes.md#stern) [`grpcurl`](kubernetes.md#grpcurl) [`yq`](kubernetes.md#yq) [`jq`](kubernetes.md#jq) |
| [Shell and files](shell.md) | [`bash`](shell.md#bash) [`vi`](shell.md#vi) [`nano`](shell.md#nano) [`less`](shell.md#less) [`file`](shell.md#file) [`tree`](shell.md#tree) [`unzip`](shell.md#unzip) [`xz`](shell.md#xz) [`git`](shell.md#git) [`ssh`](shell.md#ssh) [`gpg`](shell.md#gpg) [`python3`](shell.md#python3) |

## Conventions used in the examples

- `<pod>`, `<ns>`, `<pid>` and similar are placeholders.
- `<pid>` means a process ID **as seen from the debug container**. With `--target`, the app's processes are
  visible, so find it with `pgrep` or `ps`. In most containers the app is PID 1.
- `/proc/<pid>/root` is the target container's filesystem. The shell helper `troot <pid>` prints that path.
- "Needs" lines describe the minimum. Where it says *nothing special*, the default profile is enough.

## Tool versions

The four standalone binaries are pinned in the [Dockerfile](https://github.com/ngpayyappilly/k8s-debug/blob/main/Dockerfile)
and checksum verified. Everything else is whatever Ubuntu 24.04 ships.

| Tool | Version |
|---|---|
| `kubectl` | v1.36.1 |
| `yq` (mikefarah) | v4.47.1 |
| `grpcurl` | 1.9.3 |
| `stern` | 1.33.0 |

For the exact version of any other tool in a given image tag:

```sh
docker run --rm --entrypoint dpkg ghcr.io/ngpayyappilly/k8s-debug:<tag> -l
```

## Not installed, and what to do instead

The image favours tools that work in any pod. Language-specific profilers are not included because they must
match the target runtime.

| You want | Do this |
|---|---|
| Java thread or heap dumps | Use a JDK-based debug image, or `kubectl debug --copy-to` with the JDK image |
| Go `pprof` / `delve` | Expose `net/http/pprof` and use `curl` to fetch profiles |
| `perf` | Not usable from a container without matching kernel tools. Use [`bpftrace`](processes.md#bpftrace) or [`strace -c`](processes.md#strace) |
| Wireshark GUI | Capture with [`tcpdump`](packets-firewall.md#tcpdump), stream the file out, open it locally ([recipe](../recipes.md#capture-traffic-and-open-it-in-wireshark)) |

You can also build your own image on top of this one. See [Contributing](../contributing.md#extend-the-image-for-your-own-needs).
