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
# kubectl (checksum verified)
RUN set -eux; \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod +x /usr/local/bin/kubectl

# yq (YAML processor)
RUN set -eux; \
    curl -fsSLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}"; \
    chmod +x /usr/local/bin/yq

# grpcurl (gRPC debugging; release uses x86_64 / arm64 naming)
RUN set -eux; \
    case "${TARGETARCH}" in amd64) A=x86_64;; arm64) A=arm64;; *) echo "unsupported arch ${TARGETARCH}"; exit 1;; esac; \
    curl -fsSL "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_${A}.tar.gz" \
      | tar -xz -C /usr/local/bin grpcurl

# stern (multi-pod log tailing)
RUN set -eux; \
    curl -fsSL "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin stern

# ---- Shell experience -------------------------------------------------------
# kubectl completion is generated once at build time (not on every shell start).
RUN kubectl completion bash > /usr/share/bash-completion/completions/kubectl

COPY motd.txt /etc/motd
# /etc/bash.bashrc applies to any HOME/UID; /root/.bashrc (Ubuntu's skel copy,
# which would reset PS1 afterwards) is replaced with a stub.
COPY bashrc /etc/bash.bashrc
RUN echo '# see /etc/bash.bashrc' > /root/.bashrc

WORKDIR /root
ENTRYPOINT ["/bin/bash"]
