# Permissions and profiles

What a debug container can do depends on three things: the **RBAC** you have, the **profile** you start it
with, and the **security context of the pod** you attach to. Most "it doesn't work" reports come from one of
these.

## RBAC: what you need to be allowed to do

| Action | Verb on resource |
|---|---|
| Add an ephemeral container | `patch` (or `update`) on `pods/ephemeralcontainers`, plus `get` on `pods` |
| Open a shell (`-it`) | `create` on `pods/attach` |
| `kubectl exec` into the debug container | `create` on `pods/exec` |
| Read its output with `kubectl logs` | `get` on `pods/log` |
| Debug a node, or `--copy-to` a pod | `create` on `pods` |

Check yours with:

```sh
kubectl auth can-i patch pods/ephemeralcontainers -n <namespace>
kubectl auth can-i create pods/attach -n <namespace>
```

## Profiles

`kubectl debug --profile=<name>` picks the security settings of the container it creates. The values below
were observed with kubectl 1.36 against a containerd node.

| Profile | Capabilities (effective) | Use it for |
|---|---|---|
| `general` (default) | the runtime defaults **plus `SYS_PTRACE`** | Most debugging: shell, network tools, `strace`, `gdb`, reading the target's files |
| `netadmin` | the runtime defaults **plus `NET_ADMIN`**, and **without** `SYS_PTRACE` | Changing network config: `iptables`, `conntrack`, `ip link`/`ip route` writes, promiscuous capture |
| `sysadmin` | **all** capabilities, privileged | `bpftrace`, `dmesg`, kernel and node level work |
| `baseline` | for namespaces enforcing the Baseline Pod Security Standard | Clusters that reject the others |
| `restricted` | for namespaces enforcing the Restricted Pod Security Standard | Strict clusters. Needs a non-root user, see below |

The runtime defaults already include `NET_RAW`, `CHOWN`, `KILL`, `SETUID`, `SETGID`, `NET_BIND_SERVICE` and a few others.
That is why **`tcpdump`, `ping` and `traceroute` work with the default profile**.

!!! note "`netadmin` removes `SYS_PTRACE`"
    Profiles are alternatives, not layers. Under `netadmin` you can reconfigure the network but `strace` and
    `gdb` against other processes may fail. To get both, use `--custom` (below).

### On a node

`kubectl debug node/<name>` always mounts the node's filesystem at `/host` and shares the node's network and
process namespaces. `general` gives the default capabilities; `sysadmin` additionally makes the pod
privileged. Use `sysadmin` for `nsenter`, `dmesg`, `bpftrace` and anything that touches the kernel.

## Adding or changing capabilities with `--custom`

`--custom` takes a JSON file that is merged over the container `kubectl` generates:

```sh
cat > caps.json <<'EOF'
{"securityContext": {"capabilities": {"add": ["SYS_PTRACE", "NET_ADMIN"]}}}
EOF

kubectl debug -it <pod> --image=ghcr.io/ngpayyappilly/k8s-debug:latest \
  --target=<container> --profile=general --custom=caps.json
```

!!! warning "`--custom` replaces lists, it does not append to them"
    The `add` list in your file **replaces** the profile's list. The profile `general` adds `SYS_PTRACE`;
    if your file adds only `NET_ADMIN`, you get `NET_ADMIN` and **lose** `SYS_PTRACE`. List every capability
    you want.

## Pods that run as non-root

An ephemeral container inherits the pod-level `securityContext`. If the pod sets
`runAsUser: 1000` and `runAsNonRoot: true`, your debug container runs as UID 1000 with **no
capabilities at all**. In that situation:

- `tcpdump` fails with *You don't have permission to perform this capture*
- you cannot read `/proc/<pid>/root` of the target (*Permission denied*)

Override the user with `--custom`:

```sh
echo '{"securityContext": {"runAsUser": 0, "runAsNonRoot": false}}' > root.json

kubectl debug -it <pod> --image=ghcr.io/ngpayyappilly/k8s-debug:latest \
  --target=<container> --custom=root.json
```

If the namespace enforces the Restricted Pod Security Standard, root is not allowed. The image itself has no
non-root user set, so `--profile=restricted` on its own fails with `CreateContainerConfigError`
(*container has runAsNonRoot and image will run as root*). Give it a numeric user:

```sh
echo '{"securityContext": {"runAsUser": 1000}}' > uid.json
kubectl debug -it <pod> --image=... --target=<container> --profile=restricted --custom=uid.json
```

You will then have no capabilities, which is still enough for `curl`, `dig`, `nslookup`, `ss`, `openssl`,
`jq`, `kubectl` and reading anything the pod's own user can read, but not for packet capture or `strace`.

## Which tools need what

| Needs | Tools |
|---|---|
| Nothing special | `curl` `wget` `nc` `ncat` `socat` `openssl` `iperf3` `dig` `nslookup` `drill` `ip` (read) `ss` `ps` `top` `free` `lsof` `jq` `yq` `kubectl` `stern` `grpcurl` `git` `python3` |
| `NET_RAW` (in the runtime defaults) | `ping`, `traceroute` (ICMP and TCP modes), `mtr`, `tcpdump`, `arping`, `nmap` raw scans |
| `SYS_PTRACE` (in `general`) | `strace` `ltrace` `gdb` attaching to another process; reading `/proc/<pid>/root`, `/proc/<pid>/environ` of processes running as a different user |
| `NET_ADMIN` (in `netadmin`) | `iptables`/`nft`/`ipset` changes, `conntrack`, `ip link`/`ip route` changes, `ethtool` writes, `tcpdump` promiscuous mode (use `-p` to avoid it) |
| `SYS_ADMIN` and more (in `sysadmin`) | `bpftrace`, `dmesg`, `nsenter` into other namespaces, mounting, `iotop` |
| `--target` (shared processes) | seeing the app's processes in `ps`, `lsof`, `strace -p`, `/proc/<pid>/root` |

## Security notes

- **Sessions are recorded.** `kubectl debug -it` prints
  *All commands and output from this session will be recorded in container logs, including credentials and
  sensitive information passed through the command prompt.* Do not paste secrets into the shell.
- **No removal.** An ephemeral container cannot be deleted or edited. It stays in the pod spec (as
  `Terminated`) until the pod is replaced. Name your containers and expect that history to remain.
- **Service account token.** Ephemeral containers do **not** get the pod's service account token mounted. See
  [kubectl](../tools/kubernetes.md#kubectl) for how to borrow the target's.
- **Audit.** Adding an ephemeral container is an API write (`pods/ephemeralcontainers`) and appears in the
  Kubernetes audit log.
- **Least privilege.** Start with the default profile. Reach for `sysadmin` only when you need the kernel.
