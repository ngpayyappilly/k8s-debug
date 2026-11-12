# syntax=docker/dockerfile:1.7
#
# k8s-debug: an image for `kubectl debug` ephemeral containers.
# Multi-arch (amd64/arm64). Ubuntu base for glibc + full apt ecosystem
# (gdb/strace/bpftrace behave better on glibc than on musl).

FROM ubuntu:24.04

# Fail the build if any stage of a `curl | tar` pipe fails.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.36.1
ARG YQ_VERSION=v4.47.1
ARG GRPCURL_VERSION=1.9.3
ARG STERN_VERSION=1.33.0
# Set to "true" to bake in redis/postgres/mysql CLI clients (adds ~60MB).
ARG INSTALL_DB_CLIENTS=false

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TERM=xterm-256color

# ---- OS packages ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      # shell / editors / basics
      bash bash-completion ca-certificates curl wget less vim-tiny nano file tree \
      jq unzip xz-utils git openssh-client gnupg \
      # networking
      iproute2 iputils-ping iputils-tracepath traceroute mtr-tiny \
      dnsutils netcat-openbsd socat tcpdump nmap ncat \
      iptables nftables ipset conntrack ethtool net-tools arping \
      iperf3 openssl ldnsutils bridge-utils \
      # process / system inspection
      procps psmisc lsof htop sysstat iotop-c strace ltrace gdb \
      bpftrace util-linux kmod pciutils \
      # misc
      python3 \
    && if [ "$INSTALL_DB_CLIENTS" = "true" ]; then \
         apt-get install -y --no-install-recommends redis-tools postgresql-client mysql-client; \
       fi \
    && rm -rf /var/lib/apt/lists/*

# ---- Static binaries --------------------------------------------------------
# All binaries below are checksum verified against the upstream release.
# kubectl
RUN set -eux; \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod +x /usr/local/bin/kubectl

# yq (YAML processor). The checksums file lists many hash algorithms per binary;
# the column for SHA-256 is found via checksums_hashes_order.
RUN set -eux; \
    base="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}"; \
    curl -fsSLo /tmp/yq "${base}/yq_linux_${TARGETARCH}"; \
    col="$(curl -fsSL "${base}/checksums_hashes_order" | grep -nx 'SHA-256' | cut -d: -f1)"; \
    want="$(curl -fsSL "${base}/checksums" | awk -v f="yq_linux_${TARGETARCH}" -v c="$((col + 1))" '$1 == f {print $c}')"; \
    test -n "$want"; \
    echo "${want}  /tmp/yq" | sha256sum -c -; \
    install -m 0755 /tmp/yq /usr/local/bin/yq; \
    rm -f /tmp/yq

# grpcurl (gRPC debugging; release uses x86_64 / arm64 naming), checksum verified
RUN set -eux; \
    case "${TARGETARCH}" in amd64) A=x86_64;; arm64) A=arm64;; *) echo "unsupported arch ${TARGETARCH}"; exit 1;; esac; \
    base="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}"; \
    f="grpcurl_${GRPCURL_VERSION}_linux_${A}.tar.gz"; \
    curl -fsSLo "/tmp/${f}" "${base}/${f}"; \
    curl -fsSL "${base}/grpcurl_${GRPCURL_VERSION}_checksums.txt" | grep " ${f}\$" > /tmp/grpcurl.sha256; \
    (cd /tmp && sha256sum -c grpcurl.sha256); \
    tar -xz -C /usr/local/bin -f "/tmp/${f}" grpcurl; \
    rm -f "/tmp/${f}" /tmp/grpcurl.sha256

# stern (multi-pod log tailing), checksum verified
RUN set -eux; \
    base="https://github.com/stern/stern/releases/download/v${STERN_VERSION}"; \
    f="stern_${STERN_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl -fsSLo "/tmp/${f}" "${base}/${f}"; \
    curl -fsSL "${base}/checksums.txt" | grep " ${f}\$" > /tmp/stern.sha256; \
    (cd /tmp && sha256sum -c stern.sha256); \
    tar -xz -C /usr/local/bin -f "/tmp/${f}" stern; \
    rm -f "/tmp/${f}" /tmp/stern.sha256

# ---- Shell experience -------------------------------------------------------
COPY motd.txt /etc/motd
COPY bashrc /root/.bashrc

WORKDIR /root
ENTRYPOINT ["/bin/bash"]
