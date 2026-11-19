# DNS

Most Kubernetes "network problems" are DNS problems. These tools query DNS directly so you can see what the
resolver sees. Start by looking at the pod's resolver configuration:

```sh
cat /etc/resolv.conf
```

```text
search my-ns.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

- `nameserver` is the cluster DNS Service (CoreDNS or kube-dns).
- `search` lists the suffixes tried for short names.
- `ndots:5` means any name with **fewer than 5 dots** is tried against every search suffix first. A lookup of
  `api.example.com` (2 dots) can cost several failed queries before the real one. This is the usual cause of
  slow or flaky external DNS in pods. See the [DNS recipe](../recipes.md#dns-is-slow-or-failing).

!!! note
    The ephemeral container is part of the pod, so it uses the pod's DNS settings. `/etc/resolv.conf` is the
    same one the app uses.

## `dig`

**Package:** `dnsutils` (BIND tools) · **Needs:** nothing special

The reference DNS client. It shows the full answer, flags, timing and which server replied.

```sh
# Resolve a Service
dig my-svc.my-ns.svc.cluster.local

# Just the answer
dig +short my-svc.my-ns.svc.cluster.local

# Ask a specific server (CoreDNS service IP, a node-local cache, or an upstream)
dig @10.96.0.10 my-svc.my-ns.svc.cluster.local
dig @8.8.8.8 example.com

# Use the search list, as the app's resolver does (dig ignores it by default)
dig +search my-svc

# Headless Service: one A record per pod
dig +short my-headless.my-ns.svc.cluster.local

# SRV records (named ports)
dig +short SRV _http._tcp.my-svc.my-ns.svc.cluster.local

# Reverse lookup of a pod or service IP
dig +short -x 10.244.2.9

# Force TCP (tests whether large responses or TCP/53 are blocked)
dig +tcp my-svc.my-ns.svc.cluster.local

# Only the answer section plus query time, to measure latency
dig +noall +answer +stats example.com

# Walk the delegation from the root
dig +trace example.com
```

Read the `status:` in the header: `NOERROR` with an empty answer means the name exists but has no record of that
type; `NXDOMAIN` means it does not exist; `SERVFAIL` means the server could not answer (often an upstream
problem). `;; connection timed out; no servers could be reached` means you cannot reach the DNS server at all.

## `nslookup`

**Package:** `dnsutils` · **Needs:** nothing special

An older, simpler client. Unlike `dig` it **does** apply the search list, so it is handy for "does the short
name work?".

```sh
nslookup kubernetes.default
nslookup my-svc.my-ns 10.96.0.10          # optional server as the last argument
nslookup -type=SRV _http._tcp.my-svc.my-ns.svc.cluster.local
```

`nslookup` prints `Server:` and `Address:` first. That is the resolver it used, so you can confirm which DNS
server the pod is really talking to.

## `drill`

**Package:** `ldnsutils` · **Needs:** nothing special

A `dig`-like tool from the `ldns` library with strong DNSSEC support.

```sh
drill example.com @10.96.0.10
drill -T example.com              # trace from the root
drill -D example.com              # request DNSSEC records
drill -S example.com              # chase DNSSEC signatures to the root
```

Use it when you need to debug DNSSEC validation. For everything else, [`dig`](#dig) is more familiar.
