# Troubleshooting

When `kubectl debug` or the tools themselves do not behave.

## Starting a session

### `error: ephemeral containers are disabled for this cluster` or the flag is unknown

Your cluster is older than 1.25, or an administrator disabled the feature, or your `kubectl` is too old. Check
both:

```sh
kubectl version
```

### `forbidden: ... cannot patch resource "pods/ephemeralcontainers"`

You lack RBAC for it. See [RBAC](getting-started/permissions.md#rbac-what-you-need-to-be-allowed-to-do).

### The container shows `ImagePullBackOff` or `ErrImagePull`

```sh
kubectl describe pod <pod> | grep -A5 -i ephemeral
```

- The node cannot reach `ghcr.io`. Mirror the image
  ([Installation](getting-started/installation.md#private-clusters-and-air-gapped-registries)).
- The tag does not exist. `latest` only exists once a stable version has been released. Use `edge` or an exact
  `X.Y.Z`.
- Platform mismatch is not an issue: the image is published for amd64 and arm64.

### `CreateContainerConfigError: container has runAsNonRoot and image will run as root`

The pod or profile requires a non-root user and this image does not set one. Pass a numeric user with
`--custom`. See [Pods that run as non-root](getting-started/permissions.md#pods-that-run-as-non-root).

### Admission rejects the container (`violates PodSecurity`)

The namespace enforces the Baseline or Restricted Pod Security Standard and you asked for more than it allows,
for example `sysadmin`. Use a less privileged profile (`general`, `baseline` or `restricted`). If you need more
privilege than that namespace allows, ask a cluster administrator, or reproduce the problem in a namespace
that permits it.

### I get a prompt but nothing seems to run, or the output is empty

For short one-shot commands the container may finish before your terminal attaches. Read the output from the
logs:

```sh
kubectl debug <pod> --container=probe --image=... --target=<c> -- dig +short my-svc
kubectl logs <pod> -c probe
```

### The session ended and I cannot get back in

If the shell exited, the container is `Terminated`. Ephemeral containers cannot be restarted or deleted, so
start a new one (a new name). If you only lost your terminal and the container is still running, re-attach:

```sh
kubectl attach -it <pod> -c <debug-container-name>
```

## Inside the container

### `ps` shows only my own processes

You started without `--target`, or the container runtime does not support shared process namespaces for
ephemeral containers. `kubectl` prints a warning: *Targeting container ... If you don't see processes from
this container it may be because the container runtime doesn't support this feature.* For a pod you can
restart, `shareProcessNamespace: true` on the pod spec is the supported alternative, or debug a copy with
`--copy-to ... --share-processes`.

### `Operation not permitted` from `strace`, `gdb`, or reading `/proc/<pid>/...`

You lack `SYS_PTRACE`. The default (`general`) profile has it, but `netadmin` does not and a non-root pod
removes everything. See [Permissions](getting-started/permissions.md). Also check that you really are in the same
process namespace as the target (`--target`).

### `tcpdump: You don't have permission to perform this capture on that device`

You have no `NET_RAW`. This usually means the pod runs as a non-root user and the debug container inherited that.
Override with `--custom` (see [non-root pods](getting-started/permissions.md#pods-that-run-as-non-root)).

### `kubectl` says `Unauthorized` or `forbidden` from inside the container

Ephemeral containers have no service account token. Borrow the target's, or supply your own. See
[`kubectl`](tools/kubernetes.md#kubectl).

### `iptables -L` is empty on a node that obviously has Services

You are looking through the wrong back end. Try `iptables-legacy` and `nft list ruleset`. See
[`iptables`](tools/packets-firewall.md#iptables).

### `bpftrace` or `dmesg` fails with permission errors

They need a privileged container. Use `--profile=sysadmin`, on a node session if possible. Hardened or managed
platforms may forbid that entirely.

### `iotop` prints `task_delayacct is 0`

The kernel is not collecting per-task I/O delay accounting. Use `pidstat -d` instead, or enable
`kernel.task_delayacct` on the node.

### Usernames in `ps` or `ls -l` look wrong

They are translated with **this image's** `/etc/passwd`. Use numeric IDs (`ps -eo pid,uid,comm`).

### `top`, `free` and `/proc/meminfo` show far more memory than my limit

They show the node's. Read the cgroup files. See [the throttling recipe](recipes.md#the-pod-is-slow-or-being-throttled).

## Cleanup

- **Ephemeral containers stay in the pod spec.** They disappear when the pod is replaced (a rollout, a
  reschedule). You cannot remove one by hand.
- **Copies from `--copy-to`** are ordinary pods: `kubectl delete pod <pod>-debug`.
- **Node debug pods** are ordinary pods named `node-debugger-<node>-<suffix>`: delete them when finished.
- **Standalone debug pods** (`kubectl run`): use `--rm`, or delete them.

## Still stuck?

Search or open an issue at [github.com/ngpayyappilly/k8s-debug/issues](https://github.com/ngpayyappilly/k8s-debug/issues).
Include the `kubectl version`, the exact command, the profile you used, and the error text.
