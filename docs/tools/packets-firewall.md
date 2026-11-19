# Packet capture and firewall

Look at the actual packets, and at the kernel rules that route and filter them.

## `tcpdump`

**Package:** `tcpdump` · **Needs:** `NET_RAW`, which is in the default capabilities. Promiscuous mode needs
`NET_ADMIN`, so add `-p` to avoid it.

Captures packets on an interface and prints or saves them. Because you share the pod's network namespace, you
see exactly the traffic the app sends and receives, including loopback traffic between the app and a sidecar.

```sh
# Everything, all interfaces, numeric, no promiscuous mode
tcpdump -i any -nn -p

# One port, or one peer
tcpdump -i any -nn -p port 53
tcpdump -i any -nn -p host 10.244.2.9 and tcp port 8080

# Show HTTP request lines and bodies (plain HTTP only; TLS is encrypted)
tcpdump -i any -nn -p -A -s0 'tcp port 8080'

# Connection problems: SYNs and resets
tcpdump -i any -nn -p 'tcp[tcpflags] & (tcp-syn|tcp-rst) != 0'

# DNS queries and answers
tcpdump -i any -nn -p -vv port 53

# Stop after 100 packets
tcpdump -i any -nn -p -c 100 port 8080

# Save a capture to analyse later in Wireshark
tcpdump -i any -nn -p -s0 -w /tmp/capture.pcap 'port 8080'
```

Getting a capture file out of the pod is covered in the
[Wireshark recipe](../recipes.md#capture-traffic-and-open-it-in-wireshark).

Reading the output: `Flags [S]` is a SYN, `[S.]` a SYN-ACK, `[.]` an ACK, `[P.]` data, `[F.]` a FIN and `[R]` a
reset. A SYN with no SYN-ACK means the packet is being dropped or not answered (firewall, NetworkPolicy, wrong
IP). A `[R.]` straight back means nothing is listening on that port.

!!! note "Interface names"
    `-i any` is the right default. With some CNIs and service meshes traffic also appears on extra interfaces
    or on `lo`. Capturing on `any` (cooked capture) shows all of them but without Ethernet headers.

## `iptables`

**Package:** `iptables` · **Needs:** `NET_ADMIN` (use the `netadmin` profile, or `sysadmin` on a node)

Lists and changes IPv4 packet-filter and NAT rules. In an ordinary pod this table is almost empty. It becomes
interesting in two places:

- **Service meshes** (Istio, Linkerd) install redirect rules in the pod's namespace.
- **On a node**, `kube-proxy` (in iptables mode) implements Services with rules in the `nat` table.

```sh
iptables -t nat -L -n -v                       # NAT rules with packet counters
iptables -t nat -S KUBE-SERVICES | head        # (node) Service entry points
iptables-save | grep my-svc                    # (node) every rule mentioning a Service
iptables -t nat -L PREROUTING -n -v            # (pod with a mesh) redirect rules
```

!!! warning "Two variants: nft and legacy"
    Linux has two iptables back ends. `iptables` in this image is the **nft** variant; `iptables-legacy` is
    also installed. A node's rules are only visible through the variant its components use.
    If `iptables -t nat -S` shows nothing on a node that obviously has Services, try:

    ```sh
    iptables-legacy -t nat -S | head
    ```

    The same applies to `ip6tables` and `ip6tables-legacy`. The `nft list ruleset` command below shows
    everything in the nft back end, whichever tool created it.

## `nft`

**Package:** `nftables` · **Needs:** `NET_ADMIN`

The native interface to nftables. Newer clusters can run `kube-proxy` in nftables mode, and many CNIs and
distributions use nftables directly. It also shows rules created through `iptables-nft`.

```sh
nft list tables
nft list ruleset | less
nft list chain ip nat PREROUTING
nft list ruleset | grep my-svc
```

## `ipset`

**Package:** `ipset` · **Needs:** `NET_ADMIN`

Lists kernel IP sets: large collections of addresses that firewall rules match against. `kube-proxy` in IPVS
mode and several network-policy engines (for example Calico) use them.

```sh
ipset list -name              # names of all sets
ipset list KUBE-CLUSTER-IP    # members of one set
ipset test KUBE-CLUSTER-IP 10.96.0.10
```

## `conntrack`

**Package:** `conntrack` · **Needs:** `NET_ADMIN`

The kernel's connection tracking table. NAT for Services is stateful, so this table is where you see which
backend a connection was really sent to, and whether the table is full.

```sh
conntrack -L | head                          # all tracked connections
conntrack -L -p tcp --dport 8080             # only those to port 8080
conntrack -L -d 10.96.0.15                   # connections to a Service ClusterIP (shows the DNAT'd backend)
conntrack -C                                 # how many entries now
conntrack -S                                 # per-CPU statistics: look at insert_failed and drop
conntrack -E                                 # watch events live
```

Compare the count to the limit on the node:
`cat /proc/sys/net/netfilter/nf_conntrack_max`. If the table is full the kernel logs
*nf_conntrack: table full, dropping packet* and new connections fail intermittently. A rising `insert_failed` in
`conntrack -S` is the same problem showing up as a counter. In a pod you see the namespace's view. On a node you
see all connections.
