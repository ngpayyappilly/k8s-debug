# Network stack

Inspect the pod's interfaces, addresses, routes, sockets and neighbours. These all show the **pod's** network
namespace (not the node's), unless you debug a node, in which case they show the node's.

## `ip`

**Package:** `iproute2` · **Needs:** nothing to read; `NET_ADMIN` to change anything

The modern replacement for `ifconfig`, `route` and `arp`.

```sh
ip -br addr               # brief: interface, state, addresses
ip addr show eth0         # full detail, including MTU
ip route                  # the routing table
ip route get 10.96.0.10   # which route and source address would be used for this destination?
ip neigh                  # ARP / neighbour table (is the next hop resolved?)
ip -s link show eth0      # packet, error and drop counters
ip -d link show eth0      # details, including veth peer information
```

What to look for:

- **MTU.** `eth0` is often 1500 on the node but 1450 or lower in the pod with an overlay network (VXLAN,
  Geneve, WireGuard). A mismatch causes hangs on large responses while small ones work.
- **Errors and drops** in `ip -s link`. Rising `dropped` or `errors` point at the interface or CNI.
- **`ip route get <dest>`** is the fastest way to see whether traffic would go out via `eth0`, a service mesh
  interface, or nowhere.
- **`ip neigh`** entries in `FAILED` or `INCOMPLETE` mean the next hop is not answering ARP.

## `ss`

**Package:** `iproute2` · **Needs:** nothing special. Process names need `--target` and, for other users'
sockets, `SYS_PTRACE` (in the default profile).

Socket statistics, a faster and more capable `netstat`.

```sh
ss -tulpn                         # listening TCP/UDP sockets and the process that owns each
ss -tnp                           # established TCP connections with processes
ss -s                             # summary: how many sockets in each state
ss -tn state established '( dport = :5432 or sport = :5432 )'   # connections to/from Postgres
ss -tn state time-wait | wc -l    # TIME_WAIT pile-up?
ss -ti dst 10.244.2.9             # TCP internals: RTT, retransmits, congestion window
ss -tlnp 'sport = :8080'          # is anything listening on 8080?
```

- A `Recv-Q` that stays large on a LISTEN socket means the app is not calling `accept()` fast enough.
- A large `Send-Q` on an established connection means the peer is not reading or the network is stalled.
- Many `CLOSE-WAIT` sockets mean the app is not closing connections after the peer did (a leak in the app).
- `ss -ti` fields such as `retrans` and `rtt` show whether a path is lossy or slow.

## `arping`

**Package:** `arping` · **Needs:** `NET_RAW`

Sends ARP requests at layer 2. Use it when `ping` fails and you want to know if the neighbour exists at all, or
to detect a duplicate IP address.

```sh
arping -I eth0 -c 3 10.244.2.1       # does the gateway answer ARP?
arping -D -I eth0 -c 2 10.244.2.9    # duplicate address detection for your own IP
```

ARP only works within one L2 segment. Many CNIs route at L3, so a non-answer from a remote pod is normal.

## `ethtool`

**Package:** `ethtool` · **Needs:** nothing to read; `NET_ADMIN` to change

Driver and hardware-level details of an interface.

```sh
ethtool -i eth0                       # driver (veth, virtio_net, ena, ...)
ethtool -S eth0                       # NIC statistics, including drops and queue counters
ethtool -S eth0 | grep peer_ifindex   # for a veth: the index of the other end on the node
ethtool -k eth0                       # offload features (checksum, TSO, GRO)
```

`peer_ifindex` is the number to look for in `ip link` **on the node** (via a node debug session) to find which
host interface belongs to this pod. Not every driver exposes the counters you want inside a container.

## `ifconfig`

**Package:** `net-tools` · **Needs:** nothing special

The legacy interface viewer. It is installed for muscle memory and for scripts. Prefer [`ip`](#ip).

```sh
ifconfig eth0
```

## `netstat`

**Package:** `net-tools` · **Needs:** nothing special

Legacy socket listing. Prefer [`ss`](#ss), which is faster and shows more. `net-tools` also provides `route`
and `arp`.

```sh
netstat -tulpn
netstat -rn          # routing table
```

## `brctl`

**Package:** `bridge-utils` · **Needs:** nothing special to read

Lists Linux bridges. A pod's own namespace usually has none. It is most useful on a **node** session, where
CNIs such as `bridge`, Flannel and kind attach pod veths to a bridge.

```sh
brctl show                 # bridges and their attached interfaces
```

For modern bridge inspection also use `ip link show type bridge` and `bridge link`, which are part of
`iproute2`.
