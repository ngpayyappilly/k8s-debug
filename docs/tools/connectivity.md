# HTTP and connectivity

Tools for answering *can A reach B, and what happens when it does?* from inside the pod's network namespace.
Because the debug container shares the pod's network, `localhost` is the app, and the pod's DNS, routes,
NetworkPolicy and service mesh sidecar all apply to your commands exactly as they do to the app.

## `curl`

**Package:** `curl` · **Needs:** nothing special

The default tool for HTTP, HTTPS and many other protocols. Use it to check an endpoint, see headers, and
break a request into timing phases.

```sh
# Call a Service by its cluster DNS name, show request and response headers
curl -sv http://my-svc.my-ns.svc.cluster.local:8080/healthz

# Where does the time go? DNS, TCP connect, TLS, first byte, total
curl -o /dev/null -s -w 'dns=%{time_namelookup} connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' \
  https://my-svc.my-ns.svc.cluster.local/

# Talk to one specific backend, ignoring DNS and load balancing
curl --resolve my-svc.example.com:443:10.244.1.17 https://my-svc.example.com/

# Same, but set the Host header instead (plain HTTP)
curl -H 'Host: my-svc.example.com' http://10.244.1.17:8080/

# Trust an internal CA
curl --cacert /path/to/ca.crt https://internal.example.com/

# Hit the app on localhost, the way a sidecar or probe would
curl -s localhost:8080/metrics | head
```

Tip: `curl -w '%{http_code}\n' -o /dev/null -s <url>` is a quick liveness check in a loop:
`while sleep 1; do curl -s -o /dev/null -w '%{http_code} ' <url>; done`.

## `wget`

**Package:** `wget` · **Needs:** nothing special

A simpler downloader, useful when you want to save a file or when a script expects `wget`.

```sh
wget -qO- http://my-svc:8080/healthz          # print the body
wget --spider -S http://my-svc:8080/          # headers only, no download
wget --no-check-certificate https://my-svc/   # skip TLS verification (diagnosis only)
```

## `nc`

**Package:** `netcat-openbsd` · **Needs:** nothing special

The OpenBSD `netcat`. The fastest way to test whether a TCP or UDP port accepts connections, without speaking
any protocol.

```sh
# Is the port open? (-z scan only, -v verbose, -w timeout seconds)
nc -zv -w 3 postgres.db.svc.cluster.local 5432

# Several ports, or a range
nc -zv -w 2 my-svc 80 443
nc -zv -w 1 my-svc 8000-8100 2>&1 | grep succeeded

# UDP (best effort, UDP has no handshake)
nc -zvu -w 2 10.96.0.10 53

# Send a raw HTTP request
printf 'GET /healthz HTTP/1.0\r\nHost: my-svc\r\n\r\n' | nc -w 3 my-svc 8080

# Listen on a port, for testing NetworkPolicy from the other side
nc -l -p 9000
```

`nc` is this one. `ncat` (below) is a different program with extra features such as TLS.

## `ncat`

**Package:** `ncat` (from the Nmap project) · **Needs:** nothing special

A feature-rich netcat. Choose it over `nc` when you need TLS, proxies, access control, or a listener that
serves many clients.

```sh
# Connect with TLS and speak a protocol by hand
ncat --ssl my-svc.my-ns.svc.cluster.local 443

# Listener that stays up for many connections and echoes what it receives
ncat -l -k 9000 --exec /bin/cat

# Listen with TLS (self-signed certificate generated for you)
ncat -l --ssl 9443

# Connect through an HTTP proxy
ncat --proxy proxy.example.com:3128 --proxy-type http target.example.com 443
```

## `socat`

**Package:** `socat` · **Needs:** nothing special

A multipurpose relay. It connects any two "addresses": TCP, UDP, Unix sockets, files, stdin, TLS, and more.

```sh
# Forward a port inside the pod (a quick relay; use to prove a path works)
socat TCP-LISTEN:9000,fork,reuseaddr TCP:my-svc.my-ns.svc.cluster.local:80

# Same, and print everything that passes through (-v), a poor man's proxy
socat -v TCP-LISTEN:9000,fork TCP:my-svc:80

# Talk to a Unix socket in the target container's filesystem
socat - UNIX-CONNECT:/proc/<pid>/root/var/run/app.sock

# Interactive TCP client with line editing
socat READLINE TCP:my-svc:6379
```

!!! note
    A relay started here only exists inside this pod's network namespace. To reach it from your laptop use
    `kubectl port-forward <pod> 9000` in another terminal.

## `openssl`

**Package:** `openssl` · **Needs:** nothing special

TLS inspection: what certificate does a server present, is it valid, who issued it, when does it expire.

