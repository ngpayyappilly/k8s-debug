# Kubernetes and data

Tools for talking to the cluster API, tailing logs, calling gRPC services and slicing JSON and YAML.

## `kubectl`

**Version:** v1.36.1 (checksum verified) · **Needs:** credentials, see below. Alias: `k`, with tab completion.

The Kubernetes command-line client, available **inside** the debug container so you can query the cluster
from the pod's own point of view: its network, its DNS, its NetworkPolicy.

!!! important "No credentials by default"
    An ephemeral container does **not** get the pod's service account token mounted, and there is no
    kubeconfig. A bare `kubectl get pods` will fail with *Unauthorized* or *forbidden*. The environment does
    contain the cluster address (`KUBERNETES_SERVICE_HOST`), but no identity.

**Borrow the target container's service account** (needs `--target` and the default `SYS_PTRACE`):

```sh
P=$(pgrep -o <app-name>)                  # or 1
S=/proc/$P/root/var/run/secrets/kubernetes.io/serviceaccount

kubectl --server=https://kubernetes.default.svc \
        --certificate-authority=$S/ca.crt \
        --token="$(cat $S/token)" \
        get pods -n "$(cat $S/namespace)"
```

This acts **as the application**, which is exactly what you want when asking *"can this pod's identity do X?"*:

```sh
alias ks='kubectl --server=https://kubernetes.default.svc --certificate-authority=$S/ca.crt --token="$(cat $S/token)"'
ks auth can-i list secrets -n "$(cat $S/namespace)"
ks auth can-i --list
```

If the pod does not mount a token (`automountServiceAccountToken: false`), there is nothing to borrow.
Supply your own kubeconfig or token instead, for example `kubectl --token=<token> ...`, and treat it as the
secret it is: **an interactive session is recorded in the container logs**.

Other uses:

```sh
kubectl get endpointslices -l kubernetes.io/service-name=my-svc    # which pods back a Service?
kubectl get pod <pod> -o wide                                      # IP, node
kubectl describe pod <pod>                                         # events, probe failures
kubectl logs <pod> --previous                                      # logs of the crashed container
kubectl get events --sort-by=.lastTimestamp | tail -20
```

`kubectl` supports one minor version of skew against the API server. If your cluster is further away than that,
build a matching image (`--build-arg KUBECTL_VERSION=...`, see
[Installation](../getting-started/installation.md#build-it-yourself)).

## `stern`

**Version:** 1.33.0 (checksum verified) · **Needs:** credentials (see [`kubectl`](#kubectl)) with `get`, `list`,
`watch` on pods and `get` on `pods/log`

Tails logs from **many pods and containers at once**, color-coded by pod. Ideal for a Deployment with many
replicas or when a request crosses services.

```sh
stern my-app -n my-ns                          # every pod whose name matches "my-app"
stern -l app=my-app -n my-ns --since 5m        # by label, last 5 minutes
stern my-app -c sidecar --tail 20              # one container, last 20 lines each
stern my-app -i 'ERROR|WARN' -e healthz        # include / exclude by regex
stern my-app --timestamps -o raw               # raw lines, add timestamps
stern -A 'coredns|kube-dns' --namespace kube-system
```

## `grpcurl`

**Version:** 1.9.3 (checksum verified) · **Needs:** nothing special

`curl` for gRPC. If the server enables **reflection**, no `.proto` files are needed.

```sh
# What services does it expose?
grpcurl -plaintext my-svc.my-ns.svc.cluster.local:50051 list

# Methods of one service, and the shape of a message
grpcurl -plaintext my-svc:50051 list my.pkg.Greeter
grpcurl -plaintext my-svc:50051 describe my.pkg.HelloRequest

# Call a method
grpcurl -plaintext -d '{"name": "world"}' my-svc:50051 my.pkg.Greeter/SayHello

# Standard health check
grpcurl -plaintext my-svc:50051 grpc.health.v1.Health/Check

# TLS: verify with a CA, or skip verification (diagnosis only)
grpcurl -cacert ca.crt my-svc.example.com:443 list
grpcurl -insecure my-svc.example.com:443 list

# Without reflection, supply the proto
grpcurl -plaintext -import-path ./protos -proto greeter.proto -d '{}' my-svc:50051 my.pkg.Greeter/SayHello
```

`-plaintext` means no TLS. If you get *tls: first record does not look like a TLS handshake*, you used TLS
against a plaintext server. If you get a connection reset, the opposite. A mesh sidecar may be in the way, so
check with [`ss`](network-stack.md#ss).

## `yq`

**Version:** mikefarah/yq v4.47.1 (checksum verified) · **Needs:** nothing special

A `jq`-like processor for YAML (and also JSON, XML, TOML, CSV). Note this is the Go `yq` by Mike Farah, not
the Python wrapper of the same name, so its syntax is different.

```sh
kubectl get pod <pod> -o yaml | yq '.spec.containers[].image'
kubectl get deploy my-app -o yaml | yq '.spec.template.spec.containers[] | {"name": .name, "resources": .resources}'
yq '.metadata.labels' manifest.yaml
yq -i '.spec.replicas = 3' manifest.yaml                  # edit in place
yq -o=json '.' values.yaml                                 # convert YAML to JSON
yq eval-all 'select(.kind == "Service") | .metadata.name' *.yaml    # across many files / documents
```

## `jq`

**Package:** `jq` · **Needs:** nothing special

The standard JSON processor. `kubectl -o json` plus `jq` answers most "which of these..." questions.

```sh
# Pods that are not Running
kubectl get pods -A -o json | jq -r '.items[] | select(.status.phase != "Running") | "\(.metadata.namespace)/\(.metadata.name) \(.status.phase)"'

# Restart counts and last termination reason
kubectl get pod <pod> -o json | jq '.status.containerStatuses[] | {name, restartCount, last: .lastState.terminated}'

# Pods on a given node
kubectl get pods -A -o json | jq -r --arg n node-1 '.items[] | select(.spec.nodeName == $n) | .metadata.name'

# Decode every key of a Secret
kubectl get secret my-secret -o json | jq -r '.data | map_values(@base64d)'

# Pretty-print or filter an API response
curl -s http://localhost:8080/status | jq '.errors[]?'
```

## Optional database clients

Not in the published image. Build with `--build-arg INSTALL_DB_CLIENTS=true` to add them, useful for checking
connectivity and credentials to a database from the application's own network position.

### `redis-cli`

```sh
redis-cli -h redis.my-ns.svc.cluster.local -p 6379 ping
redis-cli -h redis --tls --cacert ca.crt info clients
```

### `psql`

```sh
psql "host=postgres.my-ns.svc.cluster.local user=app dbname=app sslmode=require" -c 'select 1'
```

### `mysql`

```sh
mysql -h mysql.my-ns.svc.cluster.local -u app -p -e 'select 1'
```

Without those clients, [`nc -zv`](connectivity.md#nc) still tells you whether the port is reachable.
