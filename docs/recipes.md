# Recipes

Start from the symptom. Each recipe assumes you attached with
`kubectl debug -it <pod> --image=ghcr.io/ngpayyappilly/k8s-debug:latest --target=<container>`.

## Connection refused or timing out

Work from the outside in. The failure mode tells you where to look.

```sh
# 1. What does the client actually see? (timing shows which phase is slow or failing)
curl -sv -m 5 -o /dev/null http://my-svc.my-ns.svc.cluster.local:8080/

# 2. Does the name resolve, and to what?
dig +short my-svc.my-ns.svc.cluster.local

# 3. Is the port reachable on the Service IP and on a backend pod IP directly?
nc -zv -w 3 <cluster-ip> 8080
kubectl get endpointslices -l kubernetes.io/service-name=my-svc -o wide
nc -zv -w 3 <pod-ip> 8080
```

| What you see | It usually means |
|---|---|
| `Connection refused` (immediate) | The IP is reachable but **nothing is listening** on that port. Check the app's port and `targetPort` |
| `timed out` | Packets are being **dropped**: NetworkPolicy, security group, wrong IP, or no route |
| Works on the pod IP, fails on the Service IP | `kube-proxy` or CNI Service handling. Check the Service has endpoints and the selector matches |
| Fails only from some pods | NetworkPolicy or node-specific problem. Repeat from a pod on another node |
| Name does not resolve | See [DNS](#dns-is-slow-or-failing) |

To prove packets leave the pod and whether anything answers:

```sh
tcpdump -i any -nn -p 'host <dest-ip> and tcp port 8080'
```

A SYN with no reply is a drop. An immediate `[R.]` is a refusal. See [`tcpdump`](tools/packets-firewall.md#tcpdump).
Then check on the **server** side whether the SYN arrived at all.

## DNS is slow or failing

```sh
cat /etc/resolv.conf                     # note nameserver and ndots
dig my-svc.my-ns.svc.cluster.local       # status and "Query time"
dig @10.96.0.10 example.com              # ask the cluster DNS directly
dig @8.8.8.8 example.com                 # compare with an upstream: is CoreDNS the problem?
tcpdump -i any -nn -p port 53            # watch queries and answers (and timeouts)
```

Common causes:

- **`ndots:5` amplification.** Looking up `api.example.com` first tries
  `api.example.com.my-ns.svc.cluster.local`, `...svc.cluster.local`, `...cluster.local` and only then the real
  name. Append a trailing dot (`api.example.com.`) to prove it, then fix with `dnsConfig: options: ndots: 2` on
  the pod, or fully qualify names in the app.
- **Intermittent 5-second delays** on lookups: classic conntrack race with parallel A and AAAA queries. Look for
  `insert_failed` in [`conntrack -S`](tools/packets-firewall.md#conntrack) on the node, or use a node-local DNS
  cache.
- **`SERVFAIL`**: the cluster DNS could not reach its upstream. Compare `dig @<coredns-ip>` with `dig @8.8.8.8`.
- **Large answers failing**: `dig +tcp` works but UDP does not, so check MTU and a firewall dropping fragments.

## TLS certificate problems

```sh
# What does the server present, and is it valid?
openssl s_client -connect my-svc.my-ns.svc:443 -servername my-svc.example.com </dev/null 2>&1 | grep -E 'subject|issuer|Verify|notAfter'

# Subject alternative names, dates, issuer
openssl s_client -connect my-svc:443 -servername my-svc.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName -dates -issuer

# What the client would say (error text is in curl's output)
curl -v https://my-svc.example.com/ 2>&1 | grep -iE 'ssl|tls|certificate|verify'
```

- `unable to get local issuer certificate`: the CA is not trusted here. Pass `--cacert` or install it (see
  [`python3`](tools/shell.md#python3) note on `update-ca-certificates`).
- `certificate has expired`: check `notAfter`. For a Secret-based certificate decode it as shown in
  [`openssl`](tools/connectivity.md#openssl).
- `hostname mismatch`: connect with the name in the certificate's SANs, or fix the SANs.
- Handshake works on a pod IP but not through a mesh or ingress: use `-servername` to send the right SNI.

## The pod is slow or being throttled

CPU throttling is invisible in `top`. Read the target's **cgroup**:

```sh
P=1                                                     # the app's PID in the shared namespace
cat /proc/$P/root/sys/fs/cgroup/cpu.max                 # "<quota> <period>", or "max 100000" for no limit
cat /proc/$P/root/sys/fs/cgroup/cpu.stat                # nr_throttled and throttled_usec: rising means throttling
cat /proc/$P/root/sys/fs/cgroup/memory.max
cat /proc/$P/root/sys/fs/cgroup/memory.current
cat /proc/$P/root/sys/fs/cgroup/memory.events           # oom_kill > 0 means it was OOM-killed
```

Then see where the time goes:

```sh
pidstat -u -w -p $P 1 5        # CPU and context switches
pidstat -d -p $P 1 5           # disk I/O
ss -ti dst <upstream-ip>       # TCP retransmits and RTT to a dependency
strace -c -f -p $P             # which system calls dominate (Ctrl-C after ~10 s)
```

!!! note
    These paths use cgroup v2, standard on current distributions. On cgroup v1 nodes the files are under
    `/sys/fs/cgroup/cpu/` and `/sys/fs/cgroup/memory/` (for example `cpu.cfs_quota_us`, `memory.limit_in_bytes`).

## The app hangs and nothing is logged

```sh
# Where is every thread right now?
gdb -p 1 -batch -ex 'thread apply all bt' -ex detach 2>&1 | less

# What is it waiting on? (stop after a few seconds with Ctrl-C)
strace -f -tt -T -p 1 2>&1 | head -50

# Is it stuck on a socket?
ss -tnp | grep -v LISTEN
lsof -p 1 | grep -E 'TCP|IPv4' | head
```

Many threads in `futex` mean lock contention or a deadlock. A thread in `read` or `recvfrom` on one connection
points at a dependency that never answers. A state of `D` in `ps` means it is stuck in the kernel on I/O.

## File descriptor or port problems

```sh
ls /proc/1/fd | wc -l                     # open descriptors now
grep 'open files' /proc/1/limits          # the limit
lsof -p 1 | awk '{print $5}' | sort | uniq -c | sort -rn     # by type: sock, REG, pipe...
ss -tn | awk '{print $1}' | sort | uniq -c                    # sockets per state
fuser -v 8080/tcp                                             # who owns the port
```

A `Too many open files` error with a count near the limit is a leak or a limit that is too low. Many
`CLOSE-WAIT` sockets mean the app is not closing connections.

## Read the app's files, config and environment

You do not need a shell in the app's image:

```sh
ls $(troot 1)/                              # same as ls /proc/1/root/
cat $(troot 1)/etc/app/config.yaml
tr '\0' '\n' < /proc/1/environ | sort       # its environment variables
cat /proc/1/cmdline | tr '\0' ' '; echo     # exact command line
ls -l /proc/1/cwd                           # current working directory
```

This also works on **distroless** and scratch images that have no shell. Mounted volumes, Secrets and ConfigMaps
appear at the same paths the app sees. `$(troot 1)` is the helper that prints `/proc/1/root`.

## Capture traffic and open it in Wireshark

Capturing inside the pod and saving to the debug container's disk is easy. Getting the file out is the part
that needs care. Create the container so it stays up, then stream the capture with `kubectl exec`:

```sh
# 1. A long-lived debug container named "capture"
kubectl debug <pod> -n <ns> --container=capture \
  --image=ghcr.io/ngpayyappilly/k8s-debug:latest --target=<container> -- sleep 3600

# 2. Stream packets straight to a local file (Ctrl-C to stop, or add -c <count>)
kubectl exec <pod> -n <ns> -c capture -- tcpdump -i any -U -nn -p -s0 -w - 'tcp port 8080' > capture.pcap

# 3. Open capture.pcap in Wireshark
```

Or write the file in the pod and copy it out:

```sh
kubectl exec <pod> -c capture -- tcpdump -i any -nn -p -s0 -c 500 -w /tmp/capture.pcap 'tcp port 8080'
kubectl cp <pod>:/tmp/capture.pcap ./capture.pcap -c capture
```

!!! warning "Use `exec`, not `kubectl debug -i`, for binary output"
    Streaming a capture through `kubectl debug -i ... -w -` can lose the data because the output is not
    attached to your terminal. Creating the container first and using `kubectl exec` is reliable.

Remember the capture contains whatever the traffic contains. TLS traffic is encrypted, but headers, SNI and
plaintext protocols are not. Delete the file when you are done.

## Check what the application's identity can do

```sh
P=1; S=/proc/$P/root/var/run/secrets/kubernetes.io/serviceaccount
alias ks='kubectl --server=https://kubernetes.default.svc --certificate-authority=$S/ca.crt --token="$(cat $S/token)"'
ks auth can-i --list -n "$(cat $S/namespace)"
```

See [`kubectl`](tools/kubernetes.md#kubectl) for why this borrowing is needed.

## Inspect Services and `kube-proxy` rules on a node

```sh
kubectl debug node/<node> -it --image=ghcr.io/ngpayyappilly/k8s-debug:latest --profile=sysadmin

iptables -t nat -S KUBE-SERVICES | grep my-svc         # the Service's entry rule
iptables-save | grep -A5 'my-svc'                      # follow the chain to the endpoints
iptables-legacy -t nat -S | head                       # if the above shows nothing
nft list ruleset | grep my-svc                         # nftables mode
conntrack -L -d <cluster-ip>                           # live connections and their chosen backend
nsenter -t 1 -m -u -i -n -p -- journalctl -u kubelet --since '10 min ago'
```

See [`iptables`](tools/packets-firewall.md#iptables) for the nft versus legacy distinction.

## Test a gRPC service

```sh
grpcurl -plaintext my-svc.my-ns.svc.cluster.local:50051 list
grpcurl -plaintext my-svc:50051 grpc.health.v1.Health/Check
grpcurl -plaintext -d '{"id": "42"}' my-svc:50051 my.pkg.Orders/Get
```

## Measure bandwidth between two pods

```sh
kubectl run iperf-server --image=ghcr.io/ngpayyappilly/k8s-debug:latest --restart=Never -- iperf3 -s
IP=$(kubectl get pod iperf-server -o jsonpath='{.status.podIP}')
# from the debug container in the pod under test:
iperf3 -c $IP -t 10
kubectl delete pod iperf-server
```

Run it same-node, cross-node and cross-zone, and compare. A big drop only when crossing nodes points at the
overlay network or MTU.