```sh
# What certificate does the server present? (-servername sets SNI, important behind shared IPs)
openssl s_client -connect my-svc.my-ns.svc:443 -servername my-svc.example.com </dev/null

# Summarise it: subject, issuer, validity dates, SANs
openssl s_client -connect my-svc:443 -servername my-svc.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# Will it expire within 7 days? (exit status 1 means yes)
openssl s_client -connect my-svc:443 </dev/null 2>/dev/null | openssl x509 -noout -checkend 604800

# Show the whole chain the server sends
openssl s_client -connect my-svc:443 -showcerts </dev/null

# Mutual TLS: present a client certificate
openssl s_client -connect my-svc:443 -cert tls.crt -key tls.key -CAfile ca.crt

# STARTTLS protocols
openssl s_client -starttls smtp -connect mail.example.com:587

# Decode a certificate stored in a Kubernetes Secret
kubectl get secret my-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text
```

Look for `Verify return code: 0 (ok)` at the end of an `s_client` run. Anything else tells you why verification
failed (unknown CA, expired, wrong hostname).

## `iperf3`

**Package:** `iperf3` · **Needs:** nothing special

Measures network throughput between two points. You need an `iperf3` server on one side, so run this image in
two places.

```sh
# Server: a standalone debug pod
kubectl run iperf-server --image=ghcr.io/ngpayyappilly/k8s-debug:latest --restart=Never -- iperf3 -s

# Client: from the ephemeral container in the pod you are investigating
iperf3 -c <iperf-server-pod-ip>          # throughput
iperf3 -c <ip> -R                         # reverse direction
iperf3 -c <ip> -P 4                       # 4 parallel streams
iperf3 -c <ip> -u -b 100M                 # UDP at 100 Mbit/s, shows loss and jitter
```

Remember to `kubectl delete pod iperf-server` afterwards. Comparing same-node, cross-node and cross-zone
results is a fast way to find an overlay-network or MTU problem.

## `ping`

**Package:** `iputils-ping` · **Needs:** `NET_RAW` (in the default capabilities)

ICMP echo. Checks basic IP reachability and latency.

```sh
ping -c 4 10.244.2.9

# Find the path MTU: increase -s until it fails with "message too long"
ping -c 2 -M do -s 1472 10.244.2.9
```

!!! warning "Services do not answer ping"
    A Service's ClusterIP is a virtual address handled by `kube-proxy` or the CNI, usually for TCP/UDP ports
    only. `ping <cluster-ip>` failing proves nothing. Ping pod IPs and node IPs, and use [`nc`](#nc)
    or [`curl`](#curl) for Services. Many networks also drop ICMP.

## `tracepath`

**Package:** `iputils-tracepath` · **Needs:** nothing special

Traces the path and reports the discovered **path MTU** at each hop, with no special permissions.

```sh
tracepath -n 10.244.2.9
```

A line such as `pmtu 1450` shows the effective MTU. If it is lower than your pod's `eth0` MTU, large packets
will be dropped or fragmented (check with [`ip`](network-stack.md#ip)).

## `traceroute`

**Package:** `traceroute` · **Needs:** `NET_RAW` for ICMP and TCP modes

Shows each router between you and a destination.

```sh
traceroute -n 8.8.8.8
traceroute -n -T -p 443 example.com    # TCP SYN probes, passes more firewalls
traceroute -n -I example.com           # ICMP probes
```

Inside a cluster you will typically see the node, then the node's gateway. Stars (`* * *`) mean a hop that
does not answer, not necessarily a failure.

## `mtr`

**Package:** `mtr-tiny` · **Needs:** `NET_RAW`

`traceroute` and `ping` combined: per-hop packet loss and latency over many probes. This build has no
graphical interface, so use the report mode.

```sh
mtr -rwn -c 20 10.244.2.9              # report: 20 probes, wide, numeric
mtr -rwn -T -P 443 -c 20 example.com   # TCP probes to port 443
```

Read loss from the **last** hop. Loss in a middle hop that does not continue to the end is usually that router
rate-limiting ICMP, not a real problem.

## `nmap`

**Package:** `nmap` · **Needs:** nothing special for TCP connect scans, `NET_RAW` for others

A port scanner and service detector. Use it on systems you are authorised to test, and remember it generates a
lot of traffic that may trip alerts.

```sh
# Which of these ports are open? (-Pn skips host discovery, -n skips DNS)
nmap -Pn -n -p 80,443,8080 10.244.2.9

# What is running on them?
nmap -Pn -n -sV -p 1-1024 10.244.2.9

# Inspect a TLS certificate and supported ciphers
nmap -Pn -p 443 --script ssl-cert,ssl-enum-ciphers my-svc.my-ns.svc.cluster.local

# Find hosts on a small range (e.g. who answers in a pod CIDR slice)
nmap -sn 10.244.2.0/28
```

If `nc -zv` answers your question, use that. `nmap` is for when you do not know which port to ask about.
