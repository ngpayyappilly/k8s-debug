# Installation

There is nothing to install. The image is public and Kubernetes pulls it when you run `kubectl debug`.
This page covers what you need, every way to start a session, and how to pin, mirror or build the image.

## Requirements

| What | Version | Why |
|---|---|---|
| Kubernetes | 1.25+ | Ephemeral containers are GA from 1.25 |
| `kubectl` | 1.31+ recommended | Older versions lack `--custom` and some `--profile` values |
| Container runtime | containerd or CRI-O | `--target` (shared process namespace) needs runtime support |
| Node OS | Linux | The image is Linux only |
| RBAC | see [Permissions](permissions.md#rbac-what-you-need-to-be-allowed-to-do) | You need to be allowed to add ephemeral containers |

Check your client and server:

```sh
kubectl version
```

## Image and tags

```text
ghcr.io/ngpayyappilly/k8s-debug
```

| Tag | Meaning |
|---|---|
| `1.2.3` | An exact release. **Use this in runbooks and automation.** |
| `1.2` | Latest patch of a minor version |
| `1` | Latest minor of a major version (not published for `0.x`) |
| `latest` | The newest stable release (pre-releases are excluded) |
| `edge` | The tip of `main`. Unreleased, may change at any time |
| `sha-abc1234` | A specific commit on `main` |

Releases are listed on the [GitHub releases and tags page](https://github.com/ngpayyappilly/k8s-debug/tags).

!!! note "No `latest` yet?"
    `latest` appears with the first stable version tag. Until then use `edge`.

## Ways to use it

### 1. Attach to a running pod (the usual way)

```sh
kubectl debug -it <pod> -n <namespace> \
  --image=ghcr.io/ngpayyappilly/k8s-debug:latest \
  --target=<container>
```

- Adds an ephemeral container to the **existing** pod. Nothing restarts.
- Shares the pod's network namespace always, and the target container's **process** namespace because of
  `--target`.
- Without `--target` you only share the network.
- Name it with `--container=my-debug` so you can find it later (`kubectl logs <pod> -c my-debug`).

By default `kubectl` uses the `general` profile, which includes `SYS_PTRACE` (so `strace` and `gdb` work).
See [Permissions and profiles](permissions.md) for the others.

### 2. Debug a pod that keeps crashing

An ephemeral container needs a running pod. If the app crashes immediately, debug a **copy** instead:

```sh
kubectl debug <pod> -it --copy-to=<pod>-debug \
  --image=ghcr.io/ngpayyappilly/k8s-debug:latest \
  --share-processes
```

Variations:

```sh
# Replace the crashing container's command so it stays up, then inspect it
kubectl debug <pod> -it --copy-to=<pod>-debug --container=<container> -- sleep 1d

# Swap the app image for the debug image in the copy
kubectl debug <pod> -it --copy-to=<pod>-debug --set-image=<container>=ghcr.io/ngpayyappilly/k8s-debug:latest

# Remove the original pod once the copy exists
kubectl debug <pod> -it --copy-to=<pod>-debug --replace --image=...
```

Delete the copy when you are done: `kubectl delete pod <pod>-debug`.

### 3. Debug a node

```sh
kubectl debug node/<node-name> -it \
  --image=ghcr.io/ngpayyappilly/k8s-debug:latest \
  --profile=sysadmin
```

This creates a pod on that node. The node's root filesystem is mounted at `/host`, and the pod uses the
node's network and process namespaces. Use it for kubelet, CNI, `kube-proxy` and kernel problems:

```sh
ls /host/var/log/pods
nsenter -t 1 -m -u -i -n -p -- systemctl status kubelet
iptables -t nat -S KUBE-SERVICES | head
```

Delete the pod afterwards: `kubectl delete pod node-debugger-<node>-<suffix>`.

### 4. A standalone debug pod

For network tests between pods (for example `iperf3`), or to test from a namespace without touching an
existing workload:

```sh
kubectl run debug --rm -it --image=ghcr.io/ngpayyappilly/k8s-debug:latest -n <namespace> -- bash
```

### 5. Locally with Docker

The same toolbox on your laptop, handy for trying commands or inspecting files:

```sh
docker run --rm -it ghcr.io/ngpayyappilly/k8s-debug:latest

# Share the host network (Linux) or mount a kubeconfig
docker run --rm -it --network host ghcr.io/ngpayyappilly/k8s-debug:latest
docker run --rm -it -v ~/.kube:/root/.kube:ro ghcr.io/ngpayyappilly/k8s-debug:latest
```

### Make it a shell function

```sh
# ~/.bashrc or ~/.zshrc
kdebug() {  # kdebug <pod> <container> [namespace]
  kubectl debug -it "$1" -n "${3:-default}" --target="$2" \
    --image=ghcr.io/ngpayyappilly/k8s-debug:latest
}
```

## Private clusters and air-gapped registries

Nodes must be able to pull the image. If they cannot reach `ghcr.io`, mirror it to a registry they can reach:

```sh
# Copies every platform, preserving the multi-arch manifest
crane copy ghcr.io/ngpayyappilly/k8s-debug:1.2.3 registry.example.com/tools/k8s-debug:1.2.3
# or
docker buildx imagetools create -t registry.example.com/tools/k8s-debug:1.2.3 \
  ghcr.io/ngpayyappilly/k8s-debug:1.2.3
```

Then use `--image=registry.example.com/tools/k8s-debug:1.2.3`. Ephemeral containers cannot set
`imagePullSecrets`. They use the pod's existing pull secrets, so a private mirror must be pullable with the
secrets the pod already has (or be public inside the cluster).

## Build it yourself

```sh
git clone https://github.com/ngpayyappilly/k8s-debug && cd k8s-debug
docker build -t k8s-debug:dev .

# Optional extras
docker build --build-arg INSTALL_DB_CLIENTS=true -t k8s-debug:db .       # redis-cli, psql, mysql
docker build --build-arg KUBECTL_VERSION=v1.34.2 -t k8s-debug:k134 .     # match your cluster

scripts/smoke-test.sh k8s-debug:dev
```

| Build argument | Default | Meaning |
|---|---|---|
| `KUBECTL_VERSION` | `v1.36.1` | `kubectl` release to install. Stay within one minor of your cluster |
| `YQ_VERSION` | `v4.47.1` | `yq` release |
| `GRPCURL_VERSION` | `1.9.3` | `grpcurl` release (no `v` prefix) |
| `STERN_VERSION` | `1.33.0` | `stern` release (no `v` prefix) |
| `INSTALL_DB_CLIENTS` | `false` | Add `redis-cli`, `psql` and `mysql` (about 60 MB) |

`kubectl`, `yq`, `grpcurl` and `stern` are downloaded from their upstream releases and **checksum verified**
during the build. Everything else comes from Ubuntu's apt repositories.

## Verify what you pulled

```sh
# Platforms and digest
docker buildx imagetools inspect ghcr.io/ngpayyappilly/k8s-debug:1.2.3

# Provenance and SBOM attestations published with each release build
docker buildx imagetools inspect ghcr.io/ngpayyappilly/k8s-debug:1.2.3 --format '{{ json .Provenance }}'
docker buildx imagetools inspect ghcr.io/ngpayyappilly/k8s-debug:1.2.3 --format '{{ json .SBOM }}'

# Exact versions of the apt-installed tools in a given tag
docker run --rm --entrypoint dpkg ghcr.io/ngpayyappilly/k8s-debug:1.2.3 -l
```

For anything security sensitive, pin by digest (`image@sha256:...`) rather than by tag.

## Next

- [Permissions and profiles](permissions.md): what the container is allowed to do, and how to grant more.
- [Tools](../tools/index.md): documentation for every utility.
- [Troubleshooting](../troubleshooting.md): when `kubectl debug` does not behave.
